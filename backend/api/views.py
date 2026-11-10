from django.db import IntegrityError, transaction
from django.contrib.auth import get_user_model, authenticate
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework import mixins
from rest_framework import viewsets
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from .models import Campaign, Student, StudentAccount, InternshipFolder, DocumentVersion, Review, Jury, JuryMember, Defense, Assessment
from .serializers import (
    CampaignSerializer, StudentSerializer, InternshipFolderSerializer,
    DocumentVersionSerializer, ReviewSerializer, JurySerializer, UserAccountSerializer,
    JuryMemberSerializer, DefenseSerializer, AssessmentSerializer
)
from .permissions import (
    IsAccountAdministrator,
    IsAdminResponsibleOrStudent,
    IsAdminOrPedagogicalResponsible,
    IsSupervisor,
)
from .roles import get_user_role


User = get_user_model()


def _student_for_user(user):
    """Retourne l'étudiant associé à l'utilisateur authentifié."""
    if isinstance(user, Student):
        return user

    account = getattr(user, 'student_account', None)
    return account.student if account else None


# ==========================================
# VIEWSETS STANDARDS AVEC PERMISSIONS
# ==========================================

class CampaignViewSet(viewsets.ModelViewSet):
    """ViewSet pour la gestion des campagnes académiques."""
    queryset = Campaign.objects.all()
    serializer_class = CampaignSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class StudentViewSet(viewsets.ModelViewSet):
    """ViewSet pour la gestion des étudiants."""
    queryset = Student.objects.all()
    serializer_class = StudentSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class InternshipFolderViewSet(viewsets.ModelViewSet):
    """ViewSet pour les dossiers de stage."""
    queryset = InternshipFolder.objects.all()
    serializer_class = InternshipFolderSerializer
    permission_classes = [IsAdminResponsibleOrStudent]

    def get_queryset(self):
        student = _student_for_user(self.request.user)
        if student is None and get_user_role(self.request.user) in ('admin', 'responsible'):
            return self.queryset
        if student is None:
            return self.queryset.none()
        return self.queryset.filter(student=student)

    def perform_create(self, serializer):
        student = _student_for_user(self.request.user)
        if student is not None:
            serializer.save(student=student)
        elif get_user_role(self.request.user) in ('admin', 'responsible'):
            serializer.save()
        else:
            raise PermissionDenied("Aucun profil étudiant n'est associé à ce compte.")

    def perform_update(self, serializer):
        student = _student_for_user(self.request.user)
        if student is not None:
            serializer.save(student=student)
        elif get_user_role(self.request.user) in ('admin', 'responsible'):
            serializer.save()
        else:
            raise PermissionDenied("Aucun profil étudiant n'est associé à ce compte.")


class DocumentVersionViewSet(viewsets.ModelViewSet):
    """ViewSet pour les versions de documents."""
    queryset = DocumentVersion.objects.all()
    serializer_class = DocumentVersionSerializer
    permission_classes = [IsAdminResponsibleOrStudent]

    def get_queryset(self):
        student = _student_for_user(self.request.user)
        if student is None and get_user_role(self.request.user) in ('admin', 'responsible'):
            return self.queryset
        if student is None:
            return self.queryset.none()
        return self.queryset.filter(folder__student=student)

    def perform_create(self, serializer):
        student = _student_for_user(self.request.user)
        folder = serializer.validated_data.get('folder')
        role = get_user_role(self.request.user)
        if role in ('admin', 'responsible'):
            serializer.save()
        elif student is None or folder is None or folder.student_id != student.id:
            raise PermissionDenied("Vous ne pouvez ajouter une version qu'à votre propre dossier.")
        else:
            serializer.save(folder=folder)

    def perform_update(self, serializer):
        student = _student_for_user(self.request.user)
        folder = serializer.validated_data.get('folder', serializer.instance.folder)
        role = get_user_role(self.request.user)
        if role in ('admin', 'responsible'):
            serializer.save()
        elif student is None or folder.student_id != student.id:
            raise PermissionDenied("Vous ne pouvez modifier que les versions de votre propre dossier.")
        else:
            serializer.save(folder=folder)


class ReviewViewSet(viewsets.ModelViewSet):
    """ViewSet pour les avis (encadreurs/tuteurs)."""
    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [IsSupervisor]

    def get_queryset(self):
        """Limite les encadreurs à leurs avis et réserve la vue globale à l’admin."""
        if get_user_role(self.request.user) == 'admin':
            return self.queryset
        return self.queryset.filter(author=self.request.user)

    def perform_create(self, serializer):
        """Lie chaque nouvel avis au compte qui l’a effectivement créé."""
        serializer.save(author=self.request.user)


