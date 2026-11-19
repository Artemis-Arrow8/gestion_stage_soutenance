"""
Tests des fonctionnalités ajoutées pour les nouveaux écrans Flutter :
    * profil étudiant enrichi (dossier, soutenance, note validée) ;
    * changement de son propre mot de passe ;
    * évaluations : moyenne automatique (grille 40/60) et unicité par soutenance ;
    * soutenances : confirmation (action dédiée) et suppression par le personnel.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from rest_framework.test import APIClient

from api.models import Assessment, Campaign, Defense, StudentAccount

from .factories import creer_defense, creer_dossier, creer_jury, creneau

User = get_user_model()

# Mot de passe des comptes créés pour ces tests.
MDP = 'mot-de-passe-de-test-solide'


def creer_compte(username, role):
    """
    Crée un compte appartenant au groupe de rôle indiqué.

    Paramètres :
        username (str) : identifiant de connexion.
        role (str) : nom du groupe (responsible, supervisor, jury…).
    """
    user = User.objects.create_user(username=username, password=MDP)
    groupe, _ = Group.objects.get_or_create(name=role)
    user.groups.add(groupe)
    return user


class ProfilEtudiantTests(TestCase):
    """Le profil d'un étudiant expose son dossier et sa soutenance."""

    def setUp(self):
        """Crée un étudiant lié à un dossier recevable et planifié."""
        self.dossier = creer_dossier()
        self.etudiant = User.objects.create_user(username='etu.profil', password=MDP)
        StudentAccount.objects.create(user=self.etudiant, student=self.dossier.student)
        self.defense = creer_defense(
            self.dossier, creer_jury(), 'Salle 101', creneau(8, 0, 9, 0)
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.etudiant)

    def test_le_profil_contient_la_soutenance(self):
        """Créneau, salle et statut de la soutenance figurent dans le profil."""
        profil = self.client.get('/api/profile/').json()['user']

        self.assertEqual(profil['role'], 'student')
        self.assertEqual(profil['folder_company'], self.dossier.company_name)
        self.assertEqual(profil['defense']['room_name'], 'Salle 101')
        self.assertIsNone(profil['defense']['final_average'])

    def test_la_note_n_apparait_qu_une_fois_validee(self):
        """Une note non validée reste masquée ; validée, elle est visible."""
        evaluation = Assessment.objects.create(
            defense=self.defense, report_grade=14, oral_grade=16, final_average=15,
        )
        profil = self.client.get('/api/profile/').json()['user']
        self.assertIsNone(profil['defense']['final_average'])

        evaluation.is_approved = True
        evaluation.save()
        profil = self.client.get('/api/profile/').json()['user']
        self.assertEqual(Decimal(profil['defense']['final_average']), Decimal('15'))


class CreationDossierParEtudiantTests(TestCase):
    """Un étudiant crée son dossier sans connaître l'identifiant de campagne."""

    def test_la_campagne_active_est_utilisee_par_defaut(self):
        """Sans campagne fournie, le dossier rejoint la campagne active."""
        dossier_existant = creer_dossier()
        # La campagne de ce dossier est close ; une nouvelle campagne est
        # active : l'étudiant n'y a pas encore de dossier (un seul par campagne).
        dossier_existant.campaign.is_active = False
        dossier_existant.campaign.save()
        Campaign.objects.create(academic_year='2027-2028', is_active=True)
        etudiant = User.objects.create_user(username='etu.nouveau', password=MDP)
        StudentAccount.objects.create(user=etudiant, student=dossier_existant.student)
        client = APIClient()
        client.force_authenticate(user=etudiant)

        reponse = client.post('/api/internship-folders/', {
            'company_name': 'Entreprise du stage',
            'subject': 'Sujet du stage',
        }, format='json')

        self.assertEqual(reponse.status_code, 201, reponse.content)
        self.assertEqual(reponse.json()['status'], 'brouillon')
        self.assertIsNotNone(reponse.json()['campaign'])


