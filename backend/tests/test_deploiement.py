"""
Tests du socle de déploiement : route racine, sonde de santé et réglages
spécifiques à Render.

* Les tests HTTP utilisent le client de test Django (base de test PostgreSQL).
* Les tests de configuration importent `config.settings` dans un processus
  Python séparé, avec un environnement contrôlé, afin de vérifier le
  comportement en production sans modifier les réglages du processus courant.
"""

import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

from django.db.utils import OperationalError
from django.test import SimpleTestCase, TestCase, override_settings

# Dossier backend/ (contient manage.py), utilisé comme répertoire de travail.
BACKEND_DIR = Path(__file__).resolve().parents[1]


class RouteRacineTests(TestCase):
    """Vérifie que `/` ne renvoie plus 404 mais une description JSON."""

    def test_la_racine_renvoie_une_page_d_accueil_json(self):
        """GET / doit répondre 200 avec les liens vers l'API et la sonde."""
        reponse = self.client.get('/')

        self.assertEqual(reponse.status_code, 200)
        donnees = reponse.json()
        self.assertEqual(donnees['status'], 'ok')
        self.assertTrue(donnees['endpoints']['api'].endswith('/api/'))
        self.assertTrue(donnees['endpoints']['health'].endswith('/health/'))

    def test_la_racine_refuse_les_methodes_d_ecriture(self):
        """POST / n'a pas de sens : la vue doit répondre 405."""
        reponse = self.client.post('/')

        self.assertEqual(reponse.status_code, 405)


class SondeSanteTests(TestCase):
    """Vérifie le comportement de la sonde /health/."""

    def test_la_sonde_confirme_la_disponibilite_de_la_base(self):
        """Base joignable : 200 et `database: ok`."""
        reponse = self.client.get('/health/')

        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(reponse.json(), {'status': 'ok', 'database': 'ok'})
        self.assertEqual(reponse['Cache-Control'], 'no-store')

    def test_la_sonde_accepte_le_chemin_sans_barre_finale(self):
        """`/health` (sans barre oblique) est accepté par la sonde."""
        reponse = self.client.get('/health')

        self.assertEqual(reponse.status_code, 200)

    @override_settings(ALLOWED_HOSTS=['api.example.test'])
    def test_la_sonde_ignore_le_controle_des_hotes(self):
        """Une sonde interne arrivant avec l'IP du conteneur reste servie."""
        reponse = self.client.get('/health/', HTTP_HOST='10.0.0.12:10000')

        self.assertEqual(reponse.status_code, 200)

    @override_settings(SECURE_SSL_REDIRECT=True)
    def test_la_sonde_n_est_pas_redirigee_vers_https(self):
        """La sonde HTTP interne ne doit pas recevoir de redirection 301."""
        reponse = self.client.get('/health/')

        self.assertEqual(reponse.status_code, 200)

    def test_la_sonde_signale_une_base_injoignable(self):
        """Base injoignable : 503 sans divulguer le détail de l'erreur."""
        # Les deux journaux attendus (service + réponse 5xx) sont capturés
        # pour vérifier leur présence sans polluer la sortie des tests.
        with mock.patch(
            'api.services.sante.connection.cursor',
            side_effect=OperationalError('connexion refusée'),
        ), self.assertLogs('api.services.sante', level='ERROR'), \
                self.assertLogs('django.request', level='ERROR'):
            reponse = self.client.get('/health/')

        self.assertEqual(reponse.status_code, 503)
        self.assertEqual(
            reponse.json(),
            {'status': 'error', 'database': 'unavailable'},
        )


class OriginesCorsTests(SimpleTestCase):
    """Vérifie les en-têtes CORS renvoyés au frontend Flutter Web."""

    @override_settings(
        CORS_ALLOWED_ORIGINS=['https://app.example.test'],
        CORS_ALLOWED_ORIGIN_REGEXES=[],
    )
    def test_une_origine_autorisee_recoit_l_en_tete_cors(self):
        """La requête préalable OPTIONS d'une origine connue est acceptée."""
        reponse = self.client.options(
            '/api/login/',
            HTTP_ORIGIN='https://app.example.test',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
        )

        self.assertEqual(
            reponse['Access-Control-Allow-Origin'],
            'https://app.example.test',
        )

    @override_settings(
        CORS_ALLOWED_ORIGINS=['https://app.example.test'],
        CORS_ALLOWED_ORIGIN_REGEXES=[],
    )
    def test_une_origine_inconnue_ne_recoit_pas_l_en_tete_cors(self):
        """Une origine non déclarée n'obtient aucune autorisation CORS."""
        reponse = self.client.options(
            '/api/login/',
            HTTP_ORIGIN='https://pirate.example.test',
            HTTP_ACCESS_CONTROL_REQUEST_METHOD='POST',
        )

        self.assertNotIn('Access-Control-Allow-Origin', reponse)


