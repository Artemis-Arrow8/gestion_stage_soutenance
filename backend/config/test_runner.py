"""
Exécuteur de tests personnalisé pour le projet SGSUS.

Les modèles de l'application `api` sont `managed = False` : Django ne crée
pas leurs tables dans la base de test. Cet exécuteur charge donc
`database/schema.sql` (tables + contraintes EXG01) dans la base de test
juste après sa création, afin que les tests d'intégration s'exécutent
exactement comme en production (contraintes d'exclusion PostgreSQL actives).
"""

from pathlib import Path

from django.db import connections
from django.test.runner import DiscoverRunner

# backend/config/test_runner.py -> racine du dépôt = backend/../
BASE_DIR = Path(__file__).resolve().parent.parent
SCHEMA_SQL_PATH = BASE_DIR.parent / "database" / "schema.sql"


class SchemaTestRunner(DiscoverRunner):
    """Charge database/schema.sql dans la base de test avant les tests."""

    def setup_databases(self, **kwargs):
        result = super().setup_databases(**kwargs)

        schema_sql = SCHEMA_SQL_PATH.read_text(encoding="utf-8")
        for alias in connections:
            with connections[alias].cursor() as cursor:
                cursor.execute(schema_sql)

        return result
