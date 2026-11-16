"""
Routage racine du projet SGSUS.

    /         -> page d'accueil JSON de l'API (corrige l'ancienne erreur 404)
    /admin/   -> site d'administration Django
    /api/     -> API REST (voir `api/urls.py`)
    /health/  -> sonde de santé, traitée par `api.middleware.HealthCheckMiddleware`
                 avant le routage (elle n'apparaît donc pas ci-dessous).
"""

from django.contrib import admin
from django.urls import include, path

from api.views import accueil

urlpatterns = [
    # Racine : description du service et liens vers les points d'entrée.
    path('', accueil, name='accueil'),
    # Administration Django (comptes, liaisons étudiant/jury/encadreur).
    path('admin/', admin.site.urls),
    # API REST consommée par le client Flutter.
    path('api/', include('api.urls')),
]
