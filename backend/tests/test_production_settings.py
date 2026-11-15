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
        result = self._import_settings()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DJANGO_ALLOWED_HOSTS", result.stderr)

    def test_production_accepts_explicit_allowed_hosts(self):
        result = self._import_settings("sgsus.example.test")

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_production_rejects_an_empty_parsed_host_list(self):
        result = self._import_settings(",,,")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DJANGO_ALLOWED_HOSTS", result.stderr)

    def test_production_requires_https_and_secure_cookies(self):
        result = self._import_settings(
            "sgsus.example.test",
            secure_ssl_redirect="False",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DJANGO_SECURE_SSL_REDIRECT", result.stderr)

    def test_production_uses_the_dedicated_database_role(self):
        result = self._import_settings(
            "sgsus.example.test",
            command=(
                "from config.settings import DATABASES; "
                "print(DATABASES['default']['USER'])"
            ),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "sgsus_app_user")

    def test_production_rejects_the_administrator_database_role(self):
        result = self._import_settings(
            "sgsus.example.test",
            db_user="db_admin",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("distinct", result.stderr)


if __name__ == "__main__":
    unittest.main()
