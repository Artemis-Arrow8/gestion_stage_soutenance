from django.conf import settings
from django.contrib.postgres.constraints import ExclusionConstraint
from django.contrib.postgres.fields import DateTimeRangeField, RangeOperators
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import Q


# ==========================================
# 1. CAMPAGNE
# ==========================================
class Campaign(models.Model):
    """Représente une campagne académique."""
    academic_year = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'campaign'

    def __str__(self):
        return f"Campagne {self.academic_year}"


# ==========================================
# 2. ÉTUDIANT ET COMPTES
# ==========================================
class Student(models.Model):
    """Représente un étudiant inscrit dans le système."""
    student_number = models.CharField(max_length=100, unique=True)
    full_name = models.CharField(max_length=255)
    email = models.EmailField(unique=True)

    @property
    def is_authenticated(self):
        return True

    @property
    def role(self):
        return 'student'

    class Meta:
        managed = False
        db_table = 'student'

    def __str__(self):
        return f"{self.student_number} — {self.full_name}"


class StudentAccount(models.Model):
    """Lie un compte utilisateur Django à un profil étudiant."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        db_column='user_id',
        related_name='student_account',
    )
    student = models.OneToOneField(
        Student,
        on_delete=models.CASCADE,
        db_column='student_id',
        related_name='student_account',
    )

    class Meta:
        db_table = 'student_account'

    def __str__(self):
        return f"{self.user.username} - {self.student.full_name}"


class FolderSupervisor(models.Model):
    """Associe un encadreur aux seuls dossiers qu'il est autorisé à suivre."""
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='folder_assignments',
    )
    folder = models.ForeignKey(
        'InternshipFolder',
        on_delete=models.CASCADE,
        related_name='supervisor_assignments',
    )

    class Meta:
        db_table = 'folder_supervisor'
        constraints = [
            models.UniqueConstraint(
                fields=('user', 'folder'),
                name='unique_supervisor_folder_assignment',
            ),
        ]

    def __str__(self):
        return f"{self.user.get_username()} - dossier #{self.folder_id}"


# ==========================================
# 3. DOSSIER DE STAGE ET DOCUMENTS
# ==========================================
class InternshipFolder(models.Model):
    """Dossier de stage soumis par l'étudiant pour une campagne."""
    student = models.ForeignKey(
        Student, on_delete=models.CASCADE, db_column='student_id',
        related_name='internship_folders',
    )
    campaign = models.ForeignKey(
        Campaign, on_delete=models.CASCADE, db_column='campaign_id',
        related_name='internship_folders',
    )
    company_name = models.CharField(max_length=255)
    subject = models.TextField()
    status = models.CharField(max_length=50, default='brouillon')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'internship_folder'

    def __str__(self):
        return f"Dossier #{self.pk} — {self.company_name}"


class DocumentVersion(models.Model):
    """Versions successives des rapports de stage."""
    folder = models.ForeignKey(
        InternshipFolder, on_delete=models.CASCADE, db_column='folder_id',
        related_name='document_versions',
    )
    version_number = models.IntegerField()
    file_path = models.CharField(max_length=255)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'document_version'


class Review(models.Model):
    """Avis et validations de l'encadreur ou du tuteur sur un document."""
    document_version = models.ForeignKey(
        DocumentVersion, on_delete=models.CASCADE, db_column='document_version_id',
        related_name='reviews',
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='sgsus_reviews',
    )
    author_role = models.CharField(max_length=50)
    decision = models.CharField(max_length=50)
    comments = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'review'


# ==========================================
# 4. SALLES, JURYS ET SOUTENANCES
# ==========================================
class Room(models.Model):
    """Catalogue des salles de soutenance (Ajout Tâche 4)."""
    name = models.CharField(max_length=100, unique=True)
    capacity = models.IntegerField()
    is_active = models.BooleanField(default=True)

    class Meta:
        managed = False
        db_table = 'room'

    def __str__(self):
        return f"Salle {self.name} ({self.capacity} places)"


class Jury(models.Model):
    """Groupe de jury constitué pour les soutenances."""
    name = models.CharField(max_length=100)
    is_complete = models.BooleanField(default=False)

    class Meta:
        managed = False
        db_table = 'jury'

    def __str__(self):
        return self.name


class JuryMember(models.Model):
    """Membres composant un jury."""
    jury = models.ForeignKey(
        Jury, on_delete=models.CASCADE, db_column='jury_id', related_name='members'
    )
    member_name = models.CharField(max_length=255)
    role_in_jury = models.CharField(max_length=100)

    class Meta:
        managed = False
        db_table = 'jury_member'

    def __str__(self):
        return f"{self.member_name} ({self.role_in_jury})"


class JuryMemberAccount(models.Model):
    """Lie un compte Django à un membre précis du jury."""
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='jury_member_account',
    )
    jury_member = models.OneToOneField(
        JuryMember,
        on_delete=models.CASCADE,
        related_name='account',
    )

    class Meta:
        db_table = 'jury_member_account'

    def __str__(self):
        return f"{self.user.get_username()} - {self.jury_member.member_name}"


class Defense(models.Model):
    """Planification des soutenances avec gestion des créneaux horaires."""
    folder = models.ForeignKey(
        InternshipFolder, on_delete=models.CASCADE, db_column='folder_id',
        related_name='defenses',
    )
    jury = models.ForeignKey(
        Jury, on_delete=models.SET_NULL, db_column='jury_id',
        null=True, blank=True, related_name='defenses',
    )
    room_name = models.CharField(max_length=100)
    slot_range = DateTimeRangeField(default_bounds='[)')
    status = models.CharField(max_length=50, default='planifie')

    class Meta:
        managed = False
        db_table = 'defense'
        constraints = [
            ExclusionConstraint(
                name='prevent_room_double_booking',
                expressions=[
                    ('room_name', RangeOperators.EQUAL),
                    ('slot_range', RangeOperators.OVERLAPS),
                ],
            ),
            ExclusionConstraint(
                name='prevent_jury_double_booking',
                expressions=[
                    ('jury', RangeOperators.EQUAL),
                    ('slot_range', RangeOperators.OVERLAPS),
                ],
            ),
        ]


# ==========================================
# 5. ÉVALUATIONS ET NOTES
# ==========================================
class Assessment(models.Model):
    """Notes et validation finale de la soutenance."""
    defense = models.ForeignKey(
        Defense, on_delete=models.CASCADE, db_column='defense_id',
        related_name='assessments',
    )
    report_grade = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    oral_grade = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    final_average = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    is_approved = models.BooleanField(default=False)

    class Meta:
        managed = False
        db_table = 'assessment'
        constraints = [
            models.CheckConstraint(
                condition=Q(report_grade__isnull=True) | Q(report_grade__gte=0, report_grade__lte=20),
                name='assessment_report_grade_0_20',
            ),
            models.CheckConstraint(
                condition=Q(oral_grade__isnull=True) | Q(oral_grade__gte=0, oral_grade__lte=20),
                name='assessment_oral_grade_0_20',
            ),
            models.CheckConstraint(
                condition=Q(final_average__isnull=True) | Q(final_average__gte=0, final_average__lte=20),
                name='assessment_final_average_0_20',
            ),
        ]