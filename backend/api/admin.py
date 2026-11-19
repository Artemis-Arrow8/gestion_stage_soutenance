"""
Configuration du site d'administration Django (/admin/) pour SGSUS.

Toutes les tables métier y sont exposées afin qu'un superutilisateur puisse
consulter et corriger les données sans passer par pgAdmin :
    * référentiels : campagnes, étudiants, salles, jurys et membres ;
    * suivi : dossiers de stage, versions de documents, avis ;
    * planification : soutenances et évaluations ;
    * liaisons de comptes : compte ↔ étudiant, compte ↔ membre de jury,
      encadreur ↔ dossier ;
    * socle ALM : grilles, indisponibilités, confidentialité, habilitations,
      et, en LECTURE SEULE, les traces validées (historique des dossiers,
      procès-verbaux, versions du planning, convocations, journal d'accès) :
      une trace ne se corrige jamais à la main (chapitre 20).
Les comptes et groupes (rôles) sont gérés par la section « Authentification
et autorisation » fournie par Django.
"""

from django.contrib import admin

from .models import (
    Assessment,
    Campaign,
    ConfidentialiteDossier,
    Convocation,
    Defense,
    DocumentVersion,
    ExceptionIndisponibilite,
    FolderSupervisor,
    GrilleEvaluation,
    HabilitationDossier,
    HistoriqueDossier,
    Indisponibilite,
    InternshipFolder,
    JournalAccesDocument,
    Jury,
    JuryMember,
    JuryMemberAccount,
    ProcesVerbal,
    Review,
    Room,
    Student,
    StudentAccount,
    VersionPlanning,
)

# Titres affichés dans l'interface d'administration.
admin.site.site_header = 'Administration SGSUS'
admin.site.site_title = 'SGSUS'
admin.site.index_title = 'Gestion des stages et des soutenances'


# =========================================================================
# 1. Référentiels
# =========================================================================

@admin.register(Campaign)
class CampaignAdmin(admin.ModelAdmin):
    """Campagnes académiques ; une seule devrait être active à la fois."""

    list_display = ('academic_year', 'is_active', 'created_at')
    list_filter = ('is_active',)
    search_fields = ('academic_year',)


@admin.register(Student)
class StudentAdmin(admin.ModelAdmin):
    """Fiches étudiantes (matricule, nom, e-mail)."""

    list_display = ('student_number', 'full_name', 'email')
    search_fields = ('student_number', 'full_name', 'email')
    ordering = ('student_number',)


@admin.register(Room)
class RoomAdmin(admin.ModelAdmin):
    """Catalogue des salles de soutenance."""

    list_display = ('name', 'capacity', 'is_active')
    list_filter = ('is_active',)
    search_fields = ('name',)
    ordering = ('name',)


class JuryMemberInline(admin.TabularInline):
    """Membres affichés et modifiables directement dans la fiche du jury."""

    model = JuryMember
    extra = 0


@admin.register(Jury)
class JuryAdmin(admin.ModelAdmin):
    """Jurys de soutenance, avec leurs membres en tableau intégré."""

    list_display = ('name', 'is_complete', 'nombre_membres')
    list_filter = ('is_complete',)
    search_fields = ('name', 'members__member_name')
    ordering = ('name',)
    inlines = [JuryMemberInline]

    @admin.display(description='Membres')
    def nombre_membres(self, jury):
        """Retourne le nombre de membres du jury."""
        return jury.members.count()


@admin.register(JuryMember)
class JuryMemberAdmin(admin.ModelAdmin):
    """Membres de jury (président, rapporteur, examinateur)."""

    list_display = ('member_name', 'role_in_jury', 'jury')
    list_filter = ('role_in_jury', 'jury')
    search_fields = ('member_name', 'jury__name')
    list_select_related = ('jury',)


# =========================================================================
# 2. Dossiers, documents et avis
# =========================================================================

