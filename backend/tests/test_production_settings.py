import os
from pathlib import Path
import subprocess
import sys
import unittest


BACKEND_DIR = Path(__file__).resolve().parents[1]


class ProductionSettingsTests(unittest.TestCase):
    # L'import isolé vérifie les réglages sans ouvrir de connexion PostgreSQL.
    def _import_settings(self, allowed_hosts=None):
        environment = os.environ.copy()
        environment.update(
            {
                "DJANGO_DEBUG": "False",
                "DJANGO_SECRET_KEY": (
                    "synthetic-test-secret-key-that-is-at-least-fifty-characters-long"
                ),
                "POSTGRES_PASSWORD": "synthetic-test-database-password",
            }
        )
        environment["DJANGO_ALLOWED_HOSTS"] = ""
        if allowed_hosts is not None:
            environment["DJANGO_ALLOWED_HOSTS"] = allowed_hosts

        return subprocess.run(
            [sys.executable, "-c", "import config.settings"],
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


if __name__ == "__main__":
    unittest.main()
