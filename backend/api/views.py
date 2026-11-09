"""
Vues DRF du projet SGSUS — Tâche 4 (module planification).

Routes principales :

* GET/POST/PUT/PATCH/DELETE /api/salles/              — catalogue des salles
* GET       /api/salles/{id}/disponibilites/?date=... — créneaux occupés/libres
* GET/POST/...          /api/jurys/                   — jurys + membres imbriqués
* GET/POST/...          /api/membres-jury/            — membres de jury
* GET/POST/...          /api/soutenances/             — soutenances (contrôle EXG01)
* GET       /api/soutenances/planning/?date=...       — planning par date/période

Les filtres du planning acceptent : date, date_debut, date_fin, salle,
jury, statut. Toutes les dates sont interprétées en UTC (NFR04).
"""
import datetime as dt
from datetime import datetime, timedelta
from django.db import transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.db.utils import IntegrityError
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from django.contrib.auth import authenticate, get_user_model
from rest_framework.views import APIView
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError

from api.roles import get_user_role

from api.models import (
    Campaign,
    Defense,
    InternshipFolder,
    Jury,
    JuryMember,
    Room,
    Student,
    User,
)
from api.serializers import (
    CampaignSerializer,
    DefenseSerializer,
    InternshipFolderSerializer,
    JuryMemberSerializer,
    JurySerializer,
    SalleSerializer,
    StudentSerializer,
    UserSerializer,
)
from api.services import conflicts

# Fenêtre horaire d'ouverture par défaut pour le calcul des créneaux libres.
HEURE_OUVERTURE = 8
HEURE_FERMETURE = 20

FORMAT_DATE = "%Y-%m-%d"


def _jour_UTC(valeur_date):
    """Convertit une date YYYY-MM-DD en borne de début de journée UTC."""
    return datetime(
        valeur_date.year, valeur_date.month, valeur_date.day,
        tzinfo=dt.timezone.utc,
    )


def _parametre_date(request, nom, obligatoire=False):
    """
    Lit un paramètre de requête au format YYYY-MM-DD.
    Retourne (date | None). Lève une ValidationError (HTTP 400) si le
    format est invalide.
    """
    brut = request.query_params.get(nom)
    if not brut:
        if obligatoire:
            raise ValidationError(
                {nom: f"Paramètre « {nom} » requis (format YYYY-MM-DD)."}
            )
        return None
    try:
        return datetime.strptime(brut, FORMAT_DATE).date()
    except ValueError:
        raise ValidationError(
            {nom: f"Date invalide : « {brut} ». Format attendu YYYY-MM-DD."}
        )


# ---------------------------------------------------------------------------
# Ressources des autres lots (contrats conservés)
# ---------------------------------------------------------------------------

class CampaignViewSet(viewsets.ModelViewSet):
    queryset = Campaign.objects.all().order_by("id")
    serializer_class = CampaignSerializer


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all().order_by("id")
    serializer_class = UserSerializer


class StudentViewSet(viewsets.ModelViewSet):
    queryset = Student.objects.all().order_by("id")
    serializer_class = StudentSerializer


class InternshipFolderViewSet(viewsets.ModelViewSet):
    queryset = InternshipFolder.objects.select_related(
        "student", "campaign"
    ).order_by("id")
    serializer_class = InternshipFolderSerializer


# ---------------------------------------------------------------------------
# Salles (F04/F05)
# ---------------------------------------------------------------------------

