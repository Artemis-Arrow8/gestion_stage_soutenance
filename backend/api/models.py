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
                                 ├──< Assessment (notes) ──< ProcesVerbal >── GrilleEvaluation
                                 └──< Convocation >── VersionPlanning

Tables ajoutées pour le socle du dossier ALM (gérées par Django) :
HistoriqueDossier, ConfidentialiteDossier, HabilitationDossier,
JournalAccesDocument, GrilleEvaluation, ProcesVerbal, VersionPlanning,
Convocation, Indisponibilite, ExceptionIndisponibilite, CleIdempotence.
"""

from decimal import Decimal

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

    Cycle de vie du statut (chapitre 4, voir api/services/dossiers.py) :
    brouillon → soumis → a_corriger ou valide → recevable (planifiable en
    soutenance) ; rejete après un refus motivé ; « rouvrir » ramène un
    dossier refusé à l'état soumis. Le statut ne change QUE par ces
    transitions, jamais par une modification directe.
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

    Cycle de vie (chapitre 4, voir api/services/publication.py) :
    planifie (proposée) → confirme → publie → termine (tenue), avec
    reporte (créneau modifié après publication, à republier) et annule.
    Une soutenance annulée libère sa salle et son jury.
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
            # EXG01 : une salle ne peut pas accueillir deux soutenances
            # ACTIVES qui se chevauchent (contrainte d'exclusion PostgreSQL ;
            # une soutenance annulée ne réserve plus rien).
            ExclusionConstraint(
                name='prevent_room_double_booking',
                expressions=[
                    ('room_name', RangeOperators.EQUAL),
                    ('slot_range', RangeOperators.OVERLAPS),
                ],
                condition=~Q(status='annule'),
            ),
            # EXG01 : un jury ne peut pas siéger dans deux soutenances
            # actives qui se chevauchent.
            ExclusionConstraint(
                name='prevent_jury_double_booking',
                expressions=[
                    ('jury', RangeOperators.EQUAL),
                    ('slot_range', RangeOperators.OVERLAPS),
                ],
                condition=~Q(status='annule'),
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


# ==========================================
# 6. HISTORIQUE DES DOSSIERS (F02/F03 : transitions tracées)
# ==========================================
class HistoriqueDossier(models.Model):
    """
    Trace d'une transition de dossier (« la preuve conservée », chapitre 4).

    Chaque événement (soumettre, demander une correction, valider, autoriser
    la soutenance, refuser, rouvrir, déposer une nouvelle version) enregistre
    l'état de départ, l'état atteint, l'acteur, le motif éventuel et la
    version du document examinée. Les lignes ne sont jamais modifiées.
    """

    # Dossier concerné ; PROTECT : un historique validé ne disparaît pas
    # par une suppression en cascade (chapitre 4).
    dossier = models.ForeignKey(
        InternshipFolder, on_delete=models.PROTECT, related_name='historique',
    )
    # Nom stable de l'événement (voir api/services/dossiers.py).
    evenement = models.CharField(max_length=50)
    # Statut avant et après la transition.
    statut_avant = models.CharField(max_length=50)
    statut_apres = models.CharField(max_length=50)
    # Auteur de la transition (conservé à NULL si son compte disparaît).
    acteur = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='+',
    )
    # Motif (obligatoire pour une demande de correction ou un refus).
    motif = models.TextField(blank=True, default='')
    # Version du rapport sur laquelle porte la décision.
    version_document = models.ForeignKey(
        DocumentVersion, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='+',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'historique_dossier'
        ordering = ['created_at', 'pk']

    def __str__(self):
        """Libellé lisible : dossier, événement et statuts."""
        return (f"Dossier #{self.dossier_id} : {self.evenement} "
                f"({self.statut_avant} → {self.statut_apres})")


class ConfidentialiteDossier(models.Model):
    """
    Niveau de confidentialité des rapports d'un dossier (complément F02).

    S'applique à TOUTES les versions du rapport du dossier, anciennes
    comprises. Un dossier « confidentiel » n'est consultable que par
    l'étudiant, ses encadreurs affectés et les personnes disposant d'une
    habilitation valide : ni le jury, ni la scolarité, ni l'administration
    n'y accèdent automatiquement. L'embargo est une restriction de DIFFUSION
    dans le temps : sa fin ne rend rien public (`diffusion_autorisee` reste
    une décision explicite).
    """

    NIVEAUX = (('standard', 'Standard'), ('confidentiel', 'Confidentiel'))

    dossier = models.OneToOneField(
        InternshipFolder, on_delete=models.CASCADE, related_name='confidentialite',
    )
    niveau = models.CharField(max_length=20, choices=NIVEAUX, default='standard')
    # Origine de la restriction (ex. « clause de l'entreprise d'accueil »).
    origine = models.CharField(max_length=255, blank=True, default='')
    # Fin de l'embargo de diffusion (aucun effet automatique).
    embargo_jusqu_au = models.DateField(null=True, blank=True)
    # Décision explicite de diffusion, prise par une personne habilitée.
    diffusion_autorisee = models.BooleanField(default=False)
    decide_par = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='+',
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'confidentialite_dossier'

    def __str__(self):
        """Libellé lisible : dossier et niveau."""
        return f"Dossier #{self.dossier_id} : {self.niveau}"


class HabilitationDossier(models.Model):
    """
    Autorisation nominative de consulter les rapports d'un dossier
    confidentiel, pour une période donnée. Une habilitation retirée
    (`revoquee`) ou expirée ne donne plus accès, même par une ancienne URL.
    """

    dossier = models.ForeignKey(
        InternshipFolder, on_delete=models.CASCADE, related_name='habilitations',
    )
    beneficiaire = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='habilitations_dossiers',
    )
    valide_du = models.DateTimeField()
    # Fin de validité (NULL : jusqu'au retrait).
    valide_au = models.DateTimeField(null=True, blank=True)
    revoquee = models.BooleanField(default=False)
    accordee_par = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='+',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'habilitation_dossier'
        ordering = ['-created_at', 'pk']

    def __str__(self):
        """Libellé lisible : bénéficiaire et dossier."""
        return f"Habilitation du compte #{self.beneficiaire_id} sur le dossier #{self.dossier_id}"


class JournalAccesDocument(models.Model):
    """
    Journal d'audit des accès aux rapports (autorisés ou refusés).

    Ne contient jamais le contenu du document. L'identifiant de la version
    est conservé en clair (sans clé étrangère) pour que la trace survive à
    une suppression éventuelle du document.
    """

    version_document_id = models.IntegerField()
    utilisateur = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='+',
    )
    action = models.CharField(max_length=30, default='telechargement')
    autorise = models.BooleanField()
    # Raison d'un refus (aucune donnée confidentielle).
    motif = models.CharField(max_length=255, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'journal_acces_document'
        ordering = ['-created_at', '-pk']

    def __str__(self):
        """Libellé lisible : document, compte et décision."""
        decision = 'autorisé' if self.autorise else 'refusé'
        return f"Accès {decision} au document #{self.version_document_id}"


# ==========================================
# 7. GRILLE D'ÉVALUATION ET PROCÈS-VERBAUX (F06)
# ==========================================
class GrilleEvaluation(models.Model):
    """
    Grille de notation d'une campagne, versionnée et figée une fois utilisée.

    Règle FICTIVE de démonstration (à valider avec l'enseignant, ce n'est
    pas une règle officielle de l'établissement) : rapport 40 %, oral 60 %,
    notes sur 20, moyenne arrondie au centième (demi supérieur). Exemple :
    rapport 14 et oral 16 donnent 0,4 × 14 + 0,6 × 16 = 15,20.
    Pour changer de règle, on crée une NOUVELLE version : un procès-verbal
    garde toujours la version avec laquelle il a été calculé.
    """

    campagne = models.ForeignKey(
        Campaign, on_delete=models.PROTECT, related_name='grilles',
    )
    version = models.PositiveIntegerField(default=1)
    # Coefficients exacts (type décimal), dont la somme doit valoir 1.
    poids_rapport = models.DecimalField(max_digits=4, decimal_places=3, default=Decimal('0.400'))
    poids_oral = models.DecimalField(max_digits=4, decimal_places=3, default=Decimal('0.600'))
    # Borne supérieure de chaque note (la borne inférieure est 0).
    note_maximale = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal('20'))
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'grille_evaluation'
        ordering = ['campagne_id', '-version']
        constraints = [
            models.UniqueConstraint(
                fields=('campagne', 'version'), name='grille_version_unique',
            ),
            # Coefficients positifs dont la somme vaut exactement 1 (100 %).
            models.CheckConstraint(
                condition=Q(poids_rapport__gte=0, poids_oral__gte=0)
                & Q(poids_rapport=Decimal('1') - models.F('poids_oral')),
                name='grille_somme_coefficients_1',
            ),
        ]

    def __str__(self):
        """Libellé lisible : campagne, version et coefficients."""
        return (f"Grille v{self.version} — campagne #{self.campagne_id} "
                f"(rapport {self.poids_rapport}, oral {self.poids_oral})")


class ProcesVerbal(models.Model):
    """
    Version d'un procès-verbal de soutenance (approbation ou rectification).

    Conserve une copie figée : version de grille, notes sources, moyenne
    calculée, composition du jury et approbateur. Une rectification crée
    une nouvelle version avec motif ; la précédente passe à « remplace »
    mais reste consultable (STA12). L'approbation dans l'application n'est
    pas une signature électronique qualifiée (hors du socle).
    """

    STATUTS = (('approuve', 'Approuvé'), ('remplace', 'Remplacé'))

    # PROTECT : un PV validé ne disparaît pas avec l'évaluation.
    evaluation = models.ForeignKey(
        Assessment, on_delete=models.PROTECT, related_name='proces_verbaux',
    )
    version = models.PositiveIntegerField()
    grille = models.ForeignKey(
        GrilleEvaluation, on_delete=models.PROTECT, related_name='proces_verbaux',
    )
    note_rapport = models.DecimalField(max_digits=5, decimal_places=2)
    note_oral = models.DecimalField(max_digits=5, decimal_places=2)
    moyenne = models.DecimalField(max_digits=5, decimal_places=2)
    # Composition du jury au moment de l'approbation : [{"nom", "role"}].
    membres_jury = models.JSONField(default=list)
    statut = models.CharField(max_length=20, choices=STATUTS, default='approuve')
    # Motif de la rectification (vide pour la première approbation).
    motif = models.TextField(blank=True, default='')
    approuve_par = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='+',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'proces_verbal'
        ordering = ['evaluation_id', 'version']
        constraints = [
            models.UniqueConstraint(
                fields=('evaluation', 'version'), name='pv_version_unique',
            ),
        ]

    def __str__(self):
        """Libellé lisible : évaluation, version et statut."""
        return f"PV v{self.version} — évaluation #{self.evaluation_id} ({self.statut})"


# ==========================================
# 8. PUBLICATION DU PLANNING ET CONVOCATIONS (F05)
# ==========================================
class VersionPlanning(models.Model):
    """
    Version figée du planning, créée à chaque publication.

    Numérotée 1, 2, 3… ; une modification après publication (report)
    n'est visible des participants qu'à la publication suivante, qui crée
    une nouvelle version identifiable (STA07).
    """

    numero = models.PositiveIntegerField(unique=True)
    publiee_par = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='+',
    )
    publiee_le = models.DateTimeField(auto_now_add=True)
    commentaire = models.TextField(blank=True, default='')
    # Nombre de soutenances publiées ou republiées dans cette version.
    nombre_soutenances = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = 'version_planning'
        ordering = ['-numero']

    def __str__(self):
        """Libellé lisible : numéro de version."""
        return f"Planning version {self.numero}"


class Convocation(models.Model):
    """
    Convocation d'un participant (étudiant ou membre du jury) à une
    soutenance, liée à la version du planning qui l'a produite.

    Les informations du créneau sont COPIÉES : une convocation reste
    interprétable même après un report. Une convocation remplacée garde son
    lien vers la nouvelle (`remplacee_par`). L'envoi (courriel simulé) est
    suivi par `notification` : son échec n'annule jamais la publication.
    """

    STATUTS = (
        ('active', 'Active'),
        ('remplacee', 'Remplacée'),
        ('annulee', 'Annulée'),
    )
    NOTIFICATIONS = (
        ('en_attente', 'En attente'),
        ('envoyee', 'Envoyée'),
        ('echec', 'Échec'),
    )

    version = models.ForeignKey(
        VersionPlanning, on_delete=models.PROTECT, related_name='convocations',
    )
    # PROTECT : une soutenance publiée ne se supprime pas (on l'annule).
    soutenance = models.ForeignKey(
        Defense, on_delete=models.PROTECT, related_name='convocations',
    )
    destinataire = models.CharField(max_length=255)
    # etudiant, president, rapporteur, examinateur…
    role_destinataire = models.CharField(max_length=50)
    compte = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='convocations',
    )
    debut = models.DateTimeField()
    fin = models.DateTimeField()
    salle = models.CharField(max_length=100)
    jury = models.CharField(max_length=100, blank=True, default='')
    statut = models.CharField(max_length=20, choices=STATUTS, default='active')
    remplacee_par = models.ForeignKey(
        'self', on_delete=models.SET_NULL, null=True, blank=True, related_name='+',
    )
    notification = models.CharField(
        max_length=20, choices=NOTIFICATIONS, default='en_attente',
    )
    tentatives_envoi = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'convocation'
        ordering = ['debut', 'pk']

    def __str__(self):
        """Libellé lisible : destinataire, soutenance et version."""
        return (f"Convocation de {self.destinataire} — soutenance "
                f"#{self.soutenance_id} ({self.statut})")


# ==========================================
# 9. INDISPONIBILITÉS RÉCURRENTES (complément F04)
# ==========================================
class Indisponibilite(models.Model):
    """
    Indisponibilité hebdomadaire d'un membre de jury ou d'une salle sur une
    période, ex. « chaque mardi de 9 h à 12 h du 1er au 31 mars ».

    Les heures sont exprimées dans le fuseau `fuseau` (fuseau métier par
    défaut) puis converties en UTC pour être comparées aux créneaux. Une
    exception rend la ressource disponible une date précise. Un membre est
    désigné par son nom, comme pour le contrôle EXG01 des membres partagés.
    """

    TYPES = (('membre', 'Membre de jury'), ('salle', 'Salle'))
    JOURS = (
        (0, 'Lundi'), (1, 'Mardi'), (2, 'Mercredi'), (3, 'Jeudi'),
        (4, 'Vendredi'), (5, 'Samedi'), (6, 'Dimanche'),
    )

    type_ressource = models.CharField(max_length=10, choices=TYPES)
    # Nom du membre de jury ou de la salle.
    ressource = models.CharField(max_length=255)
    jour_semaine = models.PositiveSmallIntegerField(choices=JOURS)
    heure_debut = models.TimeField()
    heure_fin = models.TimeField()
    fuseau = models.CharField(max_length=64)
    valide_du = models.DateField()
    valide_au = models.DateField()
    motif = models.CharField(max_length=255, blank=True, default='')
    cree_par = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        blank=True, related_name='+',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'indisponibilite'
        ordering = ['ressource', 'jour_semaine', 'heure_debut']
        constraints = [
            models.CheckConstraint(
                condition=Q(heure_fin__gt=models.F('heure_debut')),
                name='indisponibilite_heures_ordonnees',
            ),
            models.CheckConstraint(
                condition=Q(valide_au__gte=models.F('valide_du')),
                name='indisponibilite_periode_ordonnee',
            ),
            models.CheckConstraint(
                condition=Q(jour_semaine__lte=6),
                name='indisponibilite_jour_valide',
            ),
        ]

    def __str__(self):
        """Libellé lisible : ressource, jour et heures."""
        return (f"{self.ressource} indisponible le "
                f"{self.get_jour_semaine_display().lower()} "
                f"{self.heure_debut:%H:%M}–{self.heure_fin:%H:%M}")


class ExceptionIndisponibilite(models.Model):
    """Date où une indisponibilité récurrente ne s'applique pas."""

    regle = models.ForeignKey(
        Indisponibilite, on_delete=models.CASCADE, related_name='exceptions',
    )
    date = models.DateField()

    class Meta:
        db_table = 'indisponibilite_exception'
        ordering = ['date']
        constraints = [
            models.UniqueConstraint(
                fields=('regle', 'date'), name='exception_unique_par_regle',
            ),
        ]

    def __str__(self):
        """Libellé lisible : date d'exception."""
        return f"Exception du {self.date:%d/%m/%Y} (règle #{self.regle_id})"


# ==========================================
# 10. IDEMPOTENCE DES OPÉRATIONS SENSIBLES (chapitre 6)
# ==========================================
class CleIdempotence(models.Model):
    """
    Résultat mémorisé d'une opération logique identifiée par l'en-tête
    Idempotency-Key (publication du planning, approbation…).

    Même clé et même contenu : même réponse, sans second effet. Même clé et
    contenu différent : refus (409). Enregistrée dans la MÊME transaction
    que l'opération elle-même.
    """

    cle = models.CharField(max_length=100)
    # Périmètre : opération + compte (une clé n'a de sens que pour eux).
    perimetre = models.CharField(max_length=150)
    # Empreinte SHA-256 du contenu de la demande.
    empreinte = models.CharField(max_length=64)
    code_http = models.PositiveSmallIntegerField()
    reponse = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'cle_idempotence'
        constraints = [
            models.UniqueConstraint(
                fields=('cle', 'perimetre'), name='cle_idempotence_unique',
            ),
        ]

    def __str__(self):
        """Libellé lisible : opération et clé."""
        return f"{self.perimetre} — clé {self.cle}"
