"""
Vues « système » exposées à la racine du service web.

La racine `/` renvoyait auparavant une erreur 404, car seules `/admin/` et
`/api/` étaient routées. Elle renvoie désormais une page d'accueil JSON qui
décrit le service et indique les points d'entrée utiles. Cette vue est
publique et ne divulgue aucune donnée métier.
"""

from django.http import JsonResponse
from django.views.decorators.http import require_safe

# Nom et version affichés par la page d'accueil (informationnels).
NOM_SERVICE = 'SGSUS API'
VERSION_API = '1.0'


@require_safe
def accueil(request):
    """
    Page d'accueil JSON de l'API (route `/`).

    Paramètres :
        request (HttpRequest) : requête GET ou HEAD (les autres méthodes
            reçoivent automatiquement un 405 grâce à `require_safe`).

    Retour :
        JsonResponse 200 contenant le nom du service, sa version et les URL
        absolues de l'API, de l'administration et de la sonde de santé.
    """
    return JsonResponse({
        'service': NOM_SERVICE,
        'version': VERSION_API,
        'status': 'ok',
        'message': (
            "Bienvenue sur l'API de gestion des stages et des soutenances. "
            'Les routes métier sont servies sous /api/ et nécessitent un jeton JWT.'
        ),
        # `build_absolute_uri` tient compte du schéma HTTPS derrière le proxy.
        'endpoints': {
            'api': request.build_absolute_uri('/api/'),
            'login': request.build_absolute_uri('/api/login/'),
            'admin': request.build_absolute_uri('/admin/'),
            'health': request.build_absolute_uri('/health/'),
        },
    # Accents affichés tels quels (et non sous forme é) pour la lisibilité.
    }, json_dumps_params={'ensure_ascii': False})
