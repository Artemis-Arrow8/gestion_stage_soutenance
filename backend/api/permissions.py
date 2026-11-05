from rest_framework import permissions
from .roles import get_user_role


class IsAdminOrPedagogicalResponsible(permissions.BasePermission):
    """Autorise les administrateurs et responsables pédagogiques."""
    def has_permission(self, request, view):
        return get_user_role(request.user) in ('admin', 'responsible')

class IsStudent(permissions.BasePermission):
    """Autorise les étudiants dont le compte est lié à une fiche métier."""
    def has_permission(self, request, view):
        return get_user_role(request.user) == 'student'


class IsAdminResponsibleOrStudent(permissions.BasePermission):
    """Autorise le personnel pédagogique et l’étudiant propriétaire."""

    def has_permission(self, request, view):
        return get_user_role(request.user) in ('admin', 'responsible', 'student')


class IsSupervisor(permissions.BasePermission):
    """Autorise les encadreurs et les administrateurs aux avis."""
    def has_permission(self, request, view):
        return get_user_role(request.user) in ('admin', 'supervisor')


class IsAccountAdministrator(permissions.BasePermission):
    """Réserve la gestion des comptes aux superutilisateurs et au groupe admin."""
    def has_permission(self, request, view):
        return get_user_role(request.user) == 'admin'