"""
Sérialiseurs du module de planification : salles, jurys et soutenances.

Le sérialiseur des soutenances délègue la validation métier (conflits de
salle/jury, recevabilité du dossier, durée maximale…) au service
`api.services.conflicts`, qui reste l'unique source de vérité de ces règles.
"""

from rest_framework import serializers

from api.models import Defense, Jury, JuryMember, Room
from api.services import conflicts

from .academic import InternshipFolderSerializer


class SalleSerializer(serializers.ModelSerializer):
    """Salle de soutenance (nom unique, capacité, disponibilité)."""

    class Meta:
        model = Room
        fields = ['id', 'name', 'capacity', 'is_active']

    def validate_name(self, value):
        """Supprime les espaces superflus pour éviter les doublons visuels."""
        return value.strip()

    def validate_capacity(self, value):
        """
        Vérifie que la capacité est strictement positive.

        Lève :
            ValidationError : capacité nulle, négative ou absente.
        """
        if value is None or value <= 0:
            raise serializers.ValidationError("La capacité de la salle doit être strictement positive.")
        return value


class JuryMemberSerializer(serializers.ModelSerializer):
    """Membre d'un jury, avec un rôle parmi président/rapporteur/examinateur."""

    # Rôles autorisés au sein d'un jury (normalisés en minuscules).
    ROLES_VALIDES = {'president', 'rapporteur', 'examinateur'}

    class Meta:
        model = JuryMember
        fields = ['id', 'jury', 'member_name', 'role_in_jury']

    def validate_member_name(self, value):
        """Supprime les espaces superflus autour du nom."""
        return value.strip()

    def validate_role_in_jury(self, value):
        """
        Normalise puis valide le rôle du membre dans le jury.

        Retour :
            str : rôle en minuscules.

        Lève :
            ValidationError : rôle hors de ROLES_VALIDES.
        """
        role = value.strip().lower()
        if role not in self.ROLES_VALIDES:
            raise serializers.ValidationError(
                "Rôle invalide : choisir parmi 'president', 'rapporteur', 'examinateur'."
            )
        return role


class JurySerializer(serializers.ModelSerializer):
    """Jury de soutenance, avec la liste imbriquée (lecture seule) de ses membres."""

    members = JuryMemberSerializer(many=True, read_only=True)

    class Meta:
        model = Jury
        fields = ['id', 'name', 'is_complete', 'members']

    def validate_name(self, value):
        """Supprime les espaces superflus autour du nom du jury."""
        return value.strip()


class DefenseSerializer(serializers.ModelSerializer):
    """
    Soutenance planifiée, avec gestion des créneaux et contrôle des conflits.

    Écriture : le client envoie `slot_start` et `slot_end` (ISO 8601) qui
    sont fusionnés en un intervalle PostgreSQL `slot_range`.
    Lecture : on renvoie `slot_start`/`slot_end` ainsi que des champs
    dénormalisés (nom de l'étudiant, sujet, nom du jury) pour l'affichage.
    """

    slot_start = serializers.DateTimeField(write_only=True)
    slot_end = serializers.DateTimeField(write_only=True)
    folder_detail = InternshipFolderSerializer(source='folder', read_only=True)
    jury_detail = JurySerializer(source='jury', read_only=True)
    student_name = serializers.CharField(
        source='folder.student.full_name',
        read_only=True,
    )
    subject = serializers.CharField(source='folder.subject', read_only=True)
    jury_name = serializers.CharField(source='jury.name', read_only=True)

    class Meta:
        model = Defense
        fields = [
            'id',
            'folder',
            'folder_detail',
            'student_name',
            'subject',
            'jury',
            'jury_detail',
            'jury_name',
            'room_name',
            'slot_start',
            'slot_end',
            'status',
        ]

    def validate(self, attrs):
        """
        Fusionne les valeurs reçues avec l'existant puis applique les règles.

        En modification partielle, les champs absents sont repris de
        l'instance afin de toujours valider la soutenance complète.

        Retour :
            dict : attributs validés, avec `slot_range` à la place de
            `slot_start`/`slot_end`.

        Lève :
            ValidationError : champ obligatoire manquant ou règle métier
            violée (conflit, dossier non recevable, créneau invalide…).
        """
        attrs = super().validate(attrs)
        instance = self.instance

        # Valeur fournie, sinon valeur actuelle (cas PATCH), sinon None.
        debut = attrs.get('slot_start') or (instance.slot_range.lower if instance else None)
        fin = attrs.get('slot_end') or (instance.slot_range.upper if instance else None)
        dossier = attrs.get('folder') or (instance.folder if instance else None)
        jury = attrs.get('jury') or (instance.jury if instance else None)
        room_name = (attrs.get('room_name') or (instance.room_name if instance else '') or '').strip()

        # Construit et normalise le créneau (UTC, durée maximale…).
        slot = conflicts.construire_creneau(debut, fin)

        if not room_name:
            raise serializers.ValidationError({'room_name': 'La salle est obligatoire.'})
        attrs['room_name'] = room_name
        if dossier is None:
            raise serializers.ValidationError({'folder': 'Le dossier de stage est obligatoire.'})
        if jury is None:
            raise serializers.ValidationError({'jury': 'Le jury est obligatoire pour planifier une soutenance.'})

        # La soutenance modifiée ne doit pas entrer en conflit avec elle-même.
        defense_exclue_id = instance.pk if instance else None
        conflicts.verifier_toutes_regles(
            dossier.pk, jury.pk, room_name, slot,
            defense_exclue_id=defense_exclue_id,
        )

        attrs.pop('slot_start', None)
        attrs.pop('slot_end', None)
        attrs['slot_range'] = slot
        return attrs

    def create(self, validated_data):
        """Délègue la création au service de planification (verrouillage inclus)."""
        slot_range = validated_data.pop('slot_range')
        return conflicts.planifier_soutenance(
            folder_id=validated_data.pop('folder').pk,
            jury_id=validated_data.pop('jury').pk,
            room_name=validated_data.pop('room_name'),
            debut=slot_range.lower,
            fin=slot_range.upper,
            status=validated_data.pop('status', 'planifie'),
        )

    def update(self, instance, validated_data):
        """Délègue la modification au service de planification."""
        slot_range = validated_data.pop('slot_range', instance.slot_range)
        return conflicts.planifier_soutenance(
            folder_id=validated_data.pop('folder', instance.folder).pk,
            jury_id=validated_data.pop('jury', instance.jury).pk,
            room_name=validated_data.pop('room_name', instance.room_name),
            debut=slot_range.lower,
            fin=slot_range.upper,
            status=validated_data.pop('status', instance.status),
            defense_id=instance.pk,
        )

    def to_representation(self, instance):
        """
        Ajoute `slot_start` et `slot_end` (champs en écriture seule) à la sortie.

        Retour :
            dict : représentation JSON complète de la soutenance.
        """
        data = super().to_representation(instance)
        slot = instance.slot_range
        if slot is not None:
            data['slot_start'] = slot.lower.isoformat() if slot.lower else None
            data['slot_end'] = slot.upper.isoformat() if slot.upper else None
        return data
