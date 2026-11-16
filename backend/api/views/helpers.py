"""
Fonctions utilitaires partagées par les vues de l'API SGSUS.

Ce module regroupe les petites briques réutilisées par plusieurs ViewSets :
résolution du profil étudiant d'un compte, lecture et validation des
paramètres de date passés dans l'URL, conversion d'une date calendaire en
instant UTC. Les isoler ici évite la duplication entre les modules de vues.
"""

from datetime import datetime, time, timezone as datetime_timezone

from django.utils.dateparse import parse_date
from rest_framework.exceptions import ValidationError

from api.models import Student


def etudiant_du_compte(user):
    """
    Retourne la fiche `Student` associée à un utilisateur, si elle existe.

    Paramètres :
        user : utilisateur Django authentifié (ou directement une instance
            `Student`, cas historique conservé pour compatibilité).

    Retour :
        L'instance `Student` liée via `StudentAccount`, ou `None` si le
        compte n'est rattaché à aucune fiche étudiante.
    """
    # Cas historique : certaines vues manipulaient directement un Student.
    if isinstance(user, Student):
        return user
    # La relation inverse `student_account` n'existe que pour les étudiants.
    account = getattr(user, 'student_account', None)
    return account.student if account else None


def lire_parametre_date(request, nom_parametre, obligatoire=False):
    """
    Lit une date ISO (AAAA-MM-JJ) dans la chaîne de requête et la valide.

    Paramètres :
        request : requête DRF contenant `query_params`.
        nom_parametre (str) : nom du paramètre à lire (ex. « date »).
        obligatoire (bool) : si True, l'absence du paramètre est une erreur.

    Retour :
        Un objet `datetime.date`, ou `None` si le paramètre facultatif est absent.

    Lève :
        ValidationError : paramètre obligatoire manquant ou format invalide
        (traduit en HTTP 400 par DRF, avec le nom du champ en clé).
    """
    valeur = request.query_params.get(nom_parametre)
    if not valeur:
        if obligatoire:
            raise ValidationError({
                nom_parametre: 'Ce paramètre est obligatoire (format YYYY-MM-DD).'
            })
        return None

    # `parse_date` renvoie None si le format est faux et lève ValueError si
    # le format est bon mais la date impossible (ex. 2026-02-30).
    try:
        jour = parse_date(valeur)
    except ValueError:
        jour = None
    if jour is None:
        raise ValidationError({
            nom_parametre: 'Format attendu : YYYY-MM-DD.'
        })
    return jour


def debut_jour_utc(jour):
    """
    Convertit une date calendaire en instant « minuit UTC » de ce jour.

    Paramètres :
        jour (datetime.date) : date à convertir.

    Retour :
        Un `datetime` conscient du fuseau (tzinfo=UTC) à 00:00:00.
        Les créneaux étant stockés en UTC (exigence NFR04), cette borne
        permet de filtrer les soutenances d'une journée de façon cohérente.
    """
    return datetime.combine(jour, time.min, tzinfo=datetime_timezone.utc)