class ChangementMotDePasseTests(TestCase):
    """Un utilisateur connecté peut changer son propre mot de passe."""

    def setUp(self):
        """Crée et authentifie un encadreur."""
        self.user = creer_compte('enc.motdepasse', 'supervisor')
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_changement_reussi(self):
        """Avec le bon mot de passe actuel, le nouveau est enregistré."""
        reponse = self.client.post('/api/profile/password/', {
            'old_password': MDP,
            'new_password': 'Nouvelle-Phrase-Secrete-2026',
        }, format='json')

        self.assertEqual(reponse.status_code, 200, reponse.content)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password('Nouvelle-Phrase-Secrete-2026'))

    def test_ancien_mot_de_passe_incorrect(self):
        """Un mot de passe actuel erroné est refusé."""
        reponse = self.client.post('/api/profile/password/', {
            'old_password': 'faux',
            'new_password': 'Nouvelle-Phrase-Secrete-2026',
        }, format='json')

        self.assertEqual(reponse.status_code, 400)
        self.assertIn('incorrect', reponse.json()['error'])

    def test_mot_de_passe_trop_faible(self):
        """Les règles de sécurité de Django s'appliquent au nouveau mot de passe."""
        reponse = self.client.post('/api/profile/password/', {
            'old_password': MDP,
            'new_password': '123',
        }, format='json')

        self.assertEqual(reponse.status_code, 400)

    def test_acces_refuse_sans_connexion(self):
        """La route exige une session authentifiée."""
        reponse = APIClient().post('/api/profile/password/', {}, format='json')

        self.assertEqual(reponse.status_code, 401)


class EvaluationsEtSoutenancesTests(TestCase):
    """Saisie des notes et gestion des soutenances par le personnel."""

    def setUp(self):
        """Crée un responsable authentifié et une soutenance planifiée."""
        self.client = APIClient()
        self.client.force_authenticate(user=creer_compte('resp.test', 'responsible'))
        self.defense = creer_defense(
            creer_dossier(), creer_jury(), 'Salle 102', creneau(10, 0, 11, 0)
        )

    def test_la_moyenne_est_calculee_automatiquement(self):
        """
        La moyenne est calculée par le serveur avec la grille fictive 40/60
        (STA10) : 0,4 × 14 + 0,6 × 17 = 15,80. Une moyenne envoyée par le
        client est ignorée.
        """
        reponse = self.client.post('/api/assessments/', {
            'defense': self.defense.pk,
            'report_grade': '14.00',
            'oral_grade': '17.00',
            'final_average': '20.00',
        }, format='json')

        self.assertEqual(reponse.status_code, 201, reponse.content)
        self.assertEqual(Decimal(reponse.json()['final_average']), Decimal('15.80'))
        self.assertTrue(reponse.json()['student_name'])

    def test_une_seule_evaluation_par_soutenance(self):
        """Une seconde évaluation de la même soutenance est refusée."""
        Assessment.objects.create(defense=self.defense, report_grade=12, oral_grade=12)
        reponse = self.client.post('/api/assessments/', {
            'defense': self.defense.pk,
            'report_grade': '15.00',
            'oral_grade': '15.00',
        }, format='json')

        self.assertEqual(reponse.status_code, 400)

    def test_changement_de_statut_d_une_soutenance(self):
        """
        Le statut ne se modifie pas directement : la confirmation passe par
        l'action dédiée, qui exige un jury déclaré complet (F04).
        """
        reponse = self.client.patch(
            f'/api/soutenances/{self.defense.pk}/', {'status': 'confirme'}, format='json',
        )
        self.defense.refresh_from_db()
        self.assertEqual(self.defense.status, 'planifie')  # champ en lecture seule

        refus = self.client.post(f'/api/soutenances/{self.defense.pk}/confirmer/')
        self.assertEqual(refus.status_code, 409, refus.content)
        self.assertEqual(refus.json()['regle'], 'F04')

        self.defense.jury.is_complete = True
        self.defense.jury.save()
        reponse = self.client.post(f'/api/soutenances/{self.defense.pk}/confirmer/')
        self.assertEqual(reponse.status_code, 200, reponse.content)
        self.defense.refresh_from_db()
        self.assertEqual(self.defense.status, 'confirme')

    def test_suppression_d_une_soutenance(self):
        """Le personnel peut supprimer une soutenance."""
        reponse = self.client.delete(f'/api/soutenances/{self.defense.pk}/')

        self.assertEqual(reponse.status_code, 204)
        self.assertFalse(Defense.objects.filter(pk=self.defense.pk).exists())
