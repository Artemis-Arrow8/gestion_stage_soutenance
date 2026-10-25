from django.db import models

# 1. Table des Campagnes
class Campaign(models.Model):
    name = models.CharField(max_length=255)
    academic_year = models.CharField(max_length=50)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'campaigns'

# 2. Table des Utilisateurs / Rôles
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

# 3. Table des Étudiants
class Student(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    campaign = models.ForeignKey(Campaign, on_delete=models.CASCADE)
    student_id_number = models.CharField(max_length=100, unique=True)
    major = models.CharField(max_length=150)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'students'

# 4. Table des Dossiers de Stage
class Internship(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE)
    company_name = models.CharField(max_length=255)
    company_tutor_name = models.CharField(max_length=255, blank=True, null=True)
    company_tutor_email = models.EmailField(blank=True, null=True)
    project_subject = models.TextField()
    status = models.CharField(max_length=50, default='draft')
    supervisor = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'internships'

# 5. Table des Versions de Documents
class DocumentVersion(models.Model):
    internship = models.ForeignKey(Internship, on_delete=models.CASCADE)
    document_type = models.CharField(max_length=100)
    version_number = models.IntegerField(default=1)
    file_path = models.TextField()
    is_confidential = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'document_versions'

# 6. Table des Avis (Encadreur & Tuteur)
class Review(models.Model):
    internship = models.ForeignKey(Internship, on_delete=models.CASCADE)
    document_version = models.ForeignKey(DocumentVersion, on_delete=models.CASCADE)
    author = models.ForeignKey(User, on_delete=models.CASCADE)
    opinion = models.CharField(max_length=50)
    comment = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'reviews'

# 7. Table des Indisponibilités
class Availability(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, null=True, blank=True)
    resource_name = models.CharField(max_length=150, blank=True, null=True)
    time_slot = models.TextField()  # Géré textuellement ou via des extensions spécifiques si besoin
    reason = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'availabilities'

# 8. Table des Jurys
class Jury(models.Model):
    campaign = models.ForeignKey(Campaign, on_delete=models.CASCADE)
    name = models.CharField(max_length=150)
    president = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='presided_juries')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = 'juries'

# 9. Association Membres du Jury
class JuryMember(models.Model):
    jury = models.ForeignKey(Jury, on_delete=models.CASCADE)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    role_in_jury = models.CharField(max_length=100, default='member')

    class Meta:
        managed = False
        db_table = 'jury_members'

# 10. Table des Soutenances et Planification
class Defense(models.Model):
    internship = models.ForeignKey(Internship, on_delete=models.CASCADE)
    jury = models.ForeignKey(Jury, on_delete=models.CASCADE, null=True, blank=True)
    room_name = models.CharField(max_length=100)
    defense_interval = models.TextField() # Correspond au tstzrange du SQL
    status = models.CharField(max_length=50, default='proposed')
    schedule_version = models.IntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table ='defenses'

# 11. Table des Évaluations et Notes
class Assessment(models.Model):
    defense = models.ForeignKey(Defense, on_delete=models.CASCADE)
    evaluator = models.ForeignKey(User, on_delete=models.CASCADE)
    report_grade = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    oral_grade = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    final_grade = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    status = models.CharField(max_length=50, default='draft')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'assessments'

# 12. Table des Procès-Verbaux (PV)
class MinutesVersion(models.Model):
    campaign = models.ForeignKey(Campaign, on_delete=models.CASCADE)
    version_number = models.IntegerField(default=1)
    signed_document_path = models.TextField(blank=True, null=True)
    is_official = models.BooleanField(default=False)
    approved_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

class Meta:
    managed = False      
    db_table = 'minutes_versions'