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

    Certains champs (`student`, `status`, `campaign`) sont rendus en lecture
    seule dynamiquement par la vue lorsque l'appelant est un étudiant.
    """

    class Meta:
        model = InternshipFolder
        fields = '__all__'


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
        ]

    def get_defense_start(self, assessment):
        """Retourne le début du créneau de la soutenance (ISO 8601) ou None."""
        slot = assessment.defense.slot_range if assessment.defense_id else None
        return slot.lower.isoformat() if slot is not None and slot.lower else None

    def validate(self, attrs):
        """
        Vérifie l'unicité par soutenance et complète la moyenne finale.

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

        # Valeurs effectives (fournies, sinon actuelles en modification).
        def valeur(champ):
            if champ in attrs:
                return attrs[champ]
            return getattr(self.instance, champ, None) if self.instance else None

        rapport, oral = valeur('report_grade'), valeur('oral_grade')
        # Moyenne calculée seulement si elle n'est pas saisie explicitement.
        if 'final_average' not in attrs and rapport is not None and oral is not None:
            attrs['final_average'] = round((rapport + oral) / 2, 2)
        return attrs
