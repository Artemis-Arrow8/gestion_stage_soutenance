"""
Configuration pytest du module planification (Tâche 4).

Tous les modèles sont `managed = False` : Django ne crée aucune table dans la
base de test. On charge donc `database/schema.sql` (source de vérité du
groupe, contraintes d'exclusion EXG01 comprises) dans la base de test avant
le premier test qui touche la base.

Prérequis : PostgreSQL (jamais SQLite : tstzrange et les contraintes
d'exclusion n'existent que dans PostgreSQL) et le droit de créer l'extension
btree_gist (propriétaire de la base de test suffisant depuis PostgreSQL 13).

Variable optionnelle : SCHEMA_SQL pour pointer vers un autre fichier.
"""

import os
from pathlib import Path

import pytest
from django.db import connection

from .factories import SALLES_DEMO

SCHEMA_SQL = Path(
    os.environ.get(
        "SCHEMA_SQL",
        Path(__file__).resolve().parents[2] / "database" / "schema.sql",
    )
)

TABLES_A_VIDER = (
    "assessment, defense, jury_member, jury, review, "
    "document_version, internship_folder, student, campaign"
)


@pytest.fixture(scope="session")
def django_db_setup(django_db_setup, django_db_blocker):
    """Charge schema.sql dans la base de test (tables non gérées par Django)."""
    if not SCHEMA_SQL.exists():
        pytest.fail(
            f"schema.sql introuvable : {SCHEMA_SQL}. "
            "Définissez SCHEMA_SQL ou vérifiez l'arborescence du dépôt."
        )
    with django_db_blocker.unblock():
        with connection.cursor() as curseur:
            curseur.execute(SCHEMA_SQL.read_text(encoding="utf-8"))


def _vider_tables():
    with connection.cursor() as curseur:
        curseur.execute(f"TRUNCATE {TABLES_A_VIDER} RESTART IDENTITY CASCADE")


@pytest.fixture
def base_propre(transactional_db):
    """
    Pour les tests avec transaction réelle (concurrence) : les tables non
    gérées ne sont pas vidées par Django, on le fait ici avant et après.
    Le catalogue des salles n'est jamais vidé.
    """
    _vider_tables()
    yield
    _vider_tables()


@pytest.fixture
def salles_demo(db):
    """Garantit la présence des salles de démonstration du schéma."""
    from api.models import Room

    for nom, capacite in SALLES_DEMO:
        Room.objects.get_or_create(
            name=nom, defaults={"capacity": capacite, "is_active": True}
        )