class ReglagesRenderTests(unittest.TestCase):
    """Vérifie la configuration automatique propre à Render."""

    def _importer_reglages(self, commande, **variables):
        """
        Importe les réglages dans un sous-processus de production simulé.

        Paramètres :
            commande (str) : code Python exécuté après l'import.
            **variables : variables d'environnement à ajouter ou remplacer.

        Retour :
            subprocess.CompletedProcess : code de retour, stdout et stderr.
        """
        environnement = os.environ.copy()
        # Socle minimal valide pour un démarrage en production.
        environnement.update({
            'DJANGO_DEBUG': 'False',
            'DJANGO_SECRET_KEY': (
                'synthetic-test-secret-key-that-is-at-least-fifty-characters-long'
            ),
            'DATABASE_URL': (
                'postgresql://render_user:'
                'synthetic-render-password-with-more-than-thirty-two-characters'
                '@db.example.test:5432/sgsus'
            ),
            'DJANGO_ALLOWED_HOSTS': '',
            'DJANGO_CORS_ALLOWED_ORIGINS': '',
            'DJANGO_CSRF_TRUSTED_ORIGINS': '',
            'DJANGO_SECURE_SSL_REDIRECT': 'True',
            'DJANGO_SECURE_COOKIES': 'True',
            'DB_ADMIN_USER': 'db_admin',
        })
        # Les variables Render ne doivent pas fuiter de l'environnement réel.
        for nom in ('RENDER', 'RENDER_EXTERNAL_HOSTNAME', 'DJANGO_BEHIND_HTTPS_PROXY'):
            environnement.pop(nom, None)
        environnement.update(variables)
        return subprocess.run(
            [sys.executable, '-c', f'import config.settings as s; {commande}'],
            cwd=BACKEND_DIR,
            env=environnement,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_render_ajoute_son_hote_public_automatiquement(self):
        """Sans DJANGO_ALLOWED_HOSTS, l'hôte Render suffit à démarrer."""
        resultat = self._importer_reglages(
            'print(s.ALLOWED_HOSTS, s.CSRF_TRUSTED_ORIGINS)',
            RENDER='true',
            RENDER_EXTERNAL_HOSTNAME='sgsus-api.onrender.com',
        )

        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertIn("['sgsus-api.onrender.com']", resultat.stdout)
        self.assertIn("['https://sgsus-api.onrender.com']", resultat.stdout)

    def test_render_active_l_en_tete_du_proxy_https(self):
        """Sur Render, X-Forwarded-Proto est pris en compte (pas de boucle 301)."""
        resultat = self._importer_reglages(
            'print(s.SECURE_PROXY_SSL_HEADER)',
            RENDER='true',
            RENDER_EXTERNAL_HOSTNAME='sgsus-api.onrender.com',
        )

        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertIn('HTTP_X_FORWARDED_PROTO', resultat.stdout)

    def test_hors_render_le_proxy_suit_la_variable_explicite(self):
        """Ailleurs, l'en-tête du proxy n'est cru que sur demande explicite."""
        resultat = self._importer_reglages(
            'print(s.SECURE_PROXY_SSL_HEADER)',
            DJANGO_ALLOWED_HOSTS='sgsus.example.test',
            DJANGO_BEHIND_HTTPS_PROXY='False',
        )

        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertEqual(resultat.stdout.strip(), 'None')

    def test_les_origines_cors_sont_normalisees(self):
        """Une barre oblique finale est tolérée puis retirée."""
        resultat = self._importer_reglages(
            'print(s.CORS_ALLOWED_ORIGINS)',
            DJANGO_ALLOWED_HOSTS='sgsus.example.test',
            DJANGO_CORS_ALLOWED_ORIGINS='https://app.example.test/',
        )

        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertEqual(resultat.stdout.strip(), "['https://app.example.test']")

    def test_une_origine_cors_avec_chemin_est_refusee(self):
        """Une URL complète (avec /api) n'est pas une origine : refus explicite."""
        resultat = self._importer_reglages(
            'pass',
            DJANGO_ALLOWED_HOSTS='sgsus.example.test',
            DJANGO_CORS_ALLOWED_ORIGINS='https://app.example.test/api',
        )

        self.assertNotEqual(resultat.returncode, 0)
        self.assertIn('DJANGO_CORS_ALLOWED_ORIGINS', resultat.stderr)

    def test_un_hote_saisi_comme_url_est_normalise(self):
        """« https://hote/ » dans DJANGO_ALLOWED_HOSTS devient « hote »."""
        resultat = self._importer_reglages(
            'print(s.ALLOWED_HOSTS)',
            DJANGO_ALLOWED_HOSTS='https://sgsus.example.test/',
        )

        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertEqual(resultat.stdout.strip(), "['sgsus.example.test']")


if __name__ == '__main__':
    unittest.main()
