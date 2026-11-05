from django.contrib import admin

from .models import StudentAccount


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
