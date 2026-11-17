"""
Paquet des vues de l'API SGSUS, découpé par domaine fonctionnel.

Organisation :
    * `auth`     : connexion, profil, mot de passe, déconnexion (JWT) ;
    * `accounts` : administration des comptes utilisateurs ;
    * `academic` : campagnes, étudiants, dossiers, documents, avis, évaluations ;
    * `planning` : salles, jurys, membres de jury et soutenances ;
    * `system`   : page d'accueil publique de la racine `/` ;
    * `helpers`  : fonctions utilitaires partagées.

Ce fichier réexporte toutes les vues afin que `from api.views import X`
continue de fonctionner (routes, tests et modules existants).
"""

from .academic import (
    AssessmentViewSet,
    CampaignViewSet,
    DocumentVersionViewSet,
    InternshipFolderViewSet,
    ReviewViewSet,
    StudentViewSet,
)
from .accounts import UserAccountViewSet
from .auth import (
    ChangePasswordView,
    LoginView,
    LogoutView,
    UserProfileView,
    construire_profil,
)
from .helpers import debut_jour_utc, etudiant_du_compte, lire_parametre_date
from .planning import DefenseViewSet, JuryMemberViewSet, JuryViewSet, SalleViewSet
from .system import accueil

# Alias historiques conservés pour la rétrocompatibilité : les tests unitaires
# existants appellent encore `views._parametre_date` et `views._jour_UTC`.
_parametre_date = lire_parametre_date
_jour_UTC = debut_jour_utc

# Liste explicite des noms publics du paquet.
__all__ = [
    'AssessmentViewSet',
    'CampaignViewSet',
    'ChangePasswordView',
    'DefenseViewSet',
    'DocumentVersionViewSet',
    'InternshipFolderViewSet',
    'JuryMemberViewSet',
    'JuryViewSet',
    'LoginView',
    'LogoutView',
    'ReviewViewSet',
    'SalleViewSet',
    'StudentViewSet',
    'UserAccountViewSet',
    'UserProfileView',
    'accueil',
    'construire_profil',
    'debut_jour_utc',
    'etudiant_du_compte',
    'lire_parametre_date',
]
