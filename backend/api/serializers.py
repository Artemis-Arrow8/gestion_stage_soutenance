from datetime import datetime

from django.contrib.auth import get_user_model, password_validation
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import serializers

from .models import (
    Assessment,
    Campaign,
    Defense,
    DocumentVersion,
    InternshipFolder,
    Jury,
    JuryMember,
    Review,
    Room,
    Student,
    StudentAccount,
)
from .roles import ROLE_GROUPS, get_user_role
from .services import conflicts

User = get_user_model()


# ==========================================
# 1. CHAMPS PERSONNALISÉS
# ==========================================
class DateTimeRangeSerializerField(serializers.Field):
    """Sérialise un intervalle PostgreSQL (tstzrange) en objet {start, end}."""
    default_error_messages = {
        'invalid': 'Fournissez une date de début et de fin avec fuseau horaire.',
        'order': 'La date de fin doit être postérieure à la date de début.',
    }

    def to_internal_value(self, data):
        if not isinstance(data, dict) or set(data) != {'start', 'end'}:
            self.fail('invalid')

        datetimes = []
        for key in ('start', 'end'):
            value = data[key]
            try:
                parsed = parse_datetime(value) if isinstance(value, str) else value
            except ValueError:
                parsed = None
            if not isinstance(parsed, datetime) or timezone.is_naive(parsed):
                raise serializers.ValidationError({key: self.error_messages['invalid']})
            datetimes.append(parsed)

        start, end = datetimes
        if end <= start:
            self.fail('order')
        return start, end

    def to_representation(self, value):
        if value is None:
            return None
        if isinstance(value, (tuple, list)):
            start, end = value
        else:
            start, end = value.lower, value.upper
        return {
            'start': start.isoformat(),
            'end': end.isoformat(),
        }


class AccountRoleField(serializers.ChoiceField):
    """Lit le rôle calculé d'un utilisateur et permet son attribution à l'écriture."""
    def get_attribute(self, instance):
        return get_user_role(instance)


# ==========================================
# 2. CAMPAGNE, ÉTUDIANTS ET COMPTES
# ==========================================
class CampaignSerializer(serializers.ModelSerializer):
    """Campagnes académiques."""
    class Meta:
        model = Campaign
        fields = '__all__'


class StudentSerializer(serializers.ModelSerializer):
    """Fiches étudiants."""
    class Meta:
        model = Student
        fields = '__all__'


class UserAccountSerializer(serializers.ModelSerializer):
    """Gestion complète des comptes utilisateurs, de leurs rôles et profils étudiants."""
    role = AccountRoleField(choices=ROLE_GROUPS, required=False)
    password = serializers.CharField(
        write_only=True,
        required=False,
        trim_whitespace=False,
        style={'input_type': 'password'},
    )
    student_id = serializers.PrimaryKeyRelatedField(
        source='student',
        queryset=Student.objects.all(),
        required=False,
        allow_null=True,
        write_only=True,
    )
    student_profile = serializers.SerializerMethodField()

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
        )
        read_only_fields = ('id', 'student_profile')

    def validate(self, attrs):
        instance = self.instance
        role = attrs.get('role', get_user_role(instance) if instance else None)
        student = attrs.get('student')

        if instance is None and role is None:
            raise serializers.ValidationError({'role': 'Le rôle du nouveau compte est obligatoire.'})

        if role == 'student':
            if student is None and instance is not None:
                try:
                    student = instance.student_account.student
                except AttributeError:
                    student = None
            if student is None:
                raise serializers.ValidationError(
                    {'student_id': 'Un compte étudiant doit être lié à une fiche existante.'}
                )
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

        if instance is not None:
            if instance.is_superuser and role != 'admin':
                raise serializers.ValidationError(
                    {'role': 'Le rôle d’un superutilisateur ne peut pas être modifié.'}
                )
            if instance.is_superuser and attrs.get('is_active') is False:
                raise serializers.ValidationError(
                    {'is_active': 'Un superutilisateur ne peut pas être désactivé ici.'}
                )
            request = self.context.get('request')
            if request and request.user.pk == instance.pk:
                if role != get_user_role(instance) or attrs.get('is_active') is False:
                    raise serializers.ValidationError(
                        'Vous ne pouvez pas désactiver ou rétrograder votre propre compte.'
                    )

        password = attrs.get('password')
        if password:
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

    @transaction.atomic
    def create(self, validated_data):
        role = validated_data.pop('role')
        student = validated_data.pop('student', None)
        password = validated_data.pop('password')
        user = User.objects.create_user(password=password, **validated_data)
        self._assign_role(user, role)
        if role == 'student':
            StudentAccount.objects.create(user=user, student=student)
        return user

    @transaction.atomic
    def update(self, instance, validated_data):
        role = validated_data.pop('role', get_user_role(instance))
        student = validated_data.pop('student', None)
        password = validated_data.pop('password', None)

        for field, value in validated_data.items():
            setattr(instance, field, value)
        if password:
            instance.set_password(password)
        instance.is_staff = (role == 'admin')
        instance.save()

        if role == 'student':
            StudentAccount.objects.update_or_create(
                user=instance,
                defaults={'student': student or instance.student_account.student},
            )
        else:
            StudentAccount.objects.filter(user=instance).delete()
        self._assign_role(instance, role)
        return instance

    @staticmethod
    def _assign_role(user, role):
        groups = Group.objects.filter(name__in=ROLE_GROUPS)
        user.groups.remove(*groups)
        group, _ = Group.objects.get_or_create(name=role)
        user.groups.add(group)


