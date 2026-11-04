"""
Serializers DRF du projet SGSUS.

Ressources des autres lots (contrats conservés) : Campaign, User, Student,
InternshipFolder.

Ressources du module planification (Tâche 4) : Salle (Room), Jury,
JuryMember, Defense — avec validation métier :

* horaires cohérents et normalisés en UTC (NFR04) ;
* contrôle complet des conflits EXG01 délégué au service
  `api.services.conflicts` (salle, jury, membres croisés, dossier recevable).
"""

from rest_framework import serializers

from api.models import (
    Campaign,
    Defense,
    InternshipFolder,
    Jury,
    JuryMember,
    Room,
    Student,
    User,
)
from api.services import conflicts


# ---------------------------------------------------------------------------
# Ressources des autres lots (Tâche 1 / Tâche 2)
# ---------------------------------------------------------------------------

class CampaignSerializer(serializers.ModelSerializer):
    """Campagnes de stage/soutenance (Tâche 2)."""

    class Meta:
        model = Campaign
        fields = "__all__"


class UserSerializer(serializers.ModelSerializer):
    """Utilisateurs et rôles (Tâche 1)."""

    class Meta:
        model = User
        fields = ["id", "username", "email", "role", "first_name", "last_name"]


class StudentSerializer(serializers.ModelSerializer):
    """Étudiants (Tâche 2)."""

    class Meta:
        model = Student
        fields = "__all__"


class InternshipFolderSerializer(serializers.ModelSerializer):
    """Dossiers de stage (table internship_folder)."""

    class Meta:
        model = InternshipFolder
        fields = "__all__"


# ---------------------------------------------------------------------------
# Salles (ajout Tâche 4)
# ---------------------------------------------------------------------------

class SalleSerializer(serializers.ModelSerializer):
    """Catalogue des salles de soutenance."""

    class Meta:
        model = Room
        fields = ["id", "name", "capacity", "is_active"]

    def validate_name(self, value):
        return value.strip()

    def validate_capacity(self, value):
        if value is None or value <= 0:
            raise serializers.ValidationError(
                "La capacité de la salle doit être un entier strictement positif."
            )
        return value


# ---------------------------------------------------------------------------
# Jurys et membres (Tâche 4 / F04)
# ---------------------------------------------------------------------------

class JuryMemberSerializer(serializers.ModelSerializer):
    """Membre d'un jury (président, rapporteur, examinateur)."""

    ROLES_VALIDES = {"president", "rapporteur", "examinateur"}

    class Meta:
        model = JuryMember
        fields = ["id", "jury", "member_name", "role_in_jury"]

    def validate_member_name(self, value):
        return value.strip()

    def validate_role_in_jury(self, value):
        role = value.strip().lower()
        if role not in self.ROLES_VALIDES:
            raise serializers.ValidationError(
                "Rôle invalide : choisir parmi 'president', 'rapporteur', "
                "'examinateur'."
            )
        return role


class JurySerializer(serializers.ModelSerializer):
    """Jury de soutenance avec ses membres (lecture imbriquée)."""

    members = JuryMemberSerializer(many=True, read_only=True)

    class Meta:
        model = Jury
        fields = ["id", "name", "is_complete", "members"]

    def validate_name(self, value):
        return value.strip()


# ---------------------------------------------------------------------------
# Soutenances (F05) — validation des horaires + contrôle des conflits
# ---------------------------------------------------------------------------

class DefenseSerializer(serializers.ModelSerializer):
    """
    Soutenance planifiée.

    L'intervalle PostgreSQL `slot_range` (tstzrange) est exposé et accepté
    sous la forme de deux champs `slot_start` / `slot_end` (ISO 8601),
    plus simple à consommer côté Flutter.
    """

    slot_start = serializers.DateTimeField(
        write_only=True,
        help_text="Début du créneau, ISO 8601 (ex. 2026-07-10T08:00:00Z).",
    )
    slot_end = serializers.DateTimeField(
        write_only=True,
        help_text="Fin du créneau, ISO 8601 (ex. 2026-07-10T10:00:00Z).",
    )
    folder_detail = InternshipFolderSerializer(source="folder", read_only=True)
    jury_detail = JurySerializer(source="jury", read_only=True)

    class Meta:
        model = Defense
        fields = [
            "id",
            "folder",
            "folder_detail",
            "jury",
            "jury_detail",
            "room_name",
            "slot_start",
            "slot_end",
            "status",
        ]

    def validate(self, attrs):
        attrs = super().validate(attrs)
        instance = self.instance  # None à la création, la soutenance en modification.

        # Valeurs effectives : champ fourni sinon valeur actuelle de
        # l'instance (indispensable pour les mises à jour partielles PATCH).
        debut = attrs.get("slot_start") or (
            instance.slot_range.lower if instance else None
        )
        fin = attrs.get("slot_end") or (
            instance.slot_range.upper if instance else None
        )
        dossier = attrs.get("folder") or (instance.folder if instance else None)
        jury = attrs.get("jury") or (instance.jury if instance else None)
        room_name = (attrs.get("room_name") or
                     (instance.room_name if instance else "") or "").strip()

        # 1. Créneau cohérent et normalisé en UTC (construire_creneau lève une
        #    ValidationError si fin <= début ou si la durée est absurde).
        slot = conflicts.construire_creneau(debut, fin)

        # 2. Champs obligatoires.
        if not room_name:
            raise serializers.ValidationError(
                {"room_name": "La salle est obligatoire."}
            )
        attrs["room_name"] = room_name
        if dossier is None:
            raise serializers.ValidationError(
                {"folder": "Le dossier de stage est obligatoire."}
            )
        if jury is None:
            raise serializers.ValidationError(
                {"jury": "Le jury est obligatoire pour planifier une soutenance."}
            )

        # 3. Contrôle métier complet (dossier recevable F03, salle F04/F05,
        #    jury, conflits EXG01 applicatifs). En modification, la soutenance
        #    elle-même est exclue du contrôle de chevauchement.
        defense_exclue_id = instance.pk if instance else None
        conflicts.verifier_toutes_regles(
            dossier.pk, jury.pk, room_name, slot,
            defense_exclue_id=defense_exclue_id,
        )

        # 4. L'intervalle normalisé remplace les deux champs de saisie.
        attrs.pop("slot_start", None)
        attrs.pop("slot_end", None)
        attrs["slot_range"] = slot
        return attrs

    def create(self, validated_data):
        slot_range = validated_data.pop("slot_range")
        return Defense.objects.create(slot_range=slot_range, **validated_data)

    def update(self, instance, validated_data):
        slot_range = validated_data.pop("slot_range", None)
        if slot_range is not None:
            instance.slot_range = slot_range
        return super().update(instance, validated_data)

    def to_representation(self, instance):
        data = super().to_representation(instance)
        slot = instance.slot_range
        if slot is not None:
            debut = slot.lower
            fin = slot.upper
            data["slot_start"] = debut.isoformat() if debut else None
            data["slot_end"] = fin.isoformat() if fin else None
        return data
