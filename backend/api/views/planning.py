"""
Vues du module de planification : salles, jurys, membres et soutenances.

Les contrôles de conflits (EXG01 : pas de double réservation d'une salle ou
d'un jury) sont faits à deux niveaux :
    * applicatif, dans `api.services.conflicts` (messages lisibles) ;
    * base de données, par des contraintes d'exclusion PostgreSQL qui
      protègent contre les écritures concurrentes. Une violation de ces
      contraintes est traduite ici en erreur HTTP 400 compréhensible.
"""

from datetime import timedelta

from django.db import IntegrityError, transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response

from api.models import Defense, Jury, JuryMember, Room
from api.permissions import (
    IsAdminOrPedagogicalResponsible,
    IsAdminResponsibleOrAssignedJuryReader,
)
from api.roles import get_user_role
from api.serializers import (
    DefenseSerializer,
    JuryMemberSerializer,
    JurySerializer,
    SalleSerializer,
)

from .helpers import debut_jour_utc, lire_parametre_date

# Plage d'ouverture des salles utilisée pour calculer les disponibilités.
HEURE_OUVERTURE = 8
HEURE_FERMETURE = 20

# Noms des contraintes d'exclusion PostgreSQL définies dans database/schema.sql.
CONTRAINTES_DOUBLE_RESERVATION = {
    'prevent_room_double_booking',
    'prevent_jury_double_booking',
}


