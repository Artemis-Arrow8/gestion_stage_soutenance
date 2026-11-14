from datetime import datetime, time, timedelta, timezone as datetime_timezone

from django.contrib.auth import authenticate, get_user_model
from django.db import IntegrityError, transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.utils.dateparse import parse_date
from rest_framework import mixins, permissions, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from .permissions import (
    IsAccountAdministrator,
    IsAdminOrPedagogicalResponsible,
    IsAdminResponsibleOrStudent,
    IsAdminResponsibleOrAssignedJuryReader,
    IsReviewReader,
    IsSupervisor,
)
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
from .roles import get_user_role

User = get_user_model()


def _student_for_user(user):
    if isinstance(user, Student):
        return user
    account = getattr(user, 'student_account', None)
    return account.student if account else None


def _parametre_date(request, nom_parametre, obligatoire=False):
    """Lit une date ISO depuis la requête et signale les formats invalides."""
    valeur = request.query_params.get(nom_parametre)
    if not valeur:
        if obligatoire:
            raise ValidationError({
                nom_parametre: 'Ce paramètre est obligatoire (format YYYY-MM-DD).'
            })
        return None

    try:
        jour = parse_date(valeur)
    except ValueError:
        jour = None
    if jour is None:
        raise ValidationError({
            nom_parametre: 'Format attendu : YYYY-MM-DD.'
        })
    return jour


def _jour_UTC(jour):
    """Retourne minuit UTC pour une date de calendrier."""
    return datetime.combine(jour, time.min, tzinfo=datetime_timezone.utc)


# ==========================================
# 1. VUES MÉTIERS (ViewSets DRF)
# ==========================================

class CampaignViewSet(viewsets.ModelViewSet):
    """Gestion des campagnes académiques."""
    queryset = Campaign.objects.all().order_by('-id')
    serializer_class = CampaignSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class StudentViewSet(viewsets.ModelViewSet):
    """Gestion des étudiants."""
    queryset = Student.objects.all()
    serializer_class = StudentSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class InternshipFolderViewSet(viewsets.ModelViewSet):
    """Gestion des dossiers de stage."""
    queryset = InternshipFolder.objects.all()
    serializer_class = InternshipFolderSerializer
    permission_classes = [IsAdminResponsibleOrStudent]

    def get_serializer(self, *args, **kwargs):
        serializer = super().get_serializer(*args, **kwargs)
        if (
            get_user_role(self.request.user) == 'student'
            and self.action in ('create', 'update', 'partial_update')
        ):
            serializer.fields['student'].read_only = True
            serializer.fields['status'].read_only = True
            if self.action in ('update', 'partial_update'):
                serializer.fields['campaign'].read_only = True
        return serializer

    def get_queryset(self):
        role = get_user_role(self.request.user)
        student = _student_for_user(self.request.user)
        if role in ('admin', 'responsible'):
            return self.queryset
        if role == 'supervisor':
            return self.queryset.filter(
                supervisor_assignments__user=self.request.user
            ).distinct()
        if student is None:
            return self.queryset.none()
        return self.queryset.filter(student=student)

    def perform_create(self, serializer):
        student = _student_for_user(self.request.user)
        if get_user_role(self.request.user) == 'student':
            if student is None:
                raise PermissionDenied("Aucun profil étudiant n'est associé à ce compte.")
            serializer.save(student=student, status='brouillon')
            return
        serializer.save()

    def perform_update(self, serializer):
        student = _student_for_user(self.request.user)
        if get_user_role(self.request.user) == 'student':
            if student is None:
                raise PermissionDenied("Aucun profil étudiant n'est associé à ce compte.")
            serializer.save(
                student=student,
                status=serializer.instance.status,
                campaign=serializer.instance.campaign,
            )
            return
        serializer.save()


class DocumentVersionViewSet(viewsets.ReadOnlyModelViewSet):
    """Gestion des versions de documents et rapports."""
    queryset = DocumentVersion.objects.all()
    serializer_class = DocumentVersionSerializer
    permission_classes = [IsAdminResponsibleOrStudent]

    def get_queryset(self):
        role = get_user_role(self.request.user)
        student = _student_for_user(self.request.user)
        if role in ('admin', 'responsible'):
            return self.queryset
        if role == 'supervisor':
            return self.queryset.filter(
                folder__supervisor_assignments__user=self.request.user
            ).distinct()
        if student is None:
            return self.queryset.none()
        return self.queryset.filter(folder__student=student)