class JuryViewSet(viewsets.ModelViewSet):
    """ViewSet pour la gestion des jurys."""
    queryset = Jury.objects.all()
    serializer_class = JurySerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class JuryMemberViewSet(viewsets.ModelViewSet):
    """ViewSet pour les membres du jury."""
    queryset = JuryMember.objects.all()
    serializer_class = JuryMemberSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class DefenseViewSet(viewsets.ModelViewSet):
    """ViewSet pour la planification des soutenances."""
    queryset = Defense.objects.all()
    serializer_class = DefenseSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]

    def _save_defense(self, serializer):
        try:
            with transaction.atomic():
                serializer.save()
        except IntegrityError as error:
            cause = error.__cause__
            constraint_name = getattr(
                getattr(cause, 'diag', None), 'constraint_name', None
            )
            if constraint_name in {
                'prevent_room_double_booking',
                'prevent_jury_double_booking',
            }:
                raise ValidationError(
                    {'slot_range': 'The room or jury is already booked during this time.'}
                ) from error
            raise

    def perform_create(self, serializer):
        self._save_defense(serializer)

    def perform_update(self, serializer):
        self._save_defense(serializer)


class AssessmentViewSet(viewsets.ModelViewSet):
    """ViewSet pour l'évaluation et les notes."""
    queryset = Assessment.objects.all()
    serializer_class = AssessmentSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


# ==========================================
# API DE CONNEXION / AUTHENTIFICATION
# ==========================================

class LoginView(APIView):
    """Authentifie un compte actif SGSUS et retourne son profil et ses jetons."""
    authentication_classes = []
    permission_classes = []

    def post(self, request):
        identifier = request.data.get('username')
        password = request.data.get('password')

        if (
            not isinstance(identifier, str)
            or not identifier.strip()
            or not isinstance(password, str)
            or not password
        ):
            return Response(
                {"error": "Veuillez fournir votre identifiant et votre mot de passe."},
                status=status.HTTP_400_BAD_REQUEST
            )

        user = authenticate(request, username=identifier.strip(), password=password)
        if user is None:
            return Response(
                {"error": "Identifiant ou mot de passe incorrect."},
                status=status.HTTP_401_UNAUTHORIZED
            )

        role = get_user_role(user)
        if role is None:
            return Response(
                {"error": "Aucun rôle SGSUS n'est associé à ce compte."},
                status=status.HTTP_403_FORBIDDEN
            )

        refresh = RefreshToken.for_user(user)
        return Response({
            "message": "Connexion réussie",
            "user": _user_profile(user, role),
            "access": str(refresh.access_token),
            "refresh": str(refresh),
        }, status=status.HTTP_200_OK)


def _user_profile(user, role=None):
    """Construit le profil public commun au login et à la route de profil."""
    role = role or get_user_role(user)

    profile = {
        'id': user.pk,
        'username': user.get_username(),
        'email': user.email,
        'full_name': ' '.join(
            part for part in (user.first_name, user.last_name) if part
        ) or user.get_username(),
        'role': role,
    }

    try:
        student = user.student_account.student
    except AttributeError:
        return profile

    # Recherche du dossier lié à la campagne active
    folder = InternshipFolder.objects.filter(
        student=student,
        campaign__is_active=True
    ).order_by('-created_at').first()

    profile.update({
        'id': student.pk,
        'student_number': student.student_number,
        'full_name': student.full_name,
        'email': student.email,
        'folder_id': folder.id if folder else None,
        'folder_status': folder.status if folder else None,
    })

    return profile


class UserProfileView(APIView):
    """Retourne uniquement le profil du compte authentifié."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        """Expose le profil courant sans rendre consultables les comptes tiers."""
        role = get_user_role(request.user)
        if role is None:
            return Response(
                {'error': 'Aucun rôle SGSUS n’est associé à ce compte.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response({'user': _user_profile(request.user, role)})


class LogoutView(APIView):
    """Révoque le jeton de renouvellement transmis par un compte connecté."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        """Place le jeton de renouvellement en liste noire."""
        raw_token = request.data.get('refresh')
        if not isinstance(raw_token, str) or not raw_token:
            return Response(
                {'error': 'Le jeton de renouvellement est obligatoire.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            refresh = RefreshToken(raw_token)
            if str(refresh.get('user_id')) != str(request.user.pk):
                return Response(
                    {'error': 'Ce jeton n’appartient pas au compte connecté.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            refresh.blacklist()
        except TokenError:
            return Response(
                {'error': 'Le jeton de renouvellement est invalide ou révoqué.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response(
            {'message': 'Déconnexion réussie.'},
            status=status.HTTP_200_OK,
        )


class UserAccountViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.CreateModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    """Réserve la consultation et la gestion des comptes aux administrateurs."""

    queryset = User.objects.all().order_by('pk')
    serializer_class = UserAccountSerializer
    permission_classes = [IsAccountAdministrator]