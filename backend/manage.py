#!/usr/bin/env python
"""
Utilitaire en ligne de commande de Django pour le projet SGSUS.

Exemples d'utilisation (depuis le dossier backend/) :
    python manage.py runserver 127.0.0.1:8001   # serveur de développement
    python manage.py migrate                    # appliquer les migrations
    python manage.py test                       # lancer les tests
    python manage.py createsuperuser            # créer un administrateur
"""
import os
import sys


def main():
    """Configure Django puis exécute la commande passée en argument."""
    # Module de configuration utilisé si la variable n'est pas déjà définie.
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        # Django absent : environnement virtuel non activé ou dépendances
        # non installées (pip install -r requirements-dev.txt).
        raise ImportError(
            "Impossible d'importer Django. Vérifiez qu'il est installé et "
            "accessible (environnement virtuel activé ?)."
        ) from exc
    execute_from_command_line(sys.argv)


if __name__ == '__main__':
    main()
