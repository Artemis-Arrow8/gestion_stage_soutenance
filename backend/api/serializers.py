from rest_framework import serializers
from .models import Campaign, User, Student, Internship, Defense

# Serialiseur pour le modele Campaign (Campagnes de stage/soutenance)
class CampaignSerializer(serializers.ModelSerializer):
    class Meta:
        model = Campaign
        fields = '__all__'  # Expose tous les champs de la table

# Serialiseur pour le modele User (Gestion des utilisateurs et des roles)
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'role', 'first_name', 'last_name']

# Serialiseur pour le modele Student (Informations des etudiants)
class StudentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Student
        fields = '__all__'

# Serialiseur pour le modele Internship (Dossiers de stage)
class InternshipSerializer(serializers.ModelSerializer):
    class Meta:
        model = Internship
        fields = '__all__'

# Serialiseur pour le modele Defense (Planification des soutenances)
class DefenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Defense
        fields = '__all__'