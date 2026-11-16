"""
Résolution des rôles SGSUS à partir des groupes et profils Django.

Un compte possède au plus un rôle « effectif », déterminé par ordre de
priorité (admin > responsable > encadreur > jury > étudiant). Ce rôle est
utilisé à la fois par les permissions de l'API et par l'interface Flutter
pour adapter la navigation.
"""

# Noms des groupes Django correspondant aux rôles SGSUS.
ROLE_GROUPS = ('admin', 'student', 'supervisor', 'responsible', 'jury')

# Ordre de priorité utilisé lorsqu'un compte cumule plusieurs rôles.
ROLE_PRIORITY = ('admin', 'responsible', 'supervisor', 'jury', 'student')


def has_role_group(user, role):
    """
    Indique si un compte authentifié possède le rôle demandé.

    Paramètres :
        user : utilisateur Django (ou objet compatible).
        role (str) : rôle à tester, parmi ROLE_GROUPS.

    Retour :
        bool : True si le compte détient ce rôle.

    Règles particulières :
        * un superutilisateur est toujours considéré comme « admin » ;
        * « student » et « jury » se déduisent de la liaison à une fiche
          métier (StudentAccount / JuryMemberAccount), pas d'un groupe.
    """
    if not getattr(user, 'is_authenticated', False):
        return False
    if role == 'admin' and getattr(user, 'is_superuser', False):
        return True
    if role == 'student':
        try:
            return user.student_account is not None
        except AttributeError:
            # Compatibilité : objet portant directement un attribut `role`.
            return getattr(user, 'role', None) == 'student'
    if role == 'jury':
        try:
            return user.jury_member_account is not None
        except AttributeError:
            # Relation inverse absente : le compte n'est pas lié à un jury.
            return False
    groups = getattr(user, 'groups', None)
    return groups.filter(name=role).exists() if groups is not None else False


def get_user_role(user):
    """
    Retourne le rôle unique utilisé par l'API et l'interface Flutter.

    Paramètres :
        user : utilisateur Django.

    Retour :
        str | None : premier rôle détenu selon ROLE_PRIORITY, ou None si le
        compte n'est pas authentifié ou n'a aucun rôle SGSUS.
    """
    if not getattr(user, 'is_authenticated', False):
        return None

    for role in ROLE_PRIORITY:
        if has_role_group(user, role):
            return role
    return None