# ==========================================
# 3. DOSSIERS DE STAGE ET DOCUMENTS
# ==========================================
class InternshipFolderSerializer(serializers.ModelSerializer):
    """Dossiers de stage."""
    class Meta:
        model = InternshipFolder
        fields = '__all__'


class DocumentVersionSerializer(serializers.ModelSerializer):
    """Versions de rapports déposés."""
    class Meta:
        model = DocumentVersion
        fields = '__all__'
        read_only_fields = ('id', 'uploaded_at')


class ReviewSerializer(serializers.ModelSerializer):
    """Avis et validations de l'encadreur ou du tuteur."""
    class Meta:
        model = Review
        fields = '__all__'
        read_only_fields = ('id', 'author', 'created_at')


# ==========================================
# 4. SALLES, JURYS ET PLANIFICATION
# ==========================================
class SalleSerializer(serializers.ModelSerializer):
    """Catalogue des salles de soutenance."""
    class Meta:
        model = Room
        fields = ['id', 'name', 'capacity', 'is_active']

    def validate_name(self, value):
        return value.strip()

    def validate_capacity(self, value):
        if value is None or value <= 0:
            raise serializers.ValidationError("La capacité de la salle doit être strictement positive.")
        return value


class JuryMemberSerializer(serializers.ModelSerializer):
    """Membres composant un jury."""
    ROLES_VALIDES = {'president', 'rapporteur', 'examinateur'}

    class Meta:
        model = JuryMember
        fields = ['id', 'jury', 'member_name', 'role_in_jury']

    def validate_member_name(self, value):
        return value.strip()

    def validate_role_in_jury(self, value):
        role = value.strip().lower()
        if role not in self.ROLES_VALIDES:
            raise serializers.ValidationError(
                "Rôle invalide : choisir parmi 'president', 'rapporteur', 'examinateur'."
            )
        return role


class JurySerializer(serializers.ModelSerializer):
    """Jury de soutenance avec ses membres."""
    members = JuryMemberSerializer(many=True, read_only=True)

    class Meta:
        model = Jury
        fields = ['id', 'name', 'is_complete', 'members']

    def validate_name(self, value):
        return value.strip()


class DefenseSerializer(serializers.ModelSerializer):
    """Planification des soutenances avec gestion des créneaux et contrôle des conflits."""
    slot_start = serializers.DateTimeField(write_only=True)
    slot_end = serializers.DateTimeField(write_only=True)
    folder_detail = InternshipFolderSerializer(source='folder', read_only=True)
    jury_detail = JurySerializer(source='jury', read_only=True)

    class Meta:
        model = Defense
        fields = [
            'id',
            'folder',
            'folder_detail',
            'jury',
            'jury_detail',
            'room_name',
            'slot_start',
            'slot_end',
            'status',
        ]

    def validate(self, attrs):
        attrs = super().validate(attrs)
        instance = self.instance

        debut = attrs.get('slot_start') or (instance.slot_range.lower if instance else None)
        fin = attrs.get('slot_end') or (instance.slot_range.upper if instance else None)
        dossier = attrs.get('folder') or (instance.folder if instance else None)
        jury = attrs.get('jury') or (instance.jury if instance else None)
        room_name = (attrs.get('room_name') or (instance.room_name if instance else '') or '').strip()

        slot = conflicts.construire_creneau(debut, fin)

        if not room_name:
            raise serializers.ValidationError({'room_name': 'La salle est obligatoire.'})
        attrs['room_name'] = room_name
        if dossier is None:
            raise serializers.ValidationError({'folder': 'Le dossier de stage est obligatoire.'})
        if jury is None:
            raise serializers.ValidationError({'jury': 'Le jury est obligatoire pour planifier une soutenance.'})

        defense_exclue_id = instance.pk if instance else None
        conflicts.verifier_toutes_regles(
            dossier.pk, jury.pk, room_name, slot,
            defense_exclue_id=defense_exclue_id,
        )

        attrs.pop('slot_start', None)
        attrs.pop('slot_end', None)
        attrs['slot_range'] = slot
        return attrs

    def create(self, validated_data):
        slot_range = validated_data.pop('slot_range')
        return Defense.objects.create(slot_range=slot_range, **validated_data)

    def update(self, instance, validated_data):
        slot_range = validated_data.pop('slot_range', None)
        if slot_range is not None:
            instance.slot_range = slot_range
        return super().update(instance, validated_data)

    def to_representation(self, instance):
        data = super().to_representation(instance)
        slot = instance.slot_range
        if slot is not None:
            data['slot_start'] = slot.lower.isoformat() if slot.lower else None
            data['slot_end'] = slot.upper.isoformat() if slot.upper else None
        return data


# ==========================================
# 5. ÉVALUATIONS ET NOTES
# ==========================================
class AssessmentSerializer(serializers.ModelSerializer):
    """Notes et validation finale de la soutenance."""
    class Meta:
        model = Assessment
        fields = '__all__'