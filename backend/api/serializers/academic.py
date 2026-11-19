"""
Sérialiseurs du domaine académique : campagnes, étudiants, dossiers,
versions de documents, avis et évaluations.

Ces sérialiseurs sont volontairement simples (`ModelSerializer`) : les
règles d'accès sont appliquées dans les vues, et les règles métier
complexes dans les services.
"""

from rest_framework import serializers

from api.models import (
    Assessment,
    Campaign,
    DocumentVersion,
    InternshipFolder,
    Review,
    Student,
)


class CampaignSerializer(serializers.ModelSerializer):
    """Campagne académique (année universitaire et état actif/inactif)."""

    class Meta:
        model = Campaign
        fields = '__all__'


class StudentSerializer(serializers.ModelSerializer):
    """Fiche étudiante (numéro, nom complet, e-mail)."""

    class Meta:
        model = Student
        fields = '__all__'


class InternshipFolderSerializer(serializers.ModelSerializer):
    """
    Dossier de stage.

    `status` est TOUJOURS en lecture seule : il ne change que par les
    transitions de api/services/dossiers.py (soumettre, autoriser…), jamais
    par une modification directe (STA11). `student` et `campaign` sont en
    plus rendus non modifiables par la vue lorsque l'appelant est étudiant.
    `confidentialite` indique le niveau (« standard » ou « confidentiel »).
    """

    confidentialite = serializers.SerializerMethodField()

    class Meta:
        model = InternshipFolder
        fields = '__all__'
        read_only_fields = ('status',)

    def get_confidentialite(self, dossier):
        """Niveau de confidentialité du dossier (standard par défaut)."""
        reglage = getattr(dossier, 'confidentialite', None)
        return reglage.niveau if reglage is not None else 'standard'


class DocumentVersionSerializer(serializers.ModelSerializer):
    """Version déposée d'un rapport ; l'horodatage est fixé par le serveur."""

    class Meta:
        model = DocumentVersion
        fields = '__all__'
        read_only_fields = ('id', 'uploaded_at')


class ReviewSerializer(serializers.ModelSerializer):
    """
    Avis d'encadrement sur une version de document.

    L'auteur et son rôle sont déduits du jeton par la vue : ils sont donc en
    lecture seule et ne peuvent pas être usurpés par le client.
    """

    class Meta:
        model = Review
        fields = '__all__'
        read_only_fields = ('id', 'author', 'author_role', 'created_at')


class AssessmentSerializer(serializers.ModelSerializer):
    """
    Notes (rapport, oral, moyenne) et validation finale d'une soutenance.

    La moyenne (`final_average`) et l'approbation (`is_approved`) sont en
    lecture seule : la moyenne est TOUJOURS calculée par le serveur selon la
    grille de la campagne (api/services/notes.py) et l'approbation passe par
    l'action /approuver/. `grille` décrit la règle de calcul appliquée.

    Règles ajoutées :
        * une seule évaluation par soutenance ;
        * si la moyenne finale n'est pas fournie, elle est calculée
          automatiquement à partir des notes de rapport et d'oral.
    Champs ajoutés en lecture seule pour l'affichage : nom de l'étudiant,
    sujet, jury et créneau de la soutenance évaluée.
    """

    student_name = serializers.CharField(
        source='defense.folder.student.full_name', read_only=True,
    )
    subject = serializers.CharField(source='defense.folder.subject', read_only=True)
    jury_name = serializers.CharField(source='defense.jury.name', read_only=True, default='')
    defense_start = serializers.SerializerMethodField()
    grille = serializers.SerializerMethodField()
    nombre_proces_verbaux = serializers.IntegerField(
        source='proces_verbaux.count', read_only=True,
    )

    class Meta:
        model = Assessment
        fields = [
            'id',
            'defense',
            'student_name',
            'subject',
            'jury_name',
            'defense_start',
            'report_grade',
            'oral_grade',
            'final_average',
            'is_approved',
            'grille',
            'nombre_proces_verbaux',
        ]
        read_only_fields = ('final_average', 'is_approved')

    def get_defense_start(self, assessment):
        """Retourne le début du créneau de la soutenance (ISO 8601) ou None."""
        slot = assessment.defense.slot_range if assessment.defense_id else None
        return slot.lower.isoformat() if slot is not None and slot.lower else None

    def get_grille(self, evaluation):
        """Règle de calcul en vigueur (coefficients), sans rien créer."""
        from api.services.notes import grille_affichee
        return grille_affichee(evaluation.defense.folder.campaign)

    def validate(self, attrs):
        """
        Vérifie l'unicité par soutenance (la moyenne est calculée par la vue).

        Lève :
            ValidationError : une évaluation existe déjà pour cette soutenance.
        """
        attrs = super().validate(attrs)
        defense = attrs.get('defense') or (self.instance.defense if self.instance else None)
        if defense is not None:
            doublons = Assessment.objects.filter(defense=defense)
            if self.instance is not None:
                doublons = doublons.exclude(pk=self.instance.pk)
            if doublons.exists():
                raise serializers.ValidationError(
                    {'defense': 'Cette soutenance a déjà une évaluation : modifiez-la.'}
                )
        return attrs
