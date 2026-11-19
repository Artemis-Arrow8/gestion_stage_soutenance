"""
Idempotence des opérations sensibles (chapitre 6 du dossier).

Le client envoie un en-tête `Idempotency-Key` qui désigne une OPÉRATION
LOGIQUE (et non une tentative réseau) : si la réponse s'est perdue, il
renvoie la même demande avec la même clé et obtient le même résultat, sans
second effet métier (pas de deuxième version de planning, par exemple).

* même clé + même contenu → réponse mémorisée rejouée ;
* même clé + contenu différent → refus 409 ;
* sans clé → l'opération s'exécute normalement (compatibilité).

Le périmètre (opération + compte), l'empreinte SHA-256 de la demande et la
réponse sont enregistrés dans la MÊME transaction que l'opération : soit
tout est confirmé, soit rien.
"""
import hashlib
import json

from django.db import IntegrityError, transaction
from rest_framework.response import Response

from api.exceptions import ConflitMetier
from api.models import CleIdempotence

# Longueur maximale acceptée pour une clé fournie par le client.
LONGUEUR_MAX_CLE = 100


def _empreinte(donnees):
    """Empreinte stable (SHA-256) du contenu de la demande."""
    texte = json.dumps(donnees, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(texte.encode('utf-8')).hexdigest()


def executer_idempotent(request, operation, fonction):
    """
    Exécute `fonction()` (qui renvoie une Response DRF) de façon idempotente.

    Paramètres :
        request : requête DRF (en-tête Idempotency-Key, données, compte) ;
        operation (str) : nom stable de l'opération (ex. « planning.publier ») ;
        fonction : callable sans argument produisant la Response.
    """
    cle = (request.headers.get('Idempotency-Key') or '').strip()
    if not cle:
        return fonction()
    if len(cle) > LONGUEUR_MAX_CLE:
        cle = cle[:LONGUEUR_MAX_CLE]
    perimetre = f'{operation}:{request.user.pk}'
    empreinte = _empreinte(request.data)

    existante = CleIdempotence.objects.filter(cle=cle, perimetre=perimetre).first()
    if existante is not None:
        return _rejouer(existante, empreinte)

    try:
        with transaction.atomic():
            reponse = fonction()
            # Seuls les succès sont mémorisés : un refus peut être retenté
            # avec la même clé après correction (même contenu).
            if 200 <= reponse.status_code < 300:
                CleIdempotence.objects.create(
                    cle=cle, perimetre=perimetre, empreinte=empreinte,
                    code_http=reponse.status_code, reponse=reponse.data,
                )
            return reponse
    except IntegrityError:
        # Deux envois simultanés de la même clé : le second relit le premier.
        existante = CleIdempotence.objects.filter(cle=cle, perimetre=perimetre).first()
        if existante is None:
            raise
        return _rejouer(existante, empreinte)


def _rejouer(existante, empreinte):
    """Rejoue la réponse mémorisée, ou refuse une clé réutilisée autrement."""
    if existante.empreinte != empreinte:
        raise ConflitMetier(
            "Cette clé d'idempotence a déjà servi pour une demande différente.",
            regle='IDEMPOTENCE',
        )
    reponse = Response(existante.reponse, status=existante.code_http)
    reponse['Idempotent-Replayed'] = 'true'
    return reponse
