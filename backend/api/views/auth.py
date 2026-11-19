"""
Vues d'authentification de l'API SGSUS : connexion, profil et déconnexion.

Le client Flutter s'authentifie par JWT (SimpleJWT) :
    1. POST /api/login/        -> jetons `access` + `refresh` et profil ;
    2. GET  /api/profile/      -> profil du compte porteur du jeton ;
    3. POST /api/token/refresh/ -> renouvellement (vue fournie par SimpleJWT) ;
    4. POST /api/logout/       -> mise en liste noire du jeton `refresh` ;
    5. POST /api/profile/password/ -> changement de son propre mot de passe.

Les réponses d'erreur utilisent la clé `error`, que le client Flutter sait
extraire pour afficher un message lisible.
"""

from django.contrib.auth import authenticate, password_validation
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from api.models import Assessment, Defense, InternshipFolder
from api.roles import get_user_role

from .helpers import etudiant_du_compte


def _soutenance_du_dossier(folder):
    """
    Résume la soutenance d'un dossier pour l'espace étudiant.

    Paramètres :
        folder (InternshipFolder) : dossier de l'étudiant.

    Retour :
        dict | None : créneau (ISO 8601), salle, jury et statut de la
        soutenance la plus récente, avec la note finale si elle a été
        validée ; None si aucune soutenance n'est planifiée.
    """
    defense = (
        Defense.objects.select_related('jury')
        .filter(folder=folder)
        .order_by('-slot_range')
        .first()
    )
    if defense is None:
        return None
    slot = defense.slot_range
    resume = {
        'id': defense.pk,
        'slot_start': slot.lower.isoformat() if slot and slot.lower else None,
        'slot_end': slot.upper.isoformat() if slot and slot.upper else None,
        'room_name': defense.room_name,
        'jury_name': defense.jury.name if defense.jury else None,
        'status': defense.status,
        'final_average': None,
    }
    # La note n'est communiquée à l'étudiant qu'une fois validée.
    evaluation = Assessment.objects.filter(defense=defense, is_approved=True).first()
    if evaluation is not None and evaluation.final_average is not None:
        resume['final_average'] = str(evaluation.final_average)
    return resume


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
        # Informations du dossier et de la soutenance, pour le tableau de bord.
        'folder_company': folder.company_name if folder else None,
        'folder_subject': folder.subject if folder else None,
        'defense': _soutenance_du_dossier(folder) if folder else None,
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
        403 : compte valide mais sans rôle SGSUS ;
        429 : trop de tentatives depuis la même adresse (force brute).
    """

    # Vue publique : on désactive l'authentification et les permissions DRF.
    authentication_classes = []
    permission_classes = []
    # Limitation des tentatives par adresse IP (chapitre 13), réglée par
    # SGSUS_LIMITE_CONNEXION (10 par minute par défaut).
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'connexion'

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


class ChangePasswordView(APIView):
    """
    Permet à l'utilisateur connecté de changer son propre mot de passe.

    Route : POST /api/profile/password/  (JWT obligatoire).
    Corps attendu : {"old_password": str, "new_password": str}.
    Réponses :
        200 : mot de passe modifié ;
        400 : champs manquants, ancien mot de passe incorrect, ou nouveau
              mot de passe refusé par les règles de sécurité de Django.
    La session en cours reste valide : les jetons JWT ne dépendent pas du
    mot de passe.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        """Vérifie l'ancien mot de passe, valide le nouveau puis l'enregistre."""
        ancien = request.data.get('old_password')
        nouveau = request.data.get('new_password')
        if not isinstance(ancien, str) or not isinstance(nouveau, str) or not nouveau:
            return Response(
                {'error': 'Indiquez votre mot de passe actuel et le nouveau.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = request.user
        # L'ancien mot de passe prouve que c'est bien le titulaire du compte.
        if not user.check_password(ancien):
            return Response(
                {'error': 'Le mot de passe actuel est incorrect.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if ancien == nouveau:
            return Response(
                {'error': 'Le nouveau mot de passe doit être différent de l’actuel.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Règles de sécurité configurées (longueur, mots courants, etc.).
        try:
            password_validation.validate_password(nouveau, user=user)
        except DjangoValidationError as error:
            return Response(
                {'error': ' '.join(error.messages)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # `set_password` hache le mot de passe avant l'enregistrement.
        user.set_password(nouveau)
        user.save(update_fields=['password'])
        return Response({'message': 'Mot de passe modifié avec succès.'})