class SalleViewSet(viewsets.ModelViewSet):
    queryset = Room.objects.all().order_by("name")
    serializer_class = SalleSerializer

    @action(detail=True, methods=["get"], url_path="disponibilites")
    def disponibilites(self, request, pk=None):
        """
        Créneaux occupés et libres d'une salle pour une journée donnée :
        GET /api/salles/{id}/disponibilites/?date=2026-07-10
        """
        salle = self.get_object()
        jour = _parametre_date(request, "date", obligatoire=True)
        fenetre = DateTimeTZRange(
            _jour_UTC(jour), _jour_UTC(jour) + timedelta(days=1), bounds="[)"
        )

        occupees = Defense.objects.filter(
            room_name=salle.name, slot_range__overlap=fenetre
        )
        creneaux_occupes = sorted(
            [
                {
                    "soutenance_id": defense.pk,
                    "debut": defense.slot_range.lower.isoformat(),
                    "fin": defense.slot_range.upper.isoformat(),
                    "statut": defense.status,
                }
                for defense in occupees
            ],
            key=lambda c: c["debut"],
        )

        # Complément des créneaux occupés dans la fenêtre d'ouverture.
        debut_journee = _jour_UTC(jour) + timedelta(hours=HEURE_OUVERTURE)
        fin_journee = _jour_UTC(jour) + timedelta(hours=HEURE_FERMETURE)
        creneaux_libres = []
        curseur = debut_journee
        for creneau in creneaux_occupes:
            debut_occupe = datetime.fromisoformat(creneau["debut"])
            fin_occupe = datetime.fromisoformat(creneau["fin"])
            if fin_occupe <= curseur:
                continue
            if debut_occupe > curseur:
                creneaux_libres.append(
                    {
                        "debut": curseur.isoformat(),
                        "fin": min(debut_occupe, fin_journee).isoformat(),
                    }
                )
            curseur = max(curseur, fin_occupe)
            if curseur >= fin_journee:
                break
        if curseur < fin_journee:
            creneaux_libres.append(
                {"debut": curseur.isoformat(), "fin": fin_journee.isoformat()}
            )

        return Response(
            {
                "salle": SalleSerializer(salle).data,
                "date": jour.isoformat(),
                "creneaux_occupes": creneaux_occupes,
                "creneaux_libres": creneaux_libres,
            }
        )


# ---------------------------------------------------------------------------
# Jurys (F04)
# ---------------------------------------------------------------------------

class JuryViewSet(viewsets.ModelViewSet):
    queryset = Jury.objects.prefetch_related("members").order_by("name")
    serializer_class = JurySerializer


class JuryMemberViewSet(viewsets.ModelViewSet):
    queryset = JuryMember.objects.select_related("jury").order_by("id")
    serializer_class = JuryMemberSerializer


# ---------------------------------------------------------------------------
# Soutenances (F05) + planning
# ---------------------------------------------------------------------------

class DefenseViewSet(viewsets.ModelViewSet):
    serializer_class = DefenseSerializer

    def get_queryset(self):
        requete = Defense.objects.select_related(
            "folder__student", "folder__campaign", "jury"
        ).order_by("id")
        parametres = self.request.query_params

        date_unique = _parametre_date(self.request, "date")
        if date_unique is not None:
            requete = requete.filter(
                slot_range__overlap=DateTimeTZRange(
                    _jour_UTC(date_unique),
                    _jour_UTC(date_unique) + timedelta(days=1),
                    bounds="[)",
                )
            )

        date_debut = _parametre_date(self.request, "date_debut")
        date_fin = _parametre_date(self.request, "date_fin")
        if date_debut is not None or date_fin is not None:
            debut = _jour_UTC(date_debut) if date_debut else datetime(
                1970, 1, 1, tzinfo=dt.timezone.utc
            )
            fin = (
                _jour_UTC(date_fin) + timedelta(days=1)
                if date_fin
                else datetime.max.replace(tzinfo=timezone.utc)
            )
            if fin <= debut:
                raise ValidationError(
                    {"date_fin": "date_fin doit être postérieure à date_debut."}
                )
            requete = requete.filter(
                slot_range__overlap=DateTimeTZRange(debut, fin, bounds="[)")
            )

        salle = parametres.get("salle")
        if salle:
            requete = requete.filter(room_name__iexact=salle)

        jury = parametres.get("jury")
        if jury:
            try:
                requete = requete.filter(jury_id=int(jury))
            except (TypeError, ValueError):
                raise ValidationError(
                    {"jury": "Identifiant de jury invalide (entier attendu)."}
                )

        statut = parametres.get("statut")
        if statut:
            requete = requete.filter(status=statut)

        return requete

    @action(detail=False, methods=["get"], url_path="planning")
    def planning(self, request):
        """
        Planning des soutenances (lecture seule) avec les mêmes filtres que
        la liste : GET /api/soutenances/planning/?date=2026-07-10
        """
        soutenances = self.get_queryset()
        donnees = self.get_serializer(soutenances, many=True).data
        donnees_triees = sorted(donnees, key=lambda s: s.get("slot_start") or "")
        return Response({"total": len(donnees_triees), "soutenances": donnees_triees})

    # Filet de sécurité EXG01 (ADR 0002) : si deux requêtes concurrentes
    # passent le contrôle applicatif, la contrainte PostgreSQL tranche et
    # l'IntegrityError est traduite en erreur 400 lisible.
    def perform_create(self, serializer):
        try:
            with transaction.atomic():
                serializer.save()
        except IntegrityError as erreur:
            raise conflicts.traduire_integrity_error(erreur)

    def perform_update(self, serializer):
        try:
            with transaction.atomic():
                serializer.save()
        except IntegrityError as erreur:
            raise conflicts.traduire_integrity_error(erreur)

