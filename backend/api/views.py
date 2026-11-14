from django.contrib.auth import get_user_model
from rest_framework import viewsets, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .models import (
    Assessment,
    Campaign,
    Defense,
    DocumentVersion,
    InternshipFolder,
    Jury,
    JuryMember,
    Review,
    Room,
    Student,
)
from .serializers import (
    AssessmentSerializer,
    CampaignSerializer,
    DefenseSerializer,
    DocumentVersionSerializer,
    InternshipFolderSerializer,
    JuryMemberSerializer,
    JurySerializer,
    ReviewSerializer,
    SalleSerializer,
    StudentSerializer,
    UserAccountSerializer,
)

User = get_user_model()


# ==========================================
# 1. VUES MÉTIERS (ViewSets DRF)
# ==========================================

class CampaignViewSet(viewsets.ModelViewSet):
    """Gestion des campagnes académiques."""
    queryset = Campaign.objects.all().order_by('-id')
    serializer_class = CampaignSerializer
    permission_classes = [permissions.IsAuthenticated]


class StudentViewSet(viewsets.ModelViewSet):
    """Gestion des étudiants."""
    queryset = Student.objects.all()
    serializer_class = StudentSerializer
    permission_classes = [permissions.IsAuthenticated]


class InternshipFolderViewSet(viewsets.ModelViewSet):
    """Gestion des dossiers de stage."""
    queryset = InternshipFolder.objects.all()
    serializer_class = InternshipFolderSerializer
    permission_classes = [permissions.IsAuthenticated]


class DocumentVersionViewSet(viewsets.ModelViewSet):
    """Gestion des versions de documents et rapports."""
    queryset = DocumentVersion.objects.all()
    serializer_class = DocumentVersionSerializer
    permission_classes = [permissions.IsAuthenticated]


class ReviewViewSet(viewsets.ModelViewSet):
    """Gestion des avis (encadreur / tuteur)."""
    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [permissions.IsAuthenticated]


class SalleViewSet(viewsets.ModelViewSet):
    """Catalogue des salles de soutenance (Tâche 4)."""
    queryset = Room.objects.all().order_by('name')
    serializer_class = SalleSerializer
    permission_classes = [permissions.IsAuthenticated]


class JuryViewSet(viewsets.ModelViewSet):
    """Gestion des jurys de soutenance."""
    queryset = Jury.objects.all().order_by('name')
    serializer_class = JurySerializer
    permission_classes = [permissions.IsAuthenticated]


class JuryMemberViewSet(viewsets.ModelViewSet):
    """Gestion des membres composant les jurys."""
    queryset = JuryMember.objects.all()
    serializer_class = JuryMemberSerializer
    permission_classes = [permissions.IsAuthenticated]


class DefenseViewSet(viewsets.ModelViewSet):
    """Planification et gestion des soutenances."""
    queryset = Defense.objects.all()
    serializer_class = DefenseSerializer
    permission_classes = [permissions.IsAuthenticated]


class AssessmentViewSet(viewsets.ModelViewSet):
    """Gestion des évaluations et notes finales."""
    queryset = Assessment.objects.all()
    serializer_class = AssessmentSerializer
    permission_classes = [permissions.IsAuthenticated]


# ==========================================
# 2. VUES D'AUTHENTIFICATION ET COMPTES
# ==========================================

class LogoutView(APIView):
    """Invalide le token de rafraîchissement pour déconnecter l'utilisateur."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data.get("refresh")
            if not refresh_token:
                return Response(
                    {"error": "Le token de rafraîchissement est requis."},
                    status=status.HTTP_400_BAD_REQUEST
                )
            token = RefreshToken(refresh_token)
            token.blacklist()
            return Response(
                {"message": "Déconnexion réussie."},
                status=status.HTTP_205_RESET_CONTENT
            )
        except Exception as e:
            return Response(
                {"error": "Jeton invalide ou déjà expiré."},
                status=status.HTTP_400_BAD_REQUEST
            )