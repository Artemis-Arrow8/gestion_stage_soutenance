"""
Test de non-régression : les listes de l'API reflètent toujours la base.

Bug corrigé : plusieurs ViewSets renvoyaient directement le `queryset`
défini au niveau de la classe. Django mémorise le résultat d'un QuerySet une
fois évalué ; ce QuerySet de classe étant partagé par toutes les requêtes du
processus, la PREMIÈRE liste consultée restait figée. En production, une
liste vide consultée avant l'import des données restait vide jusqu'au
redémarrage du serveur, et un jury créé depuis l'application n'apparaissait
pas dans la liste.

Ces tests enchaînent « liste vide → création → nouvelle liste » dans le même
processus, exactement comme sur le serveur.
"""

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from rest_framework.test import APIClient

from .factories import creer_defense, creer_dossier, creer_jury, creneau

User = get_user_model()


class ListesToujoursAJourTests(TestCase):
    """Chaque liste doit inclure les lignes créées après une première lecture."""

    def setUp(self):
        """Crée un responsable pédagogique authentifié auprès du client API."""
        responsable = User.objects.create_user(
            username='responsable.test',
            password='mot-de-passe-de-test-solide',
        )
        groupe, _ = Group.objects.get_or_create(name='responsible')
        responsable.groups.add(groupe)
        self.client = APIClient()
        self.client.force_authenticate(user=responsable)

    def _nombre(self, route):
        """
        Retourne le nombre d'éléments renvoyés par une route de liste.

        Paramètres :
            route (str) : chemin de l'API (ex. « /api/jurys/ »).
        """
        reponse = self.client.get(route)
        self.assertEqual(reponse.status_code, 200, reponse.content)
        return len(reponse.json())

    def test_la_liste_des_jurys_inclut_un_jury_cree_apres_lecture(self):
        """Une liste lue avant la création d'un jury doit ensuite l'inclure."""
        avant = self._nombre('/api/jurys/')
        creer_jury()
        self.assertEqual(self._nombre('/api/jurys/'), avant + 1)

    def test_la_liste_des_dossiers_inclut_un_dossier_cree_apres_lecture(self):
        """Même scénario pour les dossiers de stage."""
        avant = self._nombre('/api/internship-folders/')
        creer_dossier()
        self.assertEqual(self._nombre('/api/internship-folders/'), avant + 1)

    def test_la_liste_des_soutenances_inclut_une_soutenance_creee_apres_lecture(self):
        """Même scénario pour les soutenances (route standard, hors planning)."""
        avant = self._nombre('/api/soutenances/')
        creer_defense(creer_dossier(), creer_jury(), 'Salle 101', creneau(8, 0, 9, 0))
        self.assertEqual(self._nombre('/api/soutenances/'), avant + 1)

    def test_la_liste_des_membres_inclut_un_membre_cree_apres_lecture(self):
        """Même scénario pour les membres de jury."""
        avant = self._nombre('/api/jury-members/')
        creer_jury(noms=['Membre ajouté après lecture'])
        self.assertEqual(self._nombre('/api/jury-members/'), avant + 1)
