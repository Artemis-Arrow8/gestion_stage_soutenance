from rest_framework import permissions
from .roles import get_user_role


class IsAdminOrPedagogicalResponsible(permissions.BasePermission):
    """Autorise les administrateurs et responsables pédagogiques."""
    def has_permission(self, request, view):
        return get_user_role(request.user) in ('admin', 'responsible')


class IsAdminResponsibleOrAssignedJuryReader(permissions.BasePermission):
    """Réserve les écritures au personnel et limite le jury à la lecture."""
    def has_permission(self, request, view):
        role = get_user_role(request.user)
        return role in ('admin', 'responsible') or (
            role == 'jury' and request.method in permissions.SAFE_METHODS
        )


class IsStudent(permissions.BasePermission):
    """Autorise les étudiants dont le compte est lié à une fiche métier."""
    def has_permission(self, request, view):
        return get_user_role(request.user) == 'student'


class IsAdminResponsibleOrStudent(permissions.BasePermission):
    """Autorise le personnel, les encadreurs en lecture et les étudiants."""

    def has_permission(self, request, view):
        role = get_user_role(request.user)
        if role in ('admin', 'responsible', 'student'):
            return True
        return role == 'supervisor' and request.method in permissions.SAFE_METHODS


class IsSupervisor(permissions.BasePermission):
    """Autorise les encadreurs et les administrateurs aux avis."""
    def has_permission(self, request, view):
        return get_user_role(request.user) in ('admin', 'supervisor')


class IsReviewReader(permissions.BasePermission):
    """Autorise la lecture des avis à leur propriétaire et au personnel habilité."""

    def has_permission(self, request, view):
        return get_user_role(request.user) in ('admin', 'supervisor', 'student')


class IsAccountAdministrator(permissions.BasePermission):
    """Réserve la gestion des comptes aux superutilisateurs et au groupe admin."""
    def has_permission(self, request, view):
        return get_user_role(request.user) == 'admin'