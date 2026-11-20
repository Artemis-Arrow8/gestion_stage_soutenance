"""
Sérialiseur d'administration des comptes utilisateurs.

Il porte toute la logique de cohérence entre :
    * le compte Django (`auth.User`) et son mot de passe ;
    * le rôle SGSUS, matérialisé par l'appartenance à un groupe Django ;
    * la liaison éventuelle à une fiche étudiante (`StudentAccount`) ou à un
      membre de jury (`JuryMemberAccount`).
"""

from django.contrib.auth import get_user_model, password_validation
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from rest_framework import serializers

from api.models import JuryMember, JuryMemberAccount, Student, StudentAccount
from api.roles import ROLE_GROUPS, get_user_role

from .fields import AccountRoleField

# Modèle utilisateur actif du projet.
User = get_user_model()


class UserAccountSerializer(serializers.ModelSerializer):
    """Gestion complète des comptes, de leurs rôles et de leurs profils liés."""

    # Rôle calculé en lecture, choisi parmi ROLE_GROUPS en écriture.
    role = AccountRoleField(choices=ROLE_GROUPS, required=False)
    # Le mot de passe n'est jamais renvoyé dans les réponses.
    password = serializers.CharField(
        write_only=True,
        required=False,
        trim_whitespace=False,
        style={'input_type': 'password'},
    )
    # Fiche étudiante à lier (écriture seule ; exposée via `student_profile`).
    student_id = serializers.PrimaryKeyRelatedField(
        source='student',
        queryset=Student.objects.all(),
        required=False,
        allow_null=True,
        write_only=True,
    )
    student_profile = serializers.SerializerMethodField()
    # Membre de jury à lier (écriture seule ; exposé via `jury_profile`).
    jury_member_id = serializers.PrimaryKeyRelatedField(
        source='jury_member',
        queryset=JuryMember.objects.all(),
        required=False,
        allow_null=True,
        write_only=True,
    )
    jury_profile = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            'id',
            'username',
            'email',
            'first_name',
            'last_name',
            'is_active',
            'role',
            'password',
            'student_id',
            'student_profile',
            'jury_member_id',
            'jury_profile',
        )
        read_only_fields = ('id', 'student_profile', 'jury_profile')

    def validate(self, attrs):
        """
        Valide la cohérence globale rôle / liaisons / mot de passe.

        Règles :
            * un nouveau compte doit avoir un rôle et un mot de passe ;
            * un étudiant doit être lié à une fiche libre, et seul un étudiant
              peut l'être ; même logique pour le rôle jury ;
            * un superutilisateur ne peut être ni rétrogradé ni désactivé ici ;
            * un administrateur ne peut pas se rétrograder/désactiver lui-même ;
            * le mot de passe respecte les validateurs Django configurés.

        Retour :
            dict : les attributs validés.

        Lève :
            serializers.ValidationError : avec le champ fautif en clé.
        """
        instance = self.instance
        # En modification sans rôle fourni, on conserve le rôle actuel.
        role = attrs.get('role', get_user_role(instance) if instance else None)
        student = attrs.get('student')
        jury_member = attrs.get('jury_member')

        if instance is None and role is None:
            raise serializers.ValidationError({'role': 'Le rôle du nouveau compte est obligatoire.'})

        # --- Cohérence du rôle étudiant -----------------------------------
        if role == 'student':
            if student is None and instance is not None:
                # Modification sans nouvelle fiche : on garde la fiche liée.
                try:
                    student = instance.student_account.student
                except AttributeError:
                    student = None
            if student is None:
                raise serializers.ValidationError(
                    {'student_id': 'Un compte étudiant doit être lié à une fiche existante.'}
                )
            # Une fiche ne peut appartenir qu'à un seul compte.
            linked_account = StudentAccount.objects.filter(student=student)
            if instance is not None:
                linked_account = linked_account.exclude(user=instance)
            if linked_account.exists():
                raise serializers.ValidationError(
                    {'student_id': 'Cette fiche étudiante est déjà associée à un compte.'}
                )
        elif student is not None:
            raise serializers.ValidationError(
                {'student_id': 'Seul un compte étudiant peut être lié à une fiche étudiante.'}
            )

        # --- Cohérence du rôle jury ---------------------------------------
        if role == 'jury':
            if jury_member is None and instance is not None:
                try:
                    jury_member = instance.jury_member_account.jury_member
                except AttributeError:
                    jury_member = None
            if jury_member is None:
                raise serializers.ValidationError(
                    {'jury_member_id': 'Un compte jury doit être lié à un membre existant.'}
                )
            linked_account = JuryMemberAccount.objects.filter(
                jury_member=jury_member
            )
            if instance is not None:
                linked_account = linked_account.exclude(user=instance)
            if linked_account.exists():
                raise serializers.ValidationError(
                    {'jury_member_id': 'Ce membre est déjà associé à un compte.'}
                )
        elif jury_member is not None:
            raise serializers.ValidationError(
                {'jury_member_id': 'Seul un compte jury peut être lié à un membre du jury.'}
            )

        # --- Protections des comptes sensibles ------------------------------
        if instance is not None:
            if instance.is_superuser and role != 'admin':
                raise serializers.ValidationError(
                    {'role': 'Le rôle d un superutilisateur ne peut pas être modifié.'}
                )
            if instance.is_superuser and attrs.get('is_active') is False:
                raise serializers.ValidationError(
                    {'is_active': 'Un superutilisateur ne peut pas être désactivé ici.'}
                )
            # Empêche un administrateur de perdre ses propres droits par erreur.
            request = self.context.get('request')
            if request and request.user.pk == instance.pk:
                if role != get_user_role(instance) or attrs.get('is_active') is False:
                    raise serializers.ValidationError(
                        'Vous ne pouvez pas désactiver ou rétrograder votre propre compte.'
                    )

        # --- Mot de passe ----------------------------------------------------
        password = attrs.get('password')
        if password:
            # Les validateurs Django comparent le mot de passe à l'identité :
            # on fournit donc un utilisateur candidat pour une création.
            candidate = instance or User(
                username=attrs.get('username', ''),
                email=attrs.get('email', ''),
            )
            try:
                password_validation.validate_password(password, user=candidate)
            except DjangoValidationError as error:
                raise serializers.ValidationError({'password': error.messages}) from error
        elif instance is None:
            raise serializers.ValidationError({'password': 'Le mot de passe du nouveau compte est obligatoire.'})

        return attrs

    def get_student_profile(self, user):
        """
        Retourne un résumé de la fiche étudiante liée au compte.

        Retour :
            dict (id, numéro, nom complet, e-mail) ou None si aucune liaison.
        """
        try:
            student = user.student_account.student
        except AttributeError:
            return None
        return {
            'id': student.id,
            'student_number': student.student_number,
            'full_name': student.full_name,
            'email': student.email,
        }

    def get_jury_profile(self, user):
        """
        Retourne un résumé du membre de jury lié au compte.

        Retour :
            dict (id, nom, id et nom du jury) ou None si aucune liaison.
        """
        try:
            member = user.jury_member_account.jury_member
        except AttributeError:
            return None
        return {
            'id': member.id,
            'name': member.member_name,
            'jury_id': member.jury_id,
            'jury_name': member.jury.name,
        }

    @transaction.atomic
    def create(self, validated_data):
        """
        Crée le compte, son groupe de rôle et sa liaison métier éventuelle.

        L'ensemble est atomique : en cas d'erreur, aucun compte partiel ne
        subsiste.

        Retour :
            User : le compte créé.
        """
        role = validated_data.pop('role')
        student = validated_data.pop('student', None)
        jury_member = validated_data.pop('jury_member', None)
        password = validated_data.pop('password')
        # Le groupe SGSUS contrôle les droits API ; is_staff autorise séparément
        # l'accès au site d'administration Django, sans accorder is_superuser.
        user = User.objects.create_user(
            password=password,
            is_staff=role == 'admin',
            **validated_data,
        )
        self._assign_role(user, role)
        if role == 'student':
            StudentAccount.objects.create(user=user, student=student)
        elif role == 'jury':
            JuryMemberAccount.objects.create(user=user, jury_member=jury_member)
        return user

    @transaction.atomic
    def update(self, instance, validated_data):
        """
        Met à jour le compte et resynchronise rôle et liaisons métier.

        Les liaisons devenues incohérentes avec le nouveau rôle sont
        supprimées (ex. un ancien étudiant devenu encadreur).

        Retour :
            User : le compte modifié.
        """
        role = validated_data.pop('role', get_user_role(instance))
        student = validated_data.pop('student', None)
        jury_member = validated_data.pop('jury_member', None)
        password = validated_data.pop('password', None)

        # Champs simples (username, e-mail, nom, activation…).
        for field, value in validated_data.items():
            setattr(instance, field, value)
        if password:
            # `set_password` hache le mot de passe avant enregistrement.
            instance.set_password(password)
        instance.is_staff = (role == 'admin')
        instance.save()

        # Synchronisation de la liaison étudiante.
        if role == 'student':
            StudentAccount.objects.update_or_create(
                user=instance,
                defaults={'student': student or instance.student_account.student},
            )
        else:
            StudentAccount.objects.filter(user=instance).delete()
        # Synchronisation de la liaison jury.
        if role == 'jury':
            if jury_member is None:
                jury_member = instance.jury_member_account.jury_member
            JuryMemberAccount.objects.update_or_create(
                user=instance,
                defaults={'jury_member': jury_member},
            )
        else:
            JuryMemberAccount.objects.filter(user=instance).delete()
        self._assign_role(instance, role)
        return instance

    @staticmethod
    def _assign_role(user, role):
        """
        Remplace le groupe de rôle SGSUS de l'utilisateur.

        Paramètres :
            user : compte à modifier.
            role (str) : nouveau rôle, nom d'un groupe de ROLE_GROUPS.

        Les autres groupes Django (hors rôles SGSUS) ne sont pas touchés.
        """
        groups = Group.objects.filter(name__in=ROLE_GROUPS)
        user.groups.remove(*groups)
        group, _ = Group.objects.get_or_create(name=role)
        user.groups.add(group)
