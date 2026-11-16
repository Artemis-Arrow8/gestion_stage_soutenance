"""
Vues d'authentification de l'API SGSUS : connexion, profil et déconnexion.

Le client Flutter s'authentifie par JWT (SimpleJWT) :
    1. POST /api/login/        -> jetons `access` + `refresh` et profil ;
    2. GET  /api/profile/      -> profil du compte porteur du jeton ;
    3. POST /api/token/refresh/ -> renouvellement (vue fournie par SimpleJWT) ;
    4. POST /api/logout/       -> mise en liste noire du jeton `refresh`.

Les réponses d'erreur utilisent la clé `error`, que le client Flutter sait
extraire pour afficher un message lisible.
"""

from django.contrib.auth import authenticate
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from api.models import InternshipFolder
from api.roles import get_user_role

from .helpers import etudiant_du_compte


def construire_profil(user, role=None):
    """
    Construit le dictionnaire de profil renvoyé au client Flutter.

    Paramètres :
        user : utilisateur Django authentifié.
        role (str | None) : rôle déjà calculé (évite une seconde requête) ;
            s'il est absent, il est déduit des groupes/profils du compte.

    Retour :
        dict : identité commune (id, username, email, full_name, role),
        enrichie selon le profil :
          * étudiant : numéro, fiche et dossier de la campagne active ;
          * membre du jury : identifiants du membre et de son jury.
    """
    role = role or get_user_role(user)
    profile = {
        'id': user.pk,
        'username': user.get_username(),
        'email': user.email,
        # Nom complet lisible ; à défaut, l'identifiant de connexion.
        'full_name': ' '.join(
            part for part in (user.first_name, user.last_name) if part
        ) or user.get_username(),
        'role': role,
    }

    student = etudiant_du_compte(user)
    if student is None:
        # Compte non étudiant : on ajoute éventuellement le rattachement jury.
        account = getattr(user, 'jury_member_account', None)
        if account is not None:
            profile.update({
                'jury_member_id': account.jury_member_id,
                'jury_id': account.jury_member.jury_id,
                'jury_member_name': account.jury_member.member_name,
            })
        return profile

    # Compte étudiant : on expose le dossier le plus récent de la campagne
    # active afin que l'interface puisse afficher directement son statut.
    folder = InternshipFolder.objects.filter(
        student=student,
        campaign__is_active=True,
    ).order_by('-created_at').first()
    profile.update({
        # L'identifiant exposé est celui de la fiche étudiante (contrat historique).
        'id': student.pk,
        'student_number': student.student_number,
        'full_name': student.full_name,
        'email': student.email,
        'folder_id': folder.pk if folder else None,
        'folder_status': folder.status if folder else None,
    })
    return profile


class LoginView(APIView):
    """
    Authentifie un identifiant/mot de passe et délivre une paire de JWT.

    Route : POST /api/login/  (publique : aucune authentification préalable).
    Corps attendu : {"username": str, "password": str}.
    Réponses :
        200 : {"message", "user", "access", "refresh"} ;
        400 : champs manquants ou de mauvais type ;
        401 : identifiants incorrects ;
        403 : compte valide mais sans rôle SGSUS.
    """

    # Vue publique : on désactive l'authentification et les permissions DRF.
    authentication_classes = []
    permission_classes = []

    def post(self, request):
        """Valide la saisie, authentifie le compte puis renvoie les jetons."""
        username = request.data.get('username')
        password = request.data.get('password')
        # Contrôle défensif du type : un JSON malformé ne doit pas lever de 500.
        if (
            not isinstance(username, str)
            or not username.strip()
            or not isinstance(password, str)
            or not password
        ):
            return Response(
                {'error': 'Veuillez fournir votre identifiant et votre mot de passe.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # `authenticate` applique les backends Django (hachage, compte actif…).
        user = authenticate(
            request,
            username=username.strip(),
            password=password,
        )
        if user is None:
            return Response(
                {'error': 'Identifiant ou mot de passe incorrect.'},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        # Un compte sans rôle métier ne doit pas accéder à l'application.
        role = get_user_role(user)
        if role is None:
            return Response(
                {'error': "Aucun rôle SGSUS n'est associé à ce compte."},
                status=status.HTTP_403_FORBIDDEN,
            )

        refresh = RefreshToken.for_user(user)
        return Response({
            'message': 'Connexion réussie',
            'user': construire_profil(user, role),
            'access': str(refresh.access_token),
            'refresh': str(refresh),
        })


class UserProfileView(APIView):
    """
    Renvoie le profil du compte authentifié.

    Route : GET /api/profile/  (JWT obligatoire).
    Réponses : 200 {"user": {...}} ou 403 si le compte n'a aucun rôle SGSUS.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        """Calcule le rôle courant et sérialise le profil correspondant."""
        role = get_user_role(request.user)
        if role is None:
            return Response(
                {'error': "Aucun rôle SGSUS n'est associé à ce compte."},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response({'user': construire_profil(request.user, role)})


class LogoutView(APIView):
    """
    Invalide le jeton de renouvellement pour déconnecter l'utilisateur.

    Route : POST /api/logout/  (JWT d'accès obligatoire).
    Corps attendu : {"refresh": str}.
    Le jeton doit appartenir au compte connecté : un utilisateur ne peut pas
    révoquer la session d'un autre.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        """Vérifie la propriété du jeton puis l'inscrit en liste noire."""
        raw_token = request.data.get('refresh')
        if not isinstance(raw_token, str) or not raw_token:
            return Response(
                {'error': 'Le jeton de renouvellement est obligatoire.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            refresh = RefreshToken(raw_token)
            # Comparaison en chaîne : `user_id` peut être stocké en str ou int.
            if str(refresh.get('user_id')) != str(request.user.pk):
                return Response(
                    {'error': "Ce jeton n'appartient pas au compte connecté."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            refresh.blacklist()
        except TokenError:
            # Jeton expiré, mal signé ou déjà révoqué.
            return Response(
                {'error': 'Le jeton de renouvellement est invalide ou révoqué.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(
            {'message': 'Déconnexion réussie.'},
            status=status.HTTP_200_OK,
        )
