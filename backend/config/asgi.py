"""
Point d'entrée ASGI du projet SGSUS (serveurs asynchrones : Uvicorn, Daphne…).

Le déploiement actuel utilise Gunicorn en mode WSGI (voir `wsgi.py`) ; ce
fichier est conservé pour une éventuelle mise en production asynchrone.
Documentation : https://docs.djangoproject.com/en/stable/howto/deployment/asgi/
"""

import os

from django.core.asgi import get_asgi_application

# Module de configuration utilisé si la variable n'est pas déjà définie.
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

# Application ASGI appelée par le serveur pour chaque requête.
application = get_asgi_application()
