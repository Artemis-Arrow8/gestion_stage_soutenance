"""
Classes de permission DRF fondées sur les rôles SGSUS.

Chaque classe répond à la question « ce rôle peut-il appeler cette route
avec cette méthode HTTP ? ». Le filtrage fin des lignes visibles (périmètre
d'un étudiant, d'un encadreur…) est réalisé dans les `get_queryset` des vues.
"""

from rest_framework import permissions

from .roles import get_user_role

# Rôles du personnel pédagogique disposant d'un accès complet.
ROLES_PERSONNEL = ('admin', 'responsible')


class IsAdminOrPedagogicalResponsible(permissions.BasePermission):
    """Autorise uniquement les administrateurs et responsables pédagogiques."""

    def has_permission(self, request, view):
        """Retourne True si l'appelant fait partie du personnel."""
        return get_user_role(request.user) in ROLES_PERSONNEL


class IsAdminResponsibleOrAssignedJuryReader(permissions.BasePermission):
    """Réserve les écritures au personnel et limite le jury à la lecture."""

    def has_permission(self, request, view):
        """
        Retourne True pour le personnel (toutes méthodes) ou pour un membre
        du jury utilisant une méthode sûre (GET, HEAD, OPTIONS).
        """
        role = get_user_role(request.user)
        return role in ROLES_PERSONNEL or (
            role == 'jury' and request.method in permissions.SAFE_METHODS
        )


class IsStudent(permissions.BasePermission):
    """Autorise les étudiants dont le compte est lié à une fiche métier."""

    def has_permission(self, request, view):
        """Retourne True si l'appelant a le rôle étudiant."""
        return get_user_role(request.user) == 'student'


class IsAdminResponsibleOrStudent(permissions.BasePermission):
    """Autorise le personnel, les étudiants et les encadreurs en lecture."""

    def has_permission(self, request, view):
        """
        Retourne True pour le personnel et les étudiants (toutes méthodes),
        ou pour un encadreur utilisant une méthode sûre.
        """
        role = get_user_role(request.user)
        if role in ('admin', 'responsible', 'student'):
            return True
        return role == 'supervisor' and request.method in permissions.SAFE_METHODS


class IsSupervisor(permissions.BasePermission):
    """Autorise les encadreurs et les administrateurs à rédiger des avis."""

    def has_permission(self, request, view):
        """Retourne True pour un administrateur ou un encadreur."""
        return get_user_role(request.user) in ('admin', 'supervisor')


class IsReviewReader(permissions.BasePermission):
    """Autorise la lecture des avis à leur propriétaire et au personnel habilité."""

    def has_permission(self, request, view):
        """Retourne True pour un administrateur, un encadreur ou un étudiant."""
        return get_user_role(request.user) in ('admin', 'supervisor', 'student')


class IsAccountAdministrator(permissions.BasePermission):
    """Réserve la gestion des comptes aux superutilisateurs et au groupe admin."""

    def has_permission(self, request, view):
        """Retourne True uniquement pour le rôle administrateur."""
        return get_user_role(request.user) == 'admin'


class IsPersonnelOrJury(permissions.BasePermission):
    """
    Personnel (admin, responsable) ou membre du jury.

    Le périmètre fin (soutenances de SON jury, président pour l'approbation)
    est vérifié par la vue et par api/services/notes.py.
    """

    def has_permission(self, request, view):
        """Retourne True pour le personnel et les membres du jury."""
        return get_user_role(request.user) in ROLES_PERSONNEL + ('jury',)
