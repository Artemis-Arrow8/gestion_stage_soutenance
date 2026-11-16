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
    """Notes (rapport, oral, moyenne) et validation finale d'une soutenance."""

    class Meta:
        model = Assessment
        fields = '__all__'
