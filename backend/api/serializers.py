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
    Student,
    StudentAccount,
)
from .roles import ROLE_GROUPS, get_user_role


User = get_user_model()


class DateTimeRangeSerializerField(serializers.Field):
    default_error_messages = {
        'invalid': 'Provide a start and end datetime with timezone offsets.',
        'order': 'The end datetime must be later than the start datetime.',
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
                raise serializers.ValidationError(
                    {key: self.error_messages['invalid']}
                )
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


class CampaignSerializer(serializers.ModelSerializer):
    class Meta:
        model = Campaign
        fields = '__all__'

class StudentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Student
        fields = '__all__'

class InternshipFolderSerializer(serializers.ModelSerializer):
    class Meta:
        model = InternshipFolder
        fields = '__all__'

class DocumentVersionSerializer(serializers.ModelSerializer):
    class Meta:
        model = DocumentVersion
        fields = '__all__'

class ReviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = Review
        fields = '__all__'
        read_only_fields = ('author',)

class JurySerializer(serializers.ModelSerializer):
    class Meta:
        model = Jury
        fields = '__all__'

class JuryMemberSerializer(serializers.ModelSerializer):
    class Meta:
        model = JuryMember
        fields = '__all__'

class DefenseSerializer(serializers.ModelSerializer):
    slot_range = DateTimeRangeSerializerField()

    class Meta:
        model = Defense
        fields = '__all__'

    def validate(self, attrs):
        defense = self.instance
        slot_range = attrs.get('slot_range', defense.slot_range if defense else None)
        room_name = attrs.get('room_name', defense.room_name if defense else None)
        jury = attrs.get('jury', defense.jury if defense else None)

        if slot_range is None:
            return attrs

        conflicts = Defense.objects.filter(slot_range__overlap=slot_range)
        if defense:
            conflicts = conflicts.exclude(pk=defense.pk)

        errors = {}
        if room_name and conflicts.filter(room_name=room_name).exists():
            errors['room_name'] = 'This room is already booked during this time.'
        if jury and conflicts.filter(jury=jury).exists():
            errors['jury'] = 'This jury is already booked during this time.'
        if errors:
            raise serializers.ValidationError(errors)
        return attrs


class AssessmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Assessment
        fields = '__all__'


class AccountRoleField(serializers.ChoiceField):
    """Lit le rôle calculé tout en acceptant sa valeur à l’écriture."""

    def get_attribute(self, instance):
        return get_user_role(instance)


class UserAccountSerializer(serializers.ModelSerializer):
    """Crée et met à jour les comptes sans jamais exposer leur mot de passe."""

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
        """Vérifie la cohérence du rôle, du mot de passe et du profil lié."""
        instance = self.instance
        role = attrs.get('role', get_user_role(instance) if instance else None)
        student = attrs.get('student')

        if instance is None and role is None:
            raise serializers.ValidationError(
                {'role': 'Le rôle du nouveau compte est obligatoire.'}
            )
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
                raise serializers.ValidationError(
                    {'password': error.messages}
                ) from error
        elif instance is None:
            raise serializers.ValidationError(
                {'password': 'Le mot de passe du nouveau compte est obligatoire.'}
            )

        return attrs

    def get_student_profile(self, user):
        """Retourne les données minimales du profil étudiant associé."""
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
        """Crée le compte, son rôle et, si nécessaire, son lien étudiant."""
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
        """Met à jour les champs autorisés et synchronise rôle et profil."""
        role = validated_data.pop('role', get_user_role(instance))
        student = validated_data.pop('student', None)
        password = validated_data.pop('password', None)

        for field, value in validated_data.items():
            setattr(instance, field, value)
        if password:
            instance.set_password(password)
        if role == 'admin':
            instance.is_staff = True
        else:
            instance.is_staff = False
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
        """Remplace les groupes de rôle connus par le rôle demandé."""
        groups = Group.objects.filter(name__in=ROLE_GROUPS)
        user.groups.remove(*groups)
        group, _ = Group.objects.get_or_create(name=role)
        user.groups.add(group)