class ReviewViewSet(viewsets.ModelViewSet):
    """Gestion des avis (encadreur / tuteur)."""
    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [IsSupervisor]

    def get_permissions(self):
        permission = (
            IsReviewReader
            if self.action in ('list', 'retrieve')
            else IsSupervisor
        )
        return [permission()]

    def get_queryset(self):
        role = get_user_role(self.request.user)
        if role == 'admin':
            queryset = self.queryset
        elif role == 'supervisor':
            queryset = self.queryset.filter(
                author=self.request.user,
                document_version__folder__supervisor_assignments__user=self.request.user
            ).distinct()
        elif role == 'student':
            student = _student_for_user(self.request.user)
            if student is None:
                return self.queryset.none()
            queryset = self.queryset.filter(
                document_version__folder__student=student
            )
        else:
            return self.queryset.none()

        document_id = self.request.query_params.get('document_version_id')
        if document_id is not None:
            try:
                document_id = int(document_id)
            except ValueError as error:
                raise ValidationError({
                    'document_version_id': 'Un identifiant entier est requis.'
                }) from error
            queryset = queryset.filter(document_version_id=document_id)
        return queryset

    def perform_create(self, serializer):
        if get_user_role(self.request.user) == 'supervisor':
            document = serializer.validated_data['document_version']
            if not document.folder.supervisor_assignments.filter(
                user=self.request.user
            ).exists():
                raise PermissionDenied(
                    "Vous ne pouvez donner un avis que sur un dossier qui vous est affecté."
                )
        serializer.save(
            author=self.request.user,
            author_role='encadreur',
        )


class SalleViewSet(viewsets.ModelViewSet):
    """Catalogue des salles de soutenance (Tâche 4)."""
    queryset = Room.objects.all().order_by('name')
    serializer_class = SalleSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]

    @action(detail=True, methods=['get'], url_path='disponibilites')
    def disponibilites(self, request, pk=None):
        salle = self.get_object()
        try:
            jour = _parametre_date(request, 'date', obligatoire=True)
        except ValidationError as error:
            return Response(
                error.detail,
                status=status.HTTP_400_BAD_REQUEST,
            )

        debut_jour = _jour_UTC(jour)
        debut_ouverture = debut_jour + timedelta(hours=8)
        fin_ouverture = debut_jour + timedelta(hours=20)
        reservations = Defense.objects.filter(
            room_name=salle.name,
            slot_range__overlap=DateTimeTZRange(
                debut_ouverture,
                fin_ouverture,
                bounds='[)',
            ),
        ).order_by('slot_range')

        occupes = []
        libres = []
        curseur = debut_ouverture
        for defense in reservations:
            debut = max(defense.slot_range.lower, debut_ouverture)
            fin = min(defense.slot_range.upper, fin_ouverture)
            if debut > curseur:
                libres.append({'debut': curseur.isoformat(), 'fin': debut.isoformat()})
            occupes.append({
                'debut': debut.isoformat(),
                'fin': fin.isoformat(),
                'statut': defense.status,
                'soutenance_id': defense.pk,
            })
            curseur = max(curseur, fin)
        if curseur < fin_ouverture:
            libres.append({'debut': curseur.isoformat(), 'fin': fin_ouverture.isoformat()})

        return Response({
            'date': jour.isoformat(),
            'creneaux_occupes': occupes,
            'creneaux_libres': libres,
        })


class JuryViewSet(viewsets.ModelViewSet):
    """Gestion des jurys de soutenance."""
    queryset = Jury.objects.all().order_by('name')
    serializer_class = JurySerializer
    permission_classes = [IsAdminResponsibleOrAssignedJuryReader]

    def get_queryset(self):
        if get_user_role(self.request.user) == 'jury':
            return self.queryset.filter(
                members__account__user=self.request.user
            ).distinct()
        return self.queryset


class JuryMemberViewSet(viewsets.ModelViewSet):
    """Gestion des membres composant les jurys."""
    queryset = JuryMember.objects.all()
    serializer_class = JuryMemberSerializer
    permission_classes = [IsAdminResponsibleOrAssignedJuryReader]

    def get_queryset(self):
        if get_user_role(self.request.user) == 'jury':
            return self.queryset.filter(account__user=self.request.user)
        return self.queryset


