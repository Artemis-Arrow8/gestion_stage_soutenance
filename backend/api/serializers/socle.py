"""
Sérialiseurs des données ajoutées pour le socle du dossier ALM : historique
des dossiers, confidentialité et habilitations, procès-verbaux, versions du
planning, convocations et indisponibilités.

Les champs calculés ou décidés par le serveur (auteur, dates, versions,
statuts) sont en lecture seule : le client ne peut jamais les imposer.
"""
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.conf import settings
from rest_framework import serializers

from api.models import (
    ConfidentialiteDossier,
    Convocation,
    ExceptionIndisponibilite,
    HabilitationDossier,
    HistoriqueDossier,
    Indisponibilite,
    ProcesVerbal,
    VersionPlanning,
)


class HistoriqueDossierSerializer(serializers.ModelSerializer):
    """Une ligne de l'historique d'un dossier (lecture seule)."""

    acteur_nom = serializers.SerializerMethodField()
    version = serializers.IntegerField(
        source='version_document.version_number', read_only=True, default=None,
    )

    class Meta:
        model = HistoriqueDossier
        fields = ['id', 'evenement', 'statut_avant', 'statut_apres',
                  'acteur_nom', 'motif', 'version', 'created_at']
        read_only_fields = fields

    def get_acteur_nom(self, ligne):
        """Nom lisible de l'auteur de la transition."""
        acteur = ligne.acteur
        if acteur is None:
            return None
        return acteur.get_full_name() or acteur.get_username()


class ConfidentialiteDossierSerializer(serializers.ModelSerializer):
    """Niveau de confidentialité d'un dossier, modifiable par le personnel."""

    class Meta:
        model = ConfidentialiteDossier
        fields = ['niveau', 'origine', 'embargo_jusqu_au', 'diffusion_autorisee', 'updated_at']
        read_only_fields = ['updated_at']


class HabilitationDossierSerializer(serializers.ModelSerializer):
    """Habilitation nominative sur un dossier confidentiel."""

    beneficiaire_nom = serializers.SerializerMethodField()

    class Meta:
        model = HabilitationDossier
        fields = ['id', 'dossier', 'beneficiaire', 'beneficiaire_nom', 'valide_du',
                  'valide_au', 'revoquee', 'created_at']
        read_only_fields = ['revoquee', 'created_at']
        # Début de validité facultatif : « maintenant » par défaut (vue).
        extra_kwargs = {'valide_du': {'required': False}}

    def get_beneficiaire_nom(self, habilitation):
        """Nom lisible du bénéficiaire."""
        compte = habilitation.beneficiaire
        return compte.get_full_name() or compte.get_username()

    def validate(self, attrs):
        """La fin de validité doit suivre son début."""
        attrs = super().validate(attrs)
        debut, fin = attrs.get('valide_du'), attrs.get('valide_au')
        if debut and fin and fin <= debut:
            raise serializers.ValidationError({'valide_au': 'La fin doit suivre le début.'})
        return attrs


class ProcesVerbalSerializer(serializers.ModelSerializer):
    """Version de procès-verbal (lecture seule)."""

    poids_rapport = serializers.DecimalField(
        source='grille.poids_rapport', max_digits=4, decimal_places=3, read_only=True,
    )
    poids_oral = serializers.DecimalField(
        source='grille.poids_oral', max_digits=4, decimal_places=3, read_only=True,
    )
    version_grille = serializers.IntegerField(source='grille.version', read_only=True)
    approuve_par_nom = serializers.SerializerMethodField()

    class Meta:
        model = ProcesVerbal
        fields = ['id', 'version', 'statut', 'note_rapport', 'note_oral', 'moyenne',
                  'version_grille', 'poids_rapport', 'poids_oral', 'membres_jury',
                  'motif', 'approuve_par_nom', 'created_at']
        read_only_fields = fields

    def get_approuve_par_nom(self, pv):
        """Nom lisible de l'approbateur."""
        compte = pv.approuve_par
        if compte is None:
            return None
        return compte.get_full_name() or compte.get_username()


