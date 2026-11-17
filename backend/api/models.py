"""
Modèles de données de SGSUS (gestion des stages et des soutenances).

Chaque classe correspond à une table PostgreSQL. Deux familles coexistent :

* Tables « historiques » (`managed = False`) : créées par le script SQL du
  projet (`database/schema.sql`). Django les lit et les écrit, mais ne les
  crée ni ne les modifie par ses migrations.
* Tables gérées par Django (sans `managed = False`) : tables de liaison entre
  les comptes et les données métier (StudentAccount, FolderSupervisor,
  JuryMemberAccount) et les avis (Review).

Vue d'ensemble des relations :

    Campaign ──< InternshipFolder >── Student ──1:1── StudentAccount ── User
                       │
                       ├──< DocumentVersion ──< Review
                       ├──< FolderSupervisor >── User (encadreur)
                       └──< Defense >── Jury ──< JuryMember ──1:1── JuryMemberAccount ── User
                                 └──< Assessment (notes)
"""

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
    """
    Campagne académique (une année universitaire de stages).

    Les dossiers de stage sont rattachés à une campagne ; en principe, une
    seule campagne est active à la fois.
    """

    # Année universitaire, ex. « 2026-2027 ».
    academic_year = models.CharField(max_length=50)
    # Campagne en cours (les nouveaux dossiers s'y rattachent).
    is_active = models.BooleanField(default=True)
    # Date de création, renseignée automatiquement.
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        # Table créée par database/schema.sql, pas par les migrations.
        managed = False
        db_table = 'campaign'

    def __str__(self):
        """Libellé lisible, utilisé notamment par l'administration Django."""
        return f"Campagne {self.academic_year}"


# ==========================================
# 2. ÉTUDIANT ET COMPTES
# ==========================================
class Student(models.Model):
    """Fiche d'un étudiant inscrit (distincte de son compte de connexion)."""

    # Matricule unique, ex. « ETU-2026-001 ».
    student_number = models.CharField(max_length=100, unique=True)
    # Prénom et nom.
    full_name = models.CharField(max_length=255)
    # Adresse e-mail unique.
    email = models.EmailField(unique=True)

    @property
    def is_authenticated(self):
        """Compatibilité historique : une fiche se comporte comme authentifiée."""
        return True

    @property
    def role(self):
        """Compatibilité historique : rôle implicite d'une fiche étudiante."""
        return 'student'

    class Meta:
        managed = False
        db_table = 'student'

    def __str__(self):
        """Libellé lisible : matricule et nom."""
        return f"{self.student_number} — {self.full_name}"


class StudentAccount(models.Model):
    """
    Lie un compte de connexion Django à une fiche étudiante (relation 1:1).

    C'est cette liaison qui donne à un compte le rôle « étudiant ».
    """

    # Compte de connexion (un compte ne peut être lié qu'à une fiche).
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        db_column='user_id',
        related_name='student_account',
    )
    # Fiche étudiante (une fiche ne peut être liée qu'à un compte).
    student = models.OneToOneField(
        Student,
        on_delete=models.CASCADE,
        db_column='student_id',
        related_name='student_account',
    )

    class Meta:
        db_table = 'student_account'

    def __str__(self):
        """Libellé lisible : identifiant de connexion et nom de l'étudiant."""
        return f"{self.user.username} - {self.student.full_name}"


class FolderSupervisor(models.Model):
    """
    Affecte un encadreur à un dossier de stage précis.

    Un encadreur ne voit que les dossiers qui lui sont affectés ici.
    """

    # Compte de l'encadreur.
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='folder_assignments',
    )
    # Dossier suivi.
    folder = models.ForeignKey(
        'InternshipFolder',
        on_delete=models.CASCADE,
        related_name='supervisor_assignments',
    )

    class Meta:
        db_table = 'folder_supervisor'
        constraints = [
            # Un même encadreur n'est affecté qu'une fois au même dossier.
            models.UniqueConstraint(
                fields=('user', 'folder'),
                name='unique_supervisor_folder_assignment',
            ),
        ]

    def __str__(self):
        """Libellé lisible : encadreur et numéro de dossier."""
        return f"{self.user.get_username()} - dossier #{self.folder_id}"


