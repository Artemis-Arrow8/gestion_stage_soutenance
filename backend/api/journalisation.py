"""
Journalisation structurée de SGSUS (chapitre 20 du dossier : « observer le
service »).

* Chaque requête HTTP reçoit un identifiant (`request_id`), repris de
  l'en-tête X-Request-ID s'il est fourni et valide, sinon généré. Il est
  renvoyé au client et ajouté à chaque ligne de journal produite pendant la
  requête : une erreur affichée à l'utilisateur se retrouve ainsi dans les
  journaux.
* Les journaux sont écrits en JSON, une ligne par événement : date, niveau,
  journal, request_id, message (et code d'erreur éventuel).
* Deux journaux distincts : le journal TECHNIQUE (Django, erreurs) et le
  journal MÉTIER `sgsus.metier` (transitions de dossier, publication du
  planning, approbation des notes…). Aucun mot de passe, jeton ni contenu de
  document n'y est écrit.
"""
import contextvars
import json
import logging
import re
import uuid

# Identifiant de la requête en cours (isolé par requête, même en parallèle).
_request_id = contextvars.ContextVar('request_id', default='-')

# Un identifiant fourni par le client doit rester court et inoffensif.
_FORMAT_ID_VALIDE = re.compile(r'^[A-Za-z0-9_-]{1,64}$')

# Journal des événements métier (séparé du journal technique).
journal_metier = logging.getLogger('sgsus.metier')


def request_id_courant():
    """Retourne l'identifiant de la requête en cours (« - » hors requête)."""
    return _request_id.get()


def tracer_evenement(evenement, **contexte):
    """
    Écrit un événement dans le journal métier.

    Paramètres :
        evenement (str) : nom stable de l'événement (ex. « planning.publie ») ;
        contexte : identifiants utiles (dossier, version, acteur…), jamais de
            données sensibles ni de contenu de document.
    """
    journal_metier.info(evenement, extra={'contexte': contexte})


class RequestIdMiddleware:
    """
    Attribue un identifiant à chaque requête et le renvoie dans l'en-tête
    X-Request-ID de la réponse.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        fourni = request.headers.get('X-Request-ID', '')
        identifiant = (
            fourni if _FORMAT_ID_VALIDE.match(fourni) else uuid.uuid4().hex[:16]
        )
        request.request_id = identifiant
        jeton = _request_id.set(identifiant)
        try:
            reponse = self.get_response(request)
        finally:
            _request_id.reset(jeton)
        reponse['X-Request-ID'] = identifiant
        return reponse


class FiltreRequestId(logging.Filter):
    """Ajoute `request_id` à chaque enregistrement de journal."""

    def filter(self, record):
        record.request_id = _request_id.get()
        return True


class FormateurJson(logging.Formatter):
    """Formate un enregistrement en une ligne JSON lisible par une machine."""

    def format(self, record):
        donnees = {
            'date': self.formatTime(record, '%Y-%m-%dT%H:%M:%S%z'),
            'niveau': record.levelname,
            'journal': record.name,
            'request_id': getattr(record, 'request_id', '-'),
            'message': record.getMessage(),
        }
        # Contexte métier éventuel (identifiants seulement).
        contexte = getattr(record, 'contexte', None)
        if contexte:
            donnees['contexte'] = contexte
        # Code HTTP des erreurs de requête (journal django.request).
        code = getattr(record, 'status_code', None)
        if code:
            donnees['code_http'] = code
        if record.exc_info:
            donnees['exception'] = self.formatException(record.exc_info)
        return json.dumps(donnees, ensure_ascii=False, default=str)