@admin.register(InternshipFolder)
class InternshipFolderAdmin(admin.ModelAdmin):
    """Dossiers de stage ; le statut « recevable » rend le dossier planifiable."""

    list_display = ('id', 'student', 'company_name', 'status', 'campaign', 'created_at')
    list_filter = ('status', 'campaign')
    search_fields = (
        'company_name',
        'subject',
        'student__full_name',
        'student__student_number',
    )
    list_select_related = ('student', 'campaign')


@admin.register(DocumentVersion)
class DocumentVersionAdmin(admin.ModelAdmin):
    """Versions de rapports déposées (le fichier est sur le disque du serveur)."""

    list_display = ('id', 'dossier', 'version_number', 'file_path', 'uploaded_at')
    search_fields = ('folder__student__full_name', 'folder__company_name')
    list_select_related = ('folder', 'folder__student')

    @admin.display(description='Dossier', ordering='folder')
    def dossier(self, document):
        """Retourne le libellé du dossier auquel appartient la version."""
        return document.folder


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    """Avis d'encadrement sur une version de document."""

    list_display = ('id', 'document_version', 'author', 'author_role', 'decision', 'created_at')
    list_filter = ('decision', 'author_role')
    search_fields = ('comments', 'author__username')
    list_select_related = ('author', 'document_version')


# =========================================================================
# 3. Planification et évaluations
# =========================================================================

@admin.register(Defense)
class DefenseAdmin(admin.ModelAdmin):
    """
    Soutenances planifiées.

    Les contraintes PostgreSQL interdisent toujours les doubles réservations
    d'une salle ou d'un jury, même lors d'une saisie depuis cette page.
    """

    list_display = ('id', 'etudiant', 'jury', 'room_name', 'debut', 'fin', 'status')
    list_filter = ('status', 'room_name', 'jury')
    search_fields = ('folder__student__full_name', 'room_name', 'jury__name')
    list_select_related = ('folder', 'folder__student', 'jury')

    @admin.display(description='Étudiant')
    def etudiant(self, defense):
        """Retourne le nom de l'étudiant qui soutient."""
        return defense.folder.student.full_name

    @admin.display(description='Début (UTC)')
    def debut(self, defense):
        """Retourne le début du créneau."""
        return defense.slot_range.lower if defense.slot_range else None

    @admin.display(description='Fin (UTC)')
    def fin(self, defense):
        """Retourne la fin du créneau."""
        return defense.slot_range.upper if defense.slot_range else None


@admin.register(Assessment)
class AssessmentAdmin(admin.ModelAdmin):
    """Notes (sur 20) et validation finale des soutenances."""

    list_display = ('id', 'defense', 'report_grade', 'oral_grade', 'final_average', 'is_approved')
    list_filter = ('is_approved',)


# =========================================================================
# 4. Liaisons entre comptes et données métier
# =========================================================================

@admin.register(StudentAccount)
class StudentAccountAdmin(admin.ModelAdmin):
    """Associe un compte de connexion à une fiche étudiante."""

    list_display = ('user', 'student')
    # Recherche par identifiant de connexion ou par données de la fiche.
    search_fields = (
        'user__username',
        'student__student_number',
        'student__full_name',
        'student__email',
    )
    # Jointure SQL unique pour éviter une requête par ligne affichée.
    list_select_related = ('user', 'student')


@admin.register(JuryMemberAccount)
class JuryMemberAccountAdmin(admin.ModelAdmin):
    """Associe un compte de connexion à un membre du jury."""

    list_display = ('user', 'jury_member')
    search_fields = (
        'user__username',
        'jury_member__member_name',
        'jury_member__jury__name',
    )
    list_select_related = ('user', 'jury_member', 'jury_member__jury')


@admin.register(FolderSupervisor)
class FolderSupervisorAdmin(admin.ModelAdmin):
    """Affecte un encadreur aux dossiers précis qu'il peut consulter."""

    list_display = ('user', 'folder')
    search_fields = (
        'user__username',
        'folder__student__student_number',
        'folder__student__full_name',
        'folder__company_name',
    )
    list_select_related = ('user', 'folder', 'folder__student')


