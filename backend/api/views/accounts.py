"""
Vue d'administration des comptes utilisateurs SGSUS.

Seuls les administrateurs (superutilisateurs ou groupe `admin`) peuvent
lister, consulter, créer et modifier des comptes. La suppression n'est
volontairement pas exposée : on désactive un compte (`is_active=False`)
afin de conserver l'historique (avis rédigés, etc.).
"""

from django.contrib.auth import get_user_model
from rest_framework import mixins, viewsets

from api.permissions import IsAccountAdministrator
from api.serializers import UserAccountSerializer

# Modèle utilisateur actif du projet (auth.User par défaut).
User = get_user_model()


class UserAccountViewSet(
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.CreateModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    """
    CRUD (sans suppression) des comptes : /api/accounts/.

    Le sérialiseur gère l'attribution du rôle (groupe Django) et la liaison
    éventuelle à une fiche étudiante ou à un membre de jury.
    """

    queryset = User.objects.all().order_by('pk')
    serializer_class = UserAccountSerializer
    permission_classes = [IsAccountAdministrator]

    def get_queryset(self):
        """
        Restreint la liste des comptes visibles.

        Retour :
            QuerySet de tous les comptes pour un superutilisateur ; sinon,
            les superutilisateurs sont masqués afin qu'un administrateur
            métier ne puisse ni les consulter ni les modifier.
        """
        queryset = super().get_queryset()
        if not self.request.user.is_superuser:
            queryset = queryset.filter(is_superuser=False)
        return queryset
