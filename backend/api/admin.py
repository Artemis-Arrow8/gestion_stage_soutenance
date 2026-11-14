from django.contrib import admin

from .models import FolderSupervisor, JuryMemberAccount, StudentAccount


@admin.register(StudentAccount)
class StudentAccountAdmin(admin.ModelAdmin):
    """Permet aux administrateurs d'associer les comptes aux étudiants."""

    list_display = ('user', 'student')
    search_fields = (
        'user__username',
        'student__student_number',
        'student__full_name',
        'student__email',
    )
    list_select_related = ('user', 'student')


@admin.register(JuryMemberAccount)
class JuryMemberAccountAdmin(admin.ModelAdmin):
    """Permet à l'administrateur d'associer un compte à un membre du jury."""

    list_display = ('user', 'jury_member')
    search_fields = (
        'user__username',
        'jury_member__member_name',
        'jury_member__jury__name',
    )
    list_select_related = ('user', 'jury_member', 'jury_member__jury')


@admin.register(FolderSupervisor)
class FolderSupervisorAdmin(admin.ModelAdmin):
    """Gère les dossiers précis accessibles à chaque encadreur."""

    list_display = ('user', 'folder')
    search_fields = (
        'user__username',
        'folder__student__student_number',
        'folder__student__full_name',
        'folder__company_name',
    )
    list_select_related = ('user', 'folder', 'folder__student')
