from django.conf import settings
from django.contrib.postgres.constraints import ExclusionConstraint
from django.contrib.postgres.fields import DateTimeRangeField, RangeOperators
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import Q

# ==========================================
# 1. TABLE CAMPAGNE (Campaign)
# ==========================================
class Campaign(models.Model):
    name = models.CharField(max_length=255, blank=True, null=True)
    academic_year = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'campaign'


# ==========================================
# 2. TABLE ÉTUDIANT (Student)
# ==========================================
class Student(models.Model):
    """
    Représente un étudiant inscrit dans le système.
    Correspond à la table 'student' en base de données.
    """
    student_number = models.CharField(max_length=100, unique=True)
    full_name = models.CharField(max_length=255)
    email = models.CharField(max_length=255, unique=True)

    @property
    def is_authenticated(self):
        """Propriété requise par DRF pour valider l'authentification de l'étudiant[cite: 32]."""
        return True

    @property
    def role(self):
        """Définit automatiquement le rôle 'student' pour le système de permissions[cite: 32]."""
        return 'student'

    class Meta:
        db_table = 'student'


class StudentAccount(models.Model):
    """Lie un compte Django provisionné à un étudiant déjà enregistré."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='student_account',
    )
    student = models.OneToOneField(
        Student,
        on_delete=models.CASCADE,
        related_name='account',
    )

    class Meta:
        db_table = 'student_account'

    def __str__(self):
        return f'{self.user.username} - {self.student.student_number}'


# ==========================================
# 3. TABLE DOSSIER DE STAGE (InternshipFolder)
# ==========================================
class InternshipFolder(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, db_column='student_id')
    campaign = models.ForeignKey(Campaign, on_delete=models.CASCADE, db_column='campaign_id')
    company_name = models.CharField(max_length=255)
    subject = models.TextField()
    status = models.CharField(max_length=50, default='brouillon')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'internship_folder'


# ==========================================
# 4. TABLE VERSION DE DOCUMENT (DocumentVersion)
# ==========================================
class DocumentVersion(models.Model):
    folder = models.ForeignKey(InternshipFolder, on_delete=models.CASCADE, db_column='folder_id')
    version_number = models.IntegerField()
    file_path = models.CharField(max_length=255)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'document_version'


# ==========================================
# 5. TABLE AVIS (Review)
# ==========================================
class Review(models.Model):
    document_version = models.ForeignKey(DocumentVersion, on_delete=models.CASCADE, db_column='document_version_id')
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
# 6. TABLE JURY (Jury)
# ==========================================
class Jury(models.Model):
    name = models.CharField(max_length=100)
    is_complete = models.BooleanField(default=False)

    class Meta:
        db_table = 'jury'


# ==========================================
# 7. TABLE MEMBRE DU JURY (JuryMember)
# ==========================================
class JuryMember(models.Model):
    jury = models.ForeignKey(Jury, on_delete=models.CASCADE, db_column='jury_id')
    member_name = models.CharField(max_length=255)
    role_in_jury = models.CharField(max_length=100)

    class Meta:
        db_table = 'jury_member'


# ==========================================
# 8. TABLE SOUTENANCE (Defense)
# ==========================================
class Defense(models.Model):
    folder = models.ForeignKey(InternshipFolder, on_delete=models.CASCADE, db_column='folder_id')
    jury = models.ForeignKey(Jury, on_delete=models.SET_NULL, null=True, blank=True, db_column='jury_id')
    room_name = models.CharField(max_length=100)
    slot_range = DateTimeRangeField(default_bounds='[)')
    status = models.CharField(max_length=50, default='planifie')

    class Meta:
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
# 9. TABLE ÉVALUATION ET NOTES (Assessment)
# ==========================================
class Assessment(models.Model):
    defense = models.ForeignKey(Defense, on_delete=models.CASCADE, db_column='defense_id')
    report_grade = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    oral_grade = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    final_average = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    is_approved = models.BooleanField(default=False)

    class Meta:
        db_table = 'assessment'
        constraints = [
            models.CheckConstraint(
                condition=Q(report_grade__isnull=True)
                | Q(report_grade__gte=0, report_grade__lte=20),
                name='assessment_report_grade_0_20',
            ),
            models.CheckConstraint(
                condition=Q(oral_grade__isnull=True)
                | Q(oral_grade__gte=0, oral_grade__lte=20),
                name='assessment_oral_grade_0_20',
            ),
            models.CheckConstraint(
                condition=Q(final_average__isnull=True)
                | Q(final_average__gte=0, final_average__lte=20),
                name='assessment_final_average_0_20',
            ),
        ]