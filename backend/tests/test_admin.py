"""
Tests du site d'administration Django (/admin/).

Vérifie qu'un superutilisateur voit toutes les tables métier et peut ouvrir,
pour chacune, la liste, le formulaire d'ajout et la fiche d'un élément.
"""

from django.conf import settings
from django.contrib import admin
from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.urls import reverse

from api.models import (
    Assessment,
    Campaign,
    Defense,
    DocumentVersion,
    FolderSupervisor,
    InternshipFolder,
    Jury,
    JuryMember,
    JuryMemberAccount,
    Review,
    Room,
    Student,
    StudentAccount,
)

from .factories import creer_avis, creer_defense, creer_dossier, creer_jury, creneau

User = get_user_model()

# Toutes les tables métier attendues dans l'administration.
MODELES_ADMIN = (
    Assessment, Campaign, Defense, DocumentVersion, FolderSupervisor,
    InternshipFolder, Jury, JuryMember, JuryMemberAccount, Review, Room,
    Student, StudentAccount,
)


# Le stockage « manifeste » de WhiteNoise exige un `collectstatic` préalable
# (fait dans l'image Docker) ; les tests utilisent le stockage simple.
STORAGES_DE_TEST = {
    **settings.STORAGES,
    'staticfiles': {
        'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage',
    },
}


@override_settings(STORAGES=STORAGES_DE_TEST)
class AdministrationDjangoTests(TestCase):
    """Le superutilisateur doit pouvoir gérer toutes les données métier."""

    def setUp(self):
        """Crée un superutilisateur connecté et un jeu de données minimal."""
        self.admin = User.objects.create_superuser(
            username='admin.test',
            email='admin@example.test',
            password='mot-de-passe-admin-de-test',
        )
        self.client.force_login(self.admin)
        # Données couvrant chaque table (dossier, avis, jury, soutenance…).
        dossier = creer_dossier()
        jury = creer_jury()
        creer_avis(dossier)
        defense = creer_defense(dossier, jury, 'Salle 101', creneau(8, 0, 9, 0))
        Assessment.objects.create(defense=defense, report_grade=15, oral_grade=16)

    def test_toutes_les_tables_metier_sont_enregistrees(self):
        """Chaque modèle métier apparaît dans l'administration."""
        for modele in MODELES_ADMIN:
            with self.subTest(modele=modele.__name__):
                self.assertTrue(admin.site.is_registered(modele))

    def test_listes_ajout_et_fiches_s_affichent(self):
        """Liste, ajout et fiche détaillée répondent 200 pour chaque table."""
        for modele in MODELES_ADMIN:
            app, nom = modele._meta.app_label, modele._meta.model_name
            with self.subTest(modele=modele.__name__):
                liste = self.client.get(reverse(f'admin:{app}_{nom}_changelist'))
                self.assertEqual(liste.status_code, 200)
                ajout = self.client.get(reverse(f'admin:{app}_{nom}_add'))
                self.assertEqual(ajout.status_code, 200)
                objet = modele.objects.first()
                if objet is not None:
                    fiche = self.client.get(
                        reverse(f'admin:{app}_{nom}_change', args=[objet.pk])
                    )
                    self.assertEqual(fiche.status_code, 200)

    def test_les_comptes_et_roles_restent_geres_par_django(self):
        """La gestion des comptes (mots de passe compris) reste disponible."""
        reponse = self.client.get(reverse('admin:auth_user_changelist'))
        self.assertEqual(reponse.status_code, 200)
        self.assertContains(reponse, 'admin.test')
