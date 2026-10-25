from rest_framework import viewsets
from .models import Campaign, User, Student, Internship, Defense
from .serializers import (
    CampaignSerializer, UserSerializer, StudentSerializer, 
    InternshipSerializer, DefenseSerializer
)

# Vue pour gerer les campagnes via l'API
class CampaignViewSet(viewsets.ModelViewSet):
    queryset = Campaign.objects.all()
    serializer_class = CampaignSerializer

# Vue pour gerer les utilisateurs via l'API
class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer

# Vue pour gerer les etudiants via l'API
class StudentViewSet(viewsets.ModelViewSet):
    queryset = Student.objects.all()
    serializer_class = StudentSerializer

# Vue pour gerer les stages via l'API
class InternshipViewSet(viewsets.ModelViewSet):
    queryset = Internship.objects.all()
    serializer_class = InternshipSerializer

# Vue pour gerer les soutenances via l'API
class DefenseViewSet(viewsets.ModelViewSet):
    queryset = Defense.objects.all()
    serializer_class = DefenseSerializer