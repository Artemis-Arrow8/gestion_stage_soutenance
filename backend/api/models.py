"""
Modèles Django du projet SGSUS (Gestion des stages et des soutenances).

IMPORTANT — Harmonisation avec la base de données :
Tous les modèles sont `managed = False` : la structure des tables est définie
par `database/schema.sql` (source de vérité du groupe). Django ne crée donc
aucune table et aucune migration n'est nécessaire pour ces modèles.

Noms de tables conformes à schema.sql :
    campaign, student, internship_folder, document_version, review,
    jury, jury_member, defense, assessment.

La table `room` (salles) est un ajout de la Tâche 4 (module planification),
défini de manière additive dans database/schema.sql.
"""

from django.db import models
from django.contrib.postgres.fields import DateTimeRangeField


# 1. Table campaign
class Campaign(models.Model):
    academic_year = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'campaign'

    def __str__(self):
        return f"Campagne {self.academic_year}"


# 2. Table users — NON DÉFINIE dans schema.sql v1.
#    Cette table sera créée par le module authentification/comptes (Tâche 1).
#    Modèle conservé à titre de contrat pour ce module ; ne pas interroger
#    tant que la table n'existe pas.
class User(models.Model):
    username = models.CharField(max_length=150, unique=True)
    email = models.EmailField(unique=True)
    password = models.CharField(max_length=128)
    role = models.CharField(max_length=50)
    first_name = models.CharField(max_length=150, blank=True, null=True)
    last_name = models.CharField(max_length=150, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'users'


# 3. Table student
class Student(models.Model):
    student_number = models.CharField(max_length=100, unique=True)
    full_name = models.CharField(max_length=255)
    email = models.EmailField(unique=True)

    class Meta:
        managed = False
        db_table = 'student'

    def __str__(self):
        return f"{self.student_number} — {self.full_name}"


# 4. Table internship_folder (Dossier de stage)
class InternshipFolder(models.Model):
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


# 5. Table document_version (Versions de documents / rapports)
class DocumentVersion(models.Model):
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


# 6. Table review (Avis de l'encadreur / du tuteur)
class Review(models.Model):
    document_version = models.ForeignKey(
        DocumentVersion, on_delete=models.CASCADE, db_column='document_version_id',
        related_name='reviews',
    )
    author_role = models.CharField(max_length=50)      # 'encadreur' ou 'tuteur'
    decision = models.CharField(max_length=50)         # 'favorable' ou 'defavorable'
    comments = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'review'


# 7. Table room (Salles) — ajout Tâche 4 (module planification).
#    Voir database/schema.sql (bloc "Table room").
class Room(models.Model):
    name = models.CharField(max_length=100, unique=True)
    capacity = models.IntegerField()
    is_active = models.BooleanField(default=True)

    class Meta:
        managed = False
        db_table = 'room'

    def __str__(self):
        return f"Salle {self.name} ({self.capacity} places)"


# 8. Table jury
class Jury(models.Model):
    name = models.CharField(max_length=100)
    is_complete = models.BooleanField(default=False)

    class Meta:
        managed = False
        db_table = 'jury'

    def __str__(self):
        return self.name


# 9. Table jury_member (Membres d'un jury)
class JuryMember(models.Model):
    jury = models.ForeignKey(
        Jury, on_delete=models.CASCADE, db_column='jury_id', related_name='members'
    )
    member_name = models.CharField(max_length=255)
    role_in_jury = models.CharField(max_length=100)  # 'president', 'rapporteur', 'examinateur'

    class Meta:
        managed = False
        db_table = 'jury_member'

    def __str__(self):
        return f"{self.member_name} ({self.role_in_jury})"


# 10. Table defense (Soutenances planifiées)
#     - slot_range : tstzrange PostgreSQL (intervalle [début, fin) en UTC).
#     - Les contraintes d'exclusion EXG01 (prevent_room_double_booking et
#       prevent_jury_double_booking) sont définies côté PostgreSQL.
class Defense(models.Model):
    folder = models.ForeignKey(
        InternshipFolder, on_delete=models.CASCADE, db_column='folder_id',
        related_name='defenses',
    )
    jury = models.ForeignKey(
        Jury, on_delete=models.SET_NULL, db_column='jury_id',
        null=True, blank=True, related_name='defenses',
    )
    room_name = models.CharField(max_length=100)
    slot_range = DateTimeRangeField()
    status = models.CharField(max_length=50, default='planifie')

    class Meta:
        managed = False
        db_table = 'defense'

    def __str__(self):
        return f"Soutenance #{self.pk} — {self.room_name} — {self.slot_range}"


# 11. Table assessment (Évaluations et notes)
class Assessment(models.Model):
    defense = models.ForeignKey(
        Defense, on_delete=models.CASCADE, db_column='defense_id',
        related_name='assessments',
    )
    report_grade = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    oral_grade = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    final_average = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    is_approved = models.BooleanField(default=False)

    class Meta:
        managed = False
        db_table = 'assessment'


# 12. Tables NON DÉFINIES dans schema.sql v1 (réservées aux autres lots) :
#     - availabilities : indisponibilités des salles/membres (Tâche 1/4).
#     - minutes_versions : procès-verbaux officiels (évaluations/PV).
class Availability(models.Model):
    user = models.ForeignKey(
        User, on_delete=models.CASCADE, null=True, blank=True, related_name='availabilities'
    )
    resource_name = models.CharField(max_length=150, blank=True, null=True)
    time_slot = models.TextField()  # géré textuellement tant que la table n'est pas figée
    reason = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'availabilities'


class MinutesVersion(models.Model):
    campaign = models.ForeignKey(
        Campaign, on_delete=models.CASCADE, null=True, blank=True, related_name='minutes_versions'
    )
    version_number = models.IntegerField(default=1)
    signed_document_path = models.TextField(blank=True, null=True)
    is_official = models.BooleanField(default=False)
    approved_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True, related_name='approved_minutes'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'minutes_versions'