class DefenseViewSet(viewsets.ModelViewSet):
    """Planification et gestion des soutenances."""
    queryset = Defense.objects.all()
    serializer_class = DefenseSerializer
    permission_classes = [IsAdminResponsibleOrAssignedJuryReader]

    def get_queryset(self):
        if get_user_role(self.request.user) == 'jury':
            return self.queryset.filter(
                jury__members__account__user=self.request.user
            ).distinct()
        return self.queryset

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
                    {'detail': 'Conflit de réservation : la salle ou le jury '
                               'est déjà engagé sur ce créneau (EXG01).'}
                ) from error
            raise

    def perform_create(self, serializer):
        self._save_defense(serializer)

    def perform_update(self, serializer):
        self._save_defense(serializer)

    @action(detail=False, methods=['get'], url_path='planning')
    def planning(self, request):
        queryset = self.get_queryset()
        date_value = request.query_params.get('date')
        date_debut_value = request.query_params.get('date_debut')
        date_fin_value = request.query_params.get('date_fin')
        if date_value and (date_debut_value or date_fin_value):
            return Response(
                {'date': 'Choisissez une date ou une période, pas les deux.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            jour = _parametre_date(request, 'date')
            if jour is not None:
                debut = _jour_UTC(jour)
                queryset = queryset.filter(
                    slot_range__overlap=DateTimeTZRange(
                        debut, debut + timedelta(days=1)
                    )
                )
            elif date_debut_value or date_fin_value:
                date_debut = _parametre_date(
                    request, 'date_debut', obligatoire=True
                )
                date_fin = _parametre_date(
                    request, 'date_fin', obligatoire=True
                )
                if date_fin < date_debut:
                    raise ValidationError({
                        'date_debut': (
                            'La date de début doit précéder ou égaler la date de fin.'
                        )
                    })
                debut = _jour_UTC(date_debut)
                fin = _jour_UTC(date_fin + timedelta(days=1))
                queryset = queryset.filter(
                    slot_range__overlap=DateTimeTZRange(debut, fin)
                )
        except ValidationError as error:
            return Response(error.detail, status=status.HTTP_400_BAD_REQUEST)

        salle = request.query_params.get('salle')
        statut = request.query_params.get('statut')
        jury_value = request.query_params.get('jury')
        if salle:
            queryset = queryset.filter(room_name=salle)
        if statut:
            queryset = queryset.filter(status=statut)
        if jury_value:
            try:
                jury_id = int(jury_value)
            except ValueError:
                return Response(
                    {'jury': 'L’identifiant du jury doit être un entier.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            queryset = queryset.filter(jury_id=jury_id)

        soutenances = queryset.order_by('slot_range', 'pk')
        donnees = DefenseSerializer(soutenances, many=True).data
        return Response({'total': len(donnees), 'soutenances': donnees})


class AssessmentViewSet(viewsets.ModelViewSet):
    """Gestion des évaluations et notes finales."""
    queryset = Assessment.objects.all()
    serializer_class = AssessmentSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class UserAccountViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.CreateModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    queryset = User.objects.all().order_by('pk')
    serializer_class = UserAccountSerializer
    permission_classes = [IsAccountAdministrator]

    def get_queryset(self):
        """Empêche un administrateur métier de consulter les superutilisateurs."""
        queryset = super().get_queryset()
        if not self.request.user.is_superuser:
            queryset = queryset.filter(is_superuser=False)
        return queryset


# ==========================================
# 2. VUES D'AUTHENTIFICATION ET COMPTES
# ==========================================

def _user_profile(user, role=None):
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

    student = _student_for_user(user)
    if student is None:
        account = getattr(user, 'jury_member_account', None)
        if account is not None:
            profile.update({
                'jury_member_id': account.jury_member_id,
                'jury_id': account.jury_member.jury_id,
                'jury_member_name': account.jury_member.member_name,
            })
        return profile

    folder = InternshipFolder.objects.filter(
        student=student,
        campaign__is_active=True,
    ).order_by('-created_at').first()
    profile.update({
        'id': student.pk,
        'student_number': student.student_number,
        'full_name': student.full_name,
        'email': student.email,
        'folder_id': folder.pk if folder else None,
        'folder_status': folder.status if folder else None,
    })
    return profile


class LoginView(APIView):
    authentication_classes = []
    permission_classes = []

    def post(self, request):
        username = request.data.get('username')
        password = request.data.get('password')
        if (
            not isinstance(username, str)
            or not username.strip()
            or not isinstance(password, str)
            or not password
        ):
            return Response(
                {'error': 'Veuillez fournir votre identifiant et votre mot de passe.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = authenticate(
            request,
            username=username.strip(),
            password=password,
        )
        if user is None:
            return Response(
                {'error': 'Identifiant ou mot de passe incorrect.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        role = get_user_role(user)
        if role is None:
            return Response(
                {'error': "Aucun rôle SGSUS n'est associé à ce compte."},
                status=status.HTTP_403_FORBIDDEN,
            )

        refresh = RefreshToken.for_user(user)
        return Response({
            'message': 'Connexion réussie',
            'user': _user_profile(user, role),
            'access': str(refresh.access_token),
            'refresh': str(refresh),
        })


class UserProfileView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        role = get_user_role(request.user)
        if role is None:
            return Response(
                {'error': "Aucun rôle SGSUS n'est associé à ce compte."},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response({'user': _user_profile(request.user, role)})


class LogoutView(APIView):
    """Invalide le token de rafraîchissement pour déconnecter l'utilisateur."""
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
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
                    {'error': "Ce jeton n'appartient pas au compte connecté."},
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