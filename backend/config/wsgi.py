"""
Point d'entrée WSGI du projet SGSUS.

C'est ce fichier que Gunicorn charge en production
(`gunicorn config.wsgi:application`, voir backend/entrypoint.sh).
Documentation : https://docs.djangoproject.com/en/stable/howto/deployment/wsgi/
"""

import os

from django.core.wsgi import get_wsgi_application

# Module de configuration utilisé si la variable n'est pas déjà définie.
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

# Application WSGI appelée par Gunicorn pour chaque requête.
application = get_wsgi_application()
