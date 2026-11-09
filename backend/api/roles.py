def get_user_role(user):
    """Détermine le rôle d'un utilisateur Django."""

    if not user or not user.is_authenticated or not user.is_active:
        return None

    if user.is_superuser:
        return "admin"

    roles = ("admin", "responsible", "supervisor", "student")

    groupes = user.groups.values_list("name", flat=True)

    for role in roles:
        if role in groupes:
            return role

    return None