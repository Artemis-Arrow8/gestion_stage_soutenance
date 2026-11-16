"""
Middlewares spécifiques au projet SGSUS.

`HealthCheckMiddleware` répond à la sonde de santé /health/ AVANT tous les
autres middlewares. C'est indispensable en production :
    * la sonde interne de Render (ou de Docker) peut arriver avec un en-tête
      `Host` égal à l'IP interne du conteneur, que `ALLOWED_HOSTS` rejetterait
      (erreur 400 DisallowedHost) ;
    * elle arrive en HTTP simple, que `SECURE_SSL_REDIRECT` redirigerait (301)
      vers HTTPS au lieu de répondre.
En court-circuitant la chaîne pour ce seul chemin, la sonde reçoit toujours
une réponse JSON fiable (200 ou 503), sans affaiblir la sécurité du reste
de l'application.
"""

from django.http import JsonResponse

from api.services.sante import verifier_sante

# Chemins acceptés pour la sonde (avec ou sans barre oblique finale).
CHEMINS_SANTE = frozenset({'/health', '/health/'})


class HealthCheckMiddleware:
    """
    Intercepte les requêtes GET/HEAD vers /health/ et renvoie l'état du service.

    Toute autre requête est transmise sans modification au middleware suivant.
    Doit être placé en tête de `settings.MIDDLEWARE`.
    """

    def __init__(self, get_response):
        """
        Paramètres :
            get_response : callable fourni par Django, qui invoque la suite
                de la chaîne de middlewares puis la vue.
        """
        self.get_response = get_response

    def __call__(self, request):
        """
        Traite une requête HTTP.

        Paramètres :
            request (HttpRequest) : requête entrante.

        Retour :
            JsonResponse pour la sonde de santé, sinon la réponse normale
            produite par le reste de l'application.
        """
        # `path_info` exclut un éventuel préfixe SCRIPT_NAME.
        if request.path_info in CHEMINS_SANTE and request.method in ('GET', 'HEAD'):
            corps, code_http = verifier_sante()
            reponse = JsonResponse(corps, status=code_http)
            # Une sonde ne doit jamais être servie depuis un cache intermédiaire.
            reponse['Cache-Control'] = 'no-store'
            return reponse
        return self.get_response(request)
