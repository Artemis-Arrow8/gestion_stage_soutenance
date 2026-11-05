"""Résolution des rôles SGSUS à partir des groupes et profils Django."""

ROLE_GROUPS = ('admin', 'student', 'supervisor', 'responsible')


def has_role_group(user, role):
    """Indique si un compte actif appartient au groupe du rôle demandé."""
    if not getattr(user, 'is_authenticated', False):
        return False
    if role == 'admin' and getattr(user, 'is_superuser', False):
        return True
    if role == 'student':
        try:
            return user.student_account is not None
        except AttributeError:
            return getattr(user, 'role', None) == 'student'
    groups = getattr(user, 'groups', None)
    return groups.filter(name=role).exists() if groups is not None else False


def get_user_role(user):
    """Retourne le rôle unique utilisé par l'API et l'interface Flutter."""
    if not getattr(user, 'is_authenticated', False):
        return None

    for role in ('admin', 'responsible', 'supervisor', 'student'):
        if has_role_group(user, role):
            return role
    return None