# =====================================================
# AUTHENTIFICATION DES UTILISATEURS
# =====================================================

DjangoUser = get_user_model()


def construire_profil(user):
    """Construit le profil envoyé à Flutter."""

    return {
        "id": user.pk,
        "student_number": "",
        "username": user.get_username(),
        "full_name": (
            f"{user.first_name} {user.last_name}".strip()
            or user.get_username()
        ),
        "email": user.email,
        "role": get_user_role(user),
    }


class LoginView(APIView):
    """Connexion avec identifiant et mot de passe."""

    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):

        username = request.data.get("username")
        password = request.data.get("password")

        if not username or not password:
            return Response(
                {"error": "Identifiant et mot de passe obligatoires."},
                status=status.HTTP_400_BAD_REQUEST
            )

        user = authenticate(
            request,
            username=username.strip(),
            password=password
        )

        if user is None:
            return Response(
                {"error": "Identifiant ou mot de passe incorrect."},
                status=status.HTTP_401_UNAUTHORIZED
            )

        if not user.is_active:
            return Response(
                {"error": "Ce compte est désactivé."},
                status=status.HTTP_403_FORBIDDEN
            )

        role = get_user_role(user)

        if role is None:
            return Response(
                {"error": "Aucun rôle n'est associé à ce compte."},
                status=status.HTTP_403_FORBIDDEN
            )

        refresh = RefreshToken.for_user(user)

        return Response({
            "message": "Connexion réussie",
            "user": construire_profil(user),
            "access": str(refresh.access_token),
            "refresh": str(refresh),
        }, status=status.HTTP_200_OK)


class UserProfileView(APIView):
    """Récupération du profil connecté."""

    permission_classes = [IsAuthenticated]

    def get(self, request):

        role = get_user_role(request.user)

        if role is None:
            return Response(
                {"error": "Aucun rôle associé à ce compte."},
                status=status.HTTP_403_FORBIDDEN
            )

        return Response({
            "user": construire_profil(request.user)
        })


class LogoutView(APIView):
    """Déconnexion et révocation du jeton de renouvellement."""

    permission_classes = [IsAuthenticated]

    def post(self, request):

        raw_token = request.data.get("refresh")

        if not raw_token:
            return Response(
                {"error": "Jeton de renouvellement obligatoire."},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            refresh = RefreshToken(raw_token)

            if str(refresh.get("user_id")) != str(request.user.pk):
                return Response(
                    {"error": "Ce jeton n'appartient pas à ce compte."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            refresh.blacklist()

        except TokenError:
            return Response(
                {"error": "Jeton invalide ou déjà révoqué."},
                status=status.HTTP_400_BAD_REQUEST
            )

        return Response({
            "message": "Déconnexion réussie."
        })
        