class VersionPlanningSerializer(serializers.ModelSerializer):
    """Version publiée du planning (lecture seule)."""

    class Meta:
        model = VersionPlanning
        fields = ['id', 'numero', 'publiee_le', 'commentaire', 'nombre_soutenances']
        read_only_fields = fields


class ConvocationSerializer(serializers.ModelSerializer):
    """Convocation d'un participant (lecture seule)."""

    version = serializers.IntegerField(source='version.numero', read_only=True)
    remplacee_par_version = serializers.IntegerField(
        source='remplacee_par.version.numero', read_only=True, default=None,
    )
    etudiant = serializers.CharField(source='soutenance.folder.student.full_name', read_only=True)

    class Meta:
        model = Convocation
        fields = ['id', 'version', 'soutenance', 'etudiant', 'destinataire',
                  'role_destinataire', 'debut', 'fin', 'salle', 'jury', 'statut',
                  'remplacee_par_version', 'notification', 'created_at']
        read_only_fields = fields


class IndisponibiliteSerializer(serializers.ModelSerializer):
    """
    Indisponibilité récurrente. `exceptions` est une liste de dates
    (AAAA-MM-JJ) où la ressource reste disponible.
    """

    # En écriture : liste de dates ; en lecture : ajoutée par to_representation.
    exceptions = serializers.ListField(
        child=serializers.DateField(), required=False, write_only=True,
    )
    jour_libelle = serializers.CharField(source='get_jour_semaine_display', read_only=True)

    class Meta:
        model = Indisponibilite
        fields = ['id', 'type_ressource', 'ressource', 'jour_semaine', 'jour_libelle',
                  'heure_debut', 'heure_fin', 'fuseau', 'valide_du', 'valide_au',
                  'motif', 'exceptions', 'created_at']
        read_only_fields = ['created_at']
        extra_kwargs = {'fuseau': {'required': False}}

    def to_representation(self, instance):
        """Remplace les exceptions par la liste de leurs dates."""
        donnees = super().to_representation(instance)
        donnees['exceptions'] = [e.date.isoformat() for e in instance.exceptions.all()]
        return donnees

    def validate_fuseau(self, valeur):
        """Le fuseau doit être un identifiant IANA valide (ex. Africa/Bamako)."""
        try:
            ZoneInfo(valeur)
        except (ZoneInfoNotFoundError, ValueError) as erreur:
            raise serializers.ValidationError('Fuseau horaire inconnu.') from erreur
        return valeur

    def validate(self, attrs):
        """Heures et période ordonnées ; fuseau métier par défaut."""
        attrs = super().validate(attrs)
        instance = self.instance

        def valeur(champ):
            return attrs.get(champ, getattr(instance, champ, None) if instance else None)

        if valeur('heure_fin') and valeur('heure_debut') and valeur('heure_fin') <= valeur('heure_debut'):
            raise serializers.ValidationError({'heure_fin': "L'heure de fin doit suivre l'heure de début."})
        if valeur('valide_au') and valeur('valide_du') and valeur('valide_au') < valeur('valide_du'):
            raise serializers.ValidationError({'valide_au': 'La période de validité est inversée.'})
        if not valeur('fuseau'):
            attrs['fuseau'] = settings.SGSUS_FUSEAU_METIER
        return attrs

    def _enregistrer_exceptions(self, regle, dates):
        """Remplace les exceptions de la règle par `dates`."""
        regle.exceptions.all().delete()
        ExceptionIndisponibilite.objects.bulk_create(
            ExceptionIndisponibilite(regle=regle, date=date) for date in sorted(set(dates))
        )

    def create(self, validated_data):
        """Crée la règle puis ses exceptions."""
        dates = validated_data.pop('exceptions', [])
        regle = Indisponibilite.objects.create(**validated_data)
        self._enregistrer_exceptions(regle, dates)
        return regle

    def update(self, instance, validated_data):
        """Modifie la règle ; les exceptions ne changent que si elles sont fournies."""
        dates = validated_data.pop('exceptions', None)
        regle = super().update(instance, validated_data)
        if dates is not None:
            self._enregistrer_exceptions(regle, dates)
        return regle