class SalleViewSet(viewsets.ModelViewSet):
    """
    Catalogue des salles de soutenance (/api/salles/ et /api/rooms/).

    Fournit en plus l'action GET /api/salles/<id>/disponibilites/?date=AAAA-MM-JJ
    qui calcule les créneaux libres et occupés d'une salle sur une journée.
    """

    queryset = Room.objects.all().order_by('name')
    serializer_class = SalleSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]

    @action(detail=True, methods=['get'], url_path='disponibilites')
    def disponibilites(self, request, pk=None):
        """
        Calcule les disponibilités d'une salle pour une date donnée.

        Paramètres (query string) :
            date (obligatoire) : jour au format AAAA-MM-JJ.

        Retour :
            200 {"date", "creneaux_occupes": [...], "creneaux_libres": [...]}
            où chaque créneau est {"debut", "fin"} en ISO 8601 (UTC) ;
            400 si la date est absente ou invalide.
        """
        salle = self.get_object()
        try:
            jour = lire_parametre_date(request, 'date', obligatoire=True)
        except ValidationError as error:
            return Response(
                error.detail,
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Fenêtre d'ouverture de la journée (UTC).
        debut_jour = debut_jour_utc(jour)
        debut_ouverture = debut_jour + timedelta(hours=HEURE_OUVERTURE)
        fin_ouverture = debut_jour + timedelta(hours=HEURE_FERMETURE)

        # Soutenances de cette salle qui chevauchent la fenêtre d'ouverture.
        reservations = Defense.objects.filter(
            room_name=salle.name,
            slot_range__overlap=DateTimeTZRange(
                debut_ouverture,
                fin_ouverture,
                bounds='[)',
            ),
        ).order_by('slot_range')

        # Balayage chronologique : un « curseur » avance de réservation en
        # réservation ; chaque trou entre le curseur et la réservation
        # suivante constitue un créneau libre.
        occupes = []
        libres = []
        curseur = debut_ouverture
        for defense in reservations:
            # On tronque les réservations qui débordent de la fenêtre.
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
        # Créneau libre final jusqu'à la fermeture.
        if curseur < fin_ouverture:
            libres.append({'debut': curseur.isoformat(), 'fin': fin_ouverture.isoformat()})

        return Response({
            'date': jour.isoformat(),
            'creneaux_occupes': occupes,
            'creneaux_libres': libres,
        })


class JuryViewSet(viewsets.ModelViewSet):
    """
    Gestion des jurys (/api/jurys/).

    Le personnel a un accès complet ; un membre du jury ne voit, en lecture,
    que les jurys dans lesquels il siège.
    """

    queryset = Jury.objects.all().order_by('name')
    serializer_class = JurySerializer
    permission_classes = [IsAdminResponsibleOrAssignedJuryReader]

    def get_queryset(self):
        """Restreint un membre du jury à ses propres jurys."""
        if get_user_role(self.request.user) == 'jury':
            return self.queryset.filter(
                members__account__user=self.request.user
            ).distinct()
        return self.queryset


class JuryMemberViewSet(viewsets.ModelViewSet):
    """
    Gestion des membres de jury (/api/jury-members/ et /api/membres-jury/).

    Un membre du jury ne voit que sa propre fiche.
    """

    queryset = JuryMember.objects.all()
    serializer_class = JuryMemberSerializer
    permission_classes = [IsAdminResponsibleOrAssignedJuryReader]

    def get_queryset(self):
        """Restreint un membre du jury à sa propre fiche."""
        if get_user_role(self.request.user) == 'jury':
            return self.queryset.filter(account__user=self.request.user)
        return self.queryset


class DefenseViewSet(viewsets.ModelViewSet):
    """
    Planification des soutenances (/api/soutenances/ et /api/defenses/).

    Fournit en plus l'action GET /api/soutenances/planning/ qui renvoie la
    liste filtrée et triée chronologiquement (voir `planning`).
    """

    queryset = Defense.objects.all()
    serializer_class = DefenseSerializer
    permission_classes = [IsAdminResponsibleOrAssignedJuryReader]

    def get_queryset(self):
        """Restreint un membre du jury aux soutenances de ses jurys."""
        if get_user_role(self.request.user) == 'jury':
            return self.queryset.filter(
                jury__members__account__user=self.request.user
            ).distinct()
        return self.queryset

    def _enregistrer_soutenance(self, serializer):
        """
        Sauvegarde une soutenance en traduisant les conflits de concurrence.

        Deux requêtes simultanées peuvent passer le contrôle applicatif ; la
        contrainte d'exclusion PostgreSQL rejette alors la seconde. On
        transforme cette `IntegrityError` en erreur 400 explicite.

        Lève :
            ValidationError : conflit de salle ou de jury (EXG01).
            IntegrityError : toute autre violation, propagée telle quelle.
        """
        try:
            # Le savepoint isole l'échec sans casser la transaction englobante.
            with transaction.atomic():
                serializer.save()
        except IntegrityError as error:
            # psycopg expose le nom de la contrainte violée via `diag`.
            cause = error.__cause__
            constraint_name = getattr(
                getattr(cause, 'diag', None), 'constraint_name', None
            )
            if constraint_name in CONTRAINTES_DOUBLE_RESERVATION:
                raise ValidationError(
                    {'detail': 'Conflit de réservation : la salle ou le jury '
                               'est déjà engagé sur ce créneau (EXG01).'}
                ) from error
            raise

    def perform_create(self, serializer):
        """Crée une soutenance avec gestion des conflits."""
        self._enregistrer_soutenance(serializer)

    def perform_update(self, serializer):
        """Modifie une soutenance avec gestion des conflits."""
        self._enregistrer_soutenance(serializer)

    @action(detail=False, methods=['get'], url_path='planning')
    def planning(self, request):
        """
        Renvoie le planning des soutenances, filtré et trié.

        Paramètres (query string, tous facultatifs) :
            date : un jour précis (AAAA-MM-JJ) ;
            date_debut + date_fin : une période inclusive (exclusif avec `date`) ;
            salle : nom exact de la salle ;
            statut : statut de la soutenance ;
            jury : identifiant entier du jury.

        Retour :
            200 {"total": int, "soutenances": [...]} trié par créneau ;
            400 si un paramètre est invalide ou incohérent.
        """
        queryset = self.get_queryset()
        date_value = request.query_params.get('date')
        date_debut_value = request.query_params.get('date_debut')
        date_fin_value = request.query_params.get('date_fin')
        # Une journée ET une période en même temps seraient ambiguës.
        if date_value and (date_debut_value or date_fin_value):
            return Response(
                {'date': 'Choisissez une date ou une période, pas les deux.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            jour = lire_parametre_date(request, 'date')
            if jour is not None:
                # Filtre « journée » : [minuit ; minuit du lendemain[.
                debut = debut_jour_utc(jour)
                queryset = queryset.filter(
                    slot_range__overlap=DateTimeTZRange(
                        debut, debut + timedelta(days=1)
                    )
                )
            elif date_debut_value or date_fin_value:
                # Filtre « période » : les deux bornes deviennent obligatoires.
                date_debut = lire_parametre_date(
                    request, 'date_debut', obligatoire=True
                )
                date_fin = lire_parametre_date(
                    request, 'date_fin', obligatoire=True
                )
                if date_fin < date_debut:
                    raise ValidationError({
                        'date_debut': (
                            'La date de début doit précéder ou égaler la date de fin.'
                        )
                    })
                debut = debut_jour_utc(date_debut)
                # Borne haute exclusive : lendemain de la date de fin.
                fin = debut_jour_utc(date_fin + timedelta(days=1))
                queryset = queryset.filter(
                    slot_range__overlap=DateTimeTZRange(debut, fin)
                )
        except ValidationError as error:
            return Response(error.detail, status=status.HTTP_400_BAD_REQUEST)

        # Filtres simples complémentaires.
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

        # Tri chronologique stable (le `pk` départage les créneaux identiques).
        soutenances = queryset.order_by('slot_range', 'pk')
        donnees = DefenseSerializer(soutenances, many=True).data
        return Response({'total': len(donnees), 'soutenances': donnees})
