"""
Vues des données ajoutées pour le socle du dossier ALM.

* /api/indisponibilites/       : indisponibilités récurrentes (personnel) ;
* /api/versions-planning/      : versions publiées du planning (lecture) ;
* /api/convocations/           : convocations ; chacun ne voit que les
                                 siennes, le personnel voit tout ;
* /api/habilitations/          : habilitations sur les dossiers
                                 confidentiels (personnel) ; DELETE révoque
                                 l'habilitation sans effacer sa trace.
"""
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from api.models import Convocation, HabilitationDossier, Indisponibilite, VersionPlanning
from api.permissions import ROLES_PERSONNEL, IsAdminOrPedagogicalResponsible
from api.roles import get_user_role
from api.serializers import (
    ConvocationSerializer,
    HabilitationDossierSerializer,
    IndisponibiliteSerializer,
    VersionPlanningSerializer,
)
from api.services.disponibilites import soutenances_publiees_concernees


class IndisponibiliteViewSet(viewsets.ModelViewSet):
    """
    Indisponibilités récurrentes des membres de jury et des salles (F04).

    À la création, la réponse contient `alertes` : les soutenances DÉJÀ
    publiées touchées par la nouvelle indisponibilité. Elles ne sont ni
    déplacées ni supprimées : le planificateur décide (report ou maintien).
    Filtres : ?ressource=<nom>&type_ressource=membre|salle.
    """

    queryset = Indisponibilite.objects.prefetch_related('exceptions')
    serializer_class = IndisponibiliteSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]

    def get_queryset(self):
        """Applique les filtres facultatifs."""
        base = super().get_queryset()
        ressource = self.request.query_params.get('ressource')
        type_ressource = self.request.query_params.get('type_ressource')
        if ressource:
            base = base.filter(ressource=ressource)
        if type_ressource:
            base = base.filter(type_ressource=type_ressource)
        return base

    def create(self, request, *args, **kwargs):
        """Crée la règle et signale les soutenances publiées concernées."""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        regle = serializer.save(cree_par=request.user)
        donnees = self.get_serializer(regle).data
        donnees['alertes'] = [
            {
                'soutenance': soutenance.pk,
                'debut': soutenance.slot_range.lower,
                'salle': soutenance.room_name,
                'message': (f"La soutenance #{soutenance.pk} déjà publiée tombe sur cette "
                            "indisponibilité : à reporter ou à confirmer."),
            }
            for soutenance in soutenances_publiees_concernees(regle)
        ]
        return Response(donnees, status=status.HTTP_201_CREATED)


class VersionPlanningViewSet(viewsets.ReadOnlyModelViewSet):
    """Historique des versions publiées du planning (tout compte connecté)."""

    queryset = VersionPlanning.objects.all()
    serializer_class = VersionPlanningSerializer
    permission_classes = [IsAuthenticated]


class ConvocationViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Convocations aux soutenances.

    Le personnel voit toutes les convocations ; un étudiant ou un membre du
    jury ne voit que les siennes (actives, remplacées ou annulées : une
    convocation remplacée reste identifiable). Filtre : ?soutenance=<id>.
    """

    queryset = Convocation.objects.select_related(
        'version', 'remplacee_par__version', 'soutenance__folder__student',
    )
    serializer_class = ConvocationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        """Limite chaque compte à ses propres convocations."""
        base = super().get_queryset()
        if get_user_role(self.request.user) not in ROLES_PERSONNEL:
            base = base.filter(compte=self.request.user)
        soutenance = self.request.query_params.get('soutenance')
        if soutenance and soutenance.isdigit():
            base = base.filter(soutenance_id=int(soutenance))
        return base


class HabilitationDossierViewSet(mixins.CreateModelMixin, mixins.ListModelMixin,
                                 mixins.DestroyModelMixin, viewsets.GenericViewSet):
    """
    Habilitations nominatives sur les dossiers confidentiels (personnel).

    DELETE ne supprime pas la ligne : il RÉVOQUE l'habilitation (la trace
    reste, l'accès cesse immédiatement, y compris par une ancienne URL).
    Filtre : ?dossier=<id>.
    """

    queryset = HabilitationDossier.objects.select_related('beneficiaire')
    serializer_class = HabilitationDossierSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]

    def get_queryset(self):
        """Filtre facultatif par dossier."""
        base = super().get_queryset()
        dossier = self.request.query_params.get('dossier')
        if dossier and dossier.isdigit():
            base = base.filter(dossier_id=int(dossier))
        return base

    def perform_create(self, serializer):
        """L'auteur est déduit du jeton ; début de validité par défaut : maintenant."""
        serializer.save(
            accordee_par=self.request.user,
            valide_du=serializer.validated_data.get('valide_du') or timezone.now(),
        )

    def perform_destroy(self, instance):
        """Révoque au lieu de supprimer."""
        instance.revoquee = True
        instance.save(update_fields=['revoquee'])