# ==========================================
# 3. DOSSIER DE STAGE ET DOCUMENTS
# ==========================================
class InternshipFolder(models.Model):
    """
    Dossier de stage d'un étudiant pour une campagne.

    Cycle de vie du statut : brouillon → soumis → recevable (planifiable
    en soutenance) ou rejete.
    """

    # Étudiant propriétaire du dossier.
    student = models.ForeignKey(
        Student, on_delete=models.CASCADE, db_column='student_id',
        related_name='internship_folders',
    )
    # Campagne de rattachement.
    campaign = models.ForeignKey(
        Campaign, on_delete=models.CASCADE, db_column='campaign_id',
        related_name='internship_folders',
    )
    # Entreprise d'accueil.
    company_name = models.CharField(max_length=255)
    # Sujet du stage.
    subject = models.TextField()
    # Statut du dossier (voir le cycle de vie ci-dessus).
    status = models.CharField(max_length=50, default='brouillon')
    # Date de création, renseignée automatiquement.
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'internship_folder'

    def __str__(self):
        """Libellé lisible : numéro et entreprise."""
        return f"Dossier #{self.pk} — {self.company_name}"


class DocumentVersion(models.Model):
    """
    Version déposée d'un rapport de stage (PDF).

    Chaque nouveau dépôt crée une version numérotée (1, 2, 3…) ; le fichier
    lui-même est stocké sur le disque du serveur (`file_path`).
    """

    # Dossier auquel appartient la version.
    folder = models.ForeignKey(
        InternshipFolder, on_delete=models.CASCADE, db_column='folder_id',
        related_name='document_versions',
    )
    # Numéro de version, croissant pour un même dossier.
    version_number = models.IntegerField()
    # Chemin du fichier dans le stockage (MEDIA_ROOT).
    file_path = models.CharField(max_length=255)
    # Date de dépôt, renseignée automatiquement.
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'document_version'

    def __str__(self):
        """Libellé lisible : numéro de version et dossier."""
        return f"Version {self.version_number} — dossier #{self.folder_id}"


class Review(models.Model):
    """
    Avis d'un encadreur sur une version de document.

    Un avis « favorable » sur la dernière version rend le dossier
    planifiable en soutenance (règle F03).
    """

    # Version de document évaluée.
    document_version = models.ForeignKey(
        DocumentVersion, on_delete=models.CASCADE, db_column='document_version_id',
        related_name='reviews',
    )
    # Auteur de l'avis (conservé à NULL si son compte est supprimé).
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='sgsus_reviews',
    )
    # Rôle de l'auteur au moment de l'avis (ex. « encadreur »).
    author_role = models.CharField(max_length=50)
    # Décision : « favorable » ou « defavorable ».
    decision = models.CharField(max_length=50)
    # Commentaire libre facultatif.
    comments = models.TextField(blank=True, null=True)
    # Date de l'avis, renseignée automatiquement.
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'review'

    def __str__(self):
        """Libellé lisible : décision et version concernée."""
        return f"Avis {self.decision} — version #{self.document_version_id}"


# ==========================================
# 4. SALLES, JURYS ET SOUTENANCES
# ==========================================
class Room(models.Model):
    """Salle pouvant accueillir des soutenances."""

    # Nom unique de la salle (référencé par Defense.room_name).
    name = models.CharField(max_length=100, unique=True)
    # Nombre de places.
    capacity = models.IntegerField()
    # Une salle inactive n'est plus proposée à la planification.
    is_active = models.BooleanField(default=True)

    class Meta:
        managed = False
        db_table = 'room'

    def __str__(self):
        """Libellé lisible : nom et capacité."""
        return f"Salle {self.name} ({self.capacity} places)"


class Jury(models.Model):
    """Jury de soutenance, composé de plusieurs membres."""

    # Nom du jury, ex. « Jury Informatique A ».
    name = models.CharField(max_length=100)
    # Vrai lorsque la composition est déclarée complète.
    is_complete = models.BooleanField(default=False)

    class Meta:
        managed = False
        db_table = 'jury'

    def __str__(self):
        """Libellé lisible : nom du jury."""
        return self.name


