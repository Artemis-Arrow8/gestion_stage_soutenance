"""
Configuration pytest commune à tout le backend.

Le cache (utilisé par la limitation des tentatives de connexion) est vidé
avant chaque test : les nombreuses connexions de la suite de tests ne
doivent pas déclencher la protection anti-force brute d'un test à l'autre.
"""
import pytest
from django.core.cache import cache


@pytest.fixture(autouse=True)
def vider_le_cache():
    """Repart d'un cache vide pour chaque test."""
    cache.clear()
    yield
