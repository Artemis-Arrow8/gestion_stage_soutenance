from django.db import models

# Modele representant les campagnes de stage et de soutenance
class Campaign(models.Model):
    name = models.CharField(max_length=255)         # Nom de la campagne
    academic_year = models.CharField(max_length=50) # Annee academique (ex: 2025-2026)
    is_active = models.BooleanField(default=True)   # Statut actif ou inactif
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False          # Django ne gere pas la creation/modification de cette table via migrate
        db_table = 'campaigns'   # Nom exact de la table dans PostgreSQL

# Modele representant les utilisateurs de l'application (etudiants, encadreurs, jurys, etc.)
class User(models.Model):
    username = models.CharField(max_length=150, unique=True)
    email = models.EmailField(unique=True)
    password = models.CharField(max_length=128)
    role = models.CharField(max_length=50)        # Role attribue (etudiant, encadreur, admin...)
    first_name = models.CharField(max_length=150, blank=True, null=True)
    last_name = models.CharField(max_length=150, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'users'

# Modele representant les etudiants (lie a un utilisateur et a une campagne)
class Student(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)         # Lien vers le compte utilisateur
    campaign = models.ForeignKey(Campaign, on_delete=models.CASCADE) # Lien vers la campagne en cours
    student_id_number = models.CharField(max_length=100, unique=True)# Numero de carte d'etudiant
    major = models.CharField(max_length=150)                         # Filiere ou departement
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'students'

# Modele representant les dossiers de stage des etudiants
class Internship(models.Model):
    student = models.ForeignKey(Student, on_delete=models.CASCADE)   # Etudiant concerne par le stage
    company_name = models.CharField(max_length=255)                  # Nom de l'entreprise d'accueil
    company_tutor_name = models.CharField(max_length=255, blank=True, null=True)  # Nom du tuteur pro
    company_tutor_email = models.EmailField(blank=True, null=True)   # Email du tuteur pro
    project_subject = models.TextField()                             # Sujet ou theme du stage
    status = models.CharField(max_length=50, default='draft')        # Statut du dossier (brouillon, valide...)
    supervisor = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True) # Encadreur pedagogique assigne
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'internships'

# Modele representant la planification des soutenances
class Defense(models.Model):
    internship = models.ForeignKey(Internship, on_delete=models.CASCADE) # Stage associe a la soutenance
    room_name = models.CharField(max_length=100)                         # Salle attribuee
    status = models.CharField(max_length=50, default='proposed')         # Statut de la planification
    schedule_version = models.IntegerField(default=1)                    # Numero de version du planning
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = 'defenses'