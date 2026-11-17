"""
Tests des garde-fous de configuration en production (DEBUG=False) :
hôtes autorisés, HTTPS, base de données et rôle PostgreSQL dédié.
Chaque test importe les réglages dans un sous-processus isolé.
"""

import os
from pathlib import Path
import subprocess
import sys
import unittest


BACKEND_DIR = Path(__file__).resolve().parents[1]


class ProductionSettingsTests(unittest.TestCase):
    # L'import isolé vérifie les réglages sans ouvrir de connexion PostgreSQL.
    def _import_settings(
        self,
        allowed_hosts=None,
        db_user="sgsus_app_user",
        db_admin_user="db_admin",
        secure_ssl_redirect="True",
        secure_cookies="True",
        command="import config.settings",
        database_url=None,
    ):
        environment = os.environ.copy()
        environment.update(
            {
                "DJANGO_DEBUG": "False",
                "DJANGO_SECRET_KEY": (
                    "synthetic-test-secret-key-that-is-at-least-fifty-characters-long"
                ),
                "POSTGRES_PASSWORD": "synthetic-test-database-password",
                "DB_USER": db_user,
                "DB_PASSWORD": (
                    "synthetic-test-app-password-with-at-least-thirty-two-characters"
                ),
                "DB_ADMIN_USER": db_admin_user,
                "DATABASE_URL": database_url or "",
                "DJANGO_SECURE_SSL_REDIRECT": secure_ssl_redirect,
                "DJANGO_SECURE_COOKIES": secure_cookies,
            }
        )
        environment["DJANGO_ALLOWED_HOSTS"] = ""
        if allowed_hosts is not None:
            environment["DJANGO_ALLOWED_HOSTS"] = allowed_hosts

        return subprocess.run(
            [sys.executable, "-c", command],
            cwd=BACKEND_DIR,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_production_requires_explicit_allowed_hosts(self):
        """En production, DJANGO_ALLOWED_HOSTS est obligatoire."""
        result = self._import_settings()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DJANGO_ALLOWED_HOSTS", result.stderr)

    def test_production_accepts_explicit_allowed_hosts(self):
        """En production, un hôte explicite permet le démarrage."""
        result = self._import_settings("sgsus.example.test")

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_production_rejects_an_empty_parsed_host_list(self):
        """Une liste d'hôtes vide après analyse (« ,,, ») est refusée."""
        result = self._import_settings(",,,")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DJANGO_ALLOWED_HOSTS", result.stderr)

    def test_production_requires_https_and_secure_cookies(self):
        """En production, la redirection HTTPS est obligatoire."""
        result = self._import_settings(
            "sgsus.example.test",
            secure_ssl_redirect="False",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DJANGO_SECURE_SSL_REDIRECT", result.stderr)

    def test_production_uses_the_dedicated_database_role(self):
        """Django utilise le rôle applicatif dédié de la base."""
        result = self._import_settings(
            "sgsus.example.test",
            command=(
                "from config.settings import DATABASES; "
                "print(DATABASES['default']['USER'])"
            ),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "sgsus_app_user")

    def test_production_reads_render_database_url_with_tls(self):
        """DATABASE_URL (Render) est lue avec TLS exigé par défaut."""
        result = self._import_settings(
            "sgsus.example.test",
            command=(
                "from config.settings import DATABASES; "
                "db = DATABASES['default']; "
                "print('|'.join(str(db[key]) for key in "
                "('USER', 'HOST', 'PORT', 'NAME')) + "
                "'|' + db['OPTIONS']['sslmode'])"
            ),
            database_url=(
                "postgresql://render_user:"
                "synthetic-render-password-with-more-than-thirty-two-characters"
                "@db.example.test:5432/sgsus"
            ),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            "render_user|db.example.test|5432|sgsus|require",
        )

    def test_production_rejects_non_postgresql_database_url(self):
        """Une DATABASE_URL non PostgreSQL est refusée."""
        result = self._import_settings(
            "sgsus.example.test",
            database_url="mysql://render_user:synthetic-password@db.example.test/sgsus",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DATABASE_URL", result.stderr)

    def test_production_rejects_the_administrator_database_role(self):
        """Le compte administrateur PostgreSQL est refusé comme rôle applicatif."""
        result = self._import_settings(
            "sgsus.example.test",
            db_user="db_admin",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("distinct", result.stderr)


if __name__ == "__main__":
    unittest.main()
