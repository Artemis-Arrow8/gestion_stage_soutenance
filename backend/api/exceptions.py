"""
Erreurs métier de l'API SGSUS et format commun des réponses d'erreur.

Convention du contrat d'API (docs/api.md, chapitre 6 du dossier) :

* 400 : donnée mal formée ou invalide (format DRF habituel, par champ) ;
* 403 : action interdite pour le rôle de l'appelant ;
* 404 : objet inexistant OU hors du périmètre de l'appelant (on ne révèle
  pas l'existence d'un dossier que l'on n'a pas le droit de voir) ;
* 409 : CONFLIT MÉTIER — la demande est bien formée mais une règle l'interdit
  dans l'état actuel (créneau déjà pris, dossier non recevable, note déjà
  approuvée, étape sautée…). Le corps suit toujours la même forme :

      {"code": "BUSINESS_CONFLICT", "regle": "EXG01",
       "message": "…", "request_id": "…", "details": {…}}

`request_id` est l'identifiant de la requête (en-tête X-Request-ID), aussi
présent dans les journaux du serveur : il permet de retrouver l'incident.
"""
from django.db.models import ProtectedError
from rest_framework.exceptions import APIException
from rest_framework.views import exception_handler

from api.journalisation import request_id_courant


class ConflitMetier(APIException):
    """
    Refus d'une opération par une règle métier (HTTP 409).

    Paramètres :
        message (str) : explication lisible par l'utilisateur, en français ;
        regle (str) : identifiant de la règle violée (EXG01, F03, STA06…),
            pour relier le refus au cahier des charges ;
        details (dict | None) : informations complémentaires sans données
            confidentielles (ex. {"champ": "room_name", "soutenance": 12}).
    """

    status_code = 409
    default_code = 'BUSINESS_CONFLICT'
    default_detail = 'Cette opération ne peut plus être validée.'

    def __init__(self, message=None, regle=None, details=None):
        super().__init__(detail=message or self.default_detail)
        self.regle = regle
        self.details = details or {}


def gestionnaire_exceptions(exc, context):
    """
    Gestionnaire d'exceptions DRF du projet (settings EXCEPTION_HANDLER).

    * Les conflits métier reçoivent l'enveloppe {code, regle, message,
      request_id, details}.
    * Les autres erreurs gardent le format DRF habituel (compatibilité avec
      l'application Flutter et les tests existants).
    * Toute réponse d'erreur porte l'en-tête X-Request-ID.
    """
    if isinstance(exc, ProtectedError):
        # Suppression d'un objet dont dépendent des données validées
        # (historique, procès-verbal, convocation) : on la refuse (409).
        exc = ConflitMetier(
            "Suppression impossible : des données validées (historique, "
            "procès-verbal ou convocation) dépendent de cet élément. "
            "Annulez-le ou désactivez-le plutôt.",
            regle='HISTORIQUE',
        )
    reponse = exception_handler(exc, context)
    if reponse is None:
        # Erreur non gérée par DRF (500) : Django la journalise lui-même.
        return None
    if isinstance(exc, ConflitMetier):
        reponse.data = {
            'code': exc.default_code,
            'regle': exc.regle,
            'message': str(exc.detail),
            'request_id': request_id_courant(),
            'details': exc.details,
        }
    reponse['X-Request-ID'] = request_id_courant()
    return reponse
