"""
Service de diagnostic de l'état de santé du backend.

Utilisé par le middleware `HealthCheckMiddleware` (route /health/) afin que
Render, Docker Compose ou un outil de supervision sachent si l'instance est
réellement capable de servir des requêtes, base de données comprise.
"""

import logging

from django.db import connection

# Journalise les pannes de base sans exposer leur détail au client HTTP.
logger = logging.getLogger(__name__)


def verifier_sante():
    """
    Vérifie que l'application et sa base PostgreSQL répondent.

    Retour :
        tuple (dict, int) :
            * le corps JSON à renvoyer (`status`, `database`) ;
            * le code HTTP : 200 si tout va bien, 503 si la base est
              injoignable (Render considère alors l'instance comme non prête).
    """
    try:
        # Requête minimale : ouvre (ou réutilise) la connexion et l'exerce.
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            cursor.fetchone()
    except Exception:  # noqa: BLE001 - toute panne de base rend l'instance indisponible
        # Le détail (hôte, utilisateur…) reste dans les journaux serveur.
        logger.exception('Contrôle de santé : base de données injoignable.')
        return {'status': 'error', 'database': 'unavailable'}, 503
    return {'status': 'ok', 'database': 'ok'}, 200