class JuryMember(models.Model):
    """Membre d'un jury (président, rapporteur ou examinateur)."""

    # Jury d'appartenance.
    jury = models.ForeignKey(
        Jury, on_delete=models.CASCADE, db_column='jury_id', related_name='members'
    )
    # Nom du membre (sert aussi à détecter qu'un membre siège deux fois).
    member_name = models.CharField(max_length=255)
    # Rôle : « president », « rapporteur » ou « examinateur ».
    role_in_jury = models.CharField(max_length=100)

    class Meta:
        managed = False
        db_table = 'jury_member'

    def __str__(self):
        """Libellé lisible : nom et rôle."""
        return f"{self.member_name} ({self.role_in_jury})"


class JuryMemberAccount(models.Model):
    """
    Lie un compte de connexion Django à un membre de jury (relation 1:1).

    C'est cette liaison qui donne à un compte le rôle « jury ».
    """

    # Compte de connexion.
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='jury_member_account',
    )
    # Membre de jury représenté par ce compte.
    jury_member = models.OneToOneField(
        JuryMember,
        on_delete=models.CASCADE,
        related_name='account',
    )

    class Meta:
        db_table = 'jury_member_account'

    def __str__(self):
        """Libellé lisible : identifiant de connexion et nom du membre."""
        return f"{self.user.get_username()} - {self.jury_member.member_name}"


class Defense(models.Model):
    """
    Soutenance planifiée : un dossier, un jury, une salle et un créneau.

    Statuts usuels : planifie, confirme, termine, annule.
    """

    # Dossier soutenu.
    folder = models.ForeignKey(
        InternshipFolder, on_delete=models.CASCADE, db_column='folder_id',
        related_name='defenses',
    )
    # Jury (conservé à NULL si le jury est supprimé).
    jury = models.ForeignKey(
        Jury, on_delete=models.SET_NULL, db_column='jury_id',
        null=True, blank=True, related_name='defenses',
    )
    # Nom de la salle (correspond à Room.name).
    room_name = models.CharField(max_length=100)
    # Créneau horaire [début ; fin[ en UTC (type PostgreSQL tstzrange).
    slot_range = DateTimeRangeField(default_bounds='[)')
    # Statut de la soutenance.
    status = models.CharField(max_length=50, default='planifie')

    class Meta:
        managed = False
        db_table = 'defense'
        constraints = [
            # EXG01 : une salle ne peut pas accueillir deux soutenances qui
            # se chevauchent (contrainte d'exclusion PostgreSQL).
            ExclusionConstraint(
                name='prevent_room_double_booking',
                expressions=[
                    ('room_name', RangeOperators.EQUAL),
                    ('slot_range', RangeOperators.OVERLAPS),
                ],
            ),
            # EXG01 : un jury ne peut pas siéger dans deux soutenances
            # qui se chevauchent.
            ExclusionConstraint(
                name='prevent_jury_double_booking',
                expressions=[
                    ('jury', RangeOperators.EQUAL),
                    ('slot_range', RangeOperators.OVERLAPS),
                ],
            ),
        ]

    def __str__(self):
        """Libellé lisible : numéro, salle et statut."""
        return f"Soutenance #{self.pk} — {self.room_name} ({self.status})"


# ==========================================
# 5. ÉVALUATIONS ET NOTES
# ==========================================
class Assessment(models.Model):
    """
    Évaluation d'une soutenance : notes sur 20 et validation finale.

    Une note validée (`is_approved`) devient visible par l'étudiant.
    """

    # Soutenance évaluée.
    defense = models.ForeignKey(
        Defense, on_delete=models.CASCADE, db_column='defense_id',
        related_name='assessments',
    )
    # Note du rapport écrit (0 à 20).
    report_grade = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    # Note de l'oral (0 à 20).
    oral_grade = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    # Moyenne finale (0 à 20), calculée par l'API si non saisie.
    final_average = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True,
        validators=[MinValueValidator(0), MaxValueValidator(20)],
    )
    # Validation de la note par le personnel.
    is_approved = models.BooleanField(default=False)

    class Meta:
        managed = False
        db_table = 'assessment'
        # Contraintes de base : chaque note est vide ou comprise entre 0 et 20.
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

    def __str__(self):
        """Libellé lisible : soutenance évaluée et moyenne."""
        return f"Évaluation soutenance #{self.defense_id} — {self.final_average}"