# =========================================================================
# 5. Socle ALM : paramètres modifiables
# =========================================================================
@admin.register(GrilleEvaluation)
class GrilleEvaluationAdmin(admin.ModelAdmin):
    """Grilles de notation versionnées (une nouvelle version par changement)."""

    list_display = ('campagne', 'version', 'poids_rapport', 'poids_oral', 'note_maximale')
    list_filter = ('campagne',)


class ExceptionIndisponibiliteInline(admin.TabularInline):
    """Dates d'exception saisies avec leur règle."""

    model = ExceptionIndisponibilite
    extra = 0


@admin.register(Indisponibilite)
class IndisponibiliteAdmin(admin.ModelAdmin):
    """Indisponibilités récurrentes des membres de jury et des salles."""

    list_display = ('ressource', 'type_ressource', 'jour_semaine', 'heure_debut',
                    'heure_fin', 'fuseau', 'valide_du', 'valide_au')
    list_filter = ('type_ressource', 'jour_semaine')
    search_fields = ('ressource',)
    inlines = [ExceptionIndisponibiliteInline]


@admin.register(ConfidentialiteDossier)
class ConfidentialiteDossierAdmin(admin.ModelAdmin):
    """Niveau de confidentialité et embargo des rapports par dossier."""

    list_display = ('dossier', 'niveau', 'embargo_jusqu_au', 'diffusion_autorisee')
    list_filter = ('niveau', 'diffusion_autorisee')


@admin.register(HabilitationDossier)
class HabilitationDossierAdmin(admin.ModelAdmin):
    """Habilitations nominatives sur les dossiers confidentiels."""

    list_display = ('beneficiaire', 'dossier', 'valide_du', 'valide_au', 'revoquee')
    list_filter = ('revoquee',)
    list_select_related = ('beneficiaire', 'dossier')


# =========================================================================
# 6. Socle ALM : traces validées, en lecture seule
# =========================================================================
class LectureSeuleAdmin(admin.ModelAdmin):
    """Consultation seule : ni ajout, ni modification, ni suppression."""

    def has_add_permission(self, request):
        """Aucune création manuelle de trace."""
        return False

    def has_change_permission(self, request, obj=None):
        """Aucune modification d'une trace validée."""
        return False

    def has_delete_permission(self, request, obj=None):
        """Aucune suppression d'une trace validée."""
        return False


@admin.register(HistoriqueDossier)
class HistoriqueDossierAdmin(LectureSeuleAdmin):
    """Transitions des dossiers (preuves conservées)."""

    list_display = ('dossier', 'evenement', 'statut_avant', 'statut_apres', 'acteur', 'created_at')
    list_filter = ('evenement',)


@admin.register(ProcesVerbal)
class ProcesVerbalAdmin(LectureSeuleAdmin):
    """Versions des procès-verbaux de soutenance."""

    list_display = ('evaluation', 'version', 'statut', 'moyenne', 'approuve_par', 'created_at')
    list_filter = ('statut',)


@admin.register(VersionPlanning)
class VersionPlanningAdmin(LectureSeuleAdmin):
    """Versions publiées du planning."""

    list_display = ('numero', 'publiee_le', 'publiee_par', 'nombre_soutenances')


@admin.register(Convocation)
class ConvocationAdmin(LectureSeuleAdmin):
    """Convocations produites par les publications."""

    list_display = ('destinataire', 'role_destinataire', 'soutenance', 'version',
                    'statut', 'notification', 'debut')
    list_filter = ('statut', 'notification', 'role_destinataire')
    search_fields = ('destinataire',)


@admin.register(JournalAccesDocument)
class JournalAccesDocumentAdmin(LectureSeuleAdmin):
    """Journal d'audit des accès aux rapports."""

    list_display = ('version_document_id', 'utilisateur', 'action', 'autorise', 'motif', 'created_at')
    list_filter = ('autorise', 'action')
