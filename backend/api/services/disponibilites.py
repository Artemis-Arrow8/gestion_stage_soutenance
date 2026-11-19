"""
Indisponibilités récurrentes des membres de jury et des salles (complément
F04, STA09).

Une règle dit « chaque <jour> de <heure> à <heure>, du <date> au <date> »,
dans un fuseau horaire donné (fuseau métier par défaut, réglage
SGSUS_FUSEAU_METIER). Pour comparer avec un créneau de soutenance (stocké en
UTC), on DÉVELOPPE les occurrences de la règle sur l'horizon utile — ici le
créneau lui-même, à un jour près de chaque côté — en les convertissant en
UTC, date par date : le calcul reste juste lors d'un changement d'heure.
Une exception (date précise) annule l'occurrence de ce jour-là.

Une indisponibilité ajoutée APRÈS publication ne déplace ni ne supprime
aucune soutenance : elle produit seulement une ALERTE listant les
soutenances publiées concernées, à traiter par le planificateur.
"""
from datetime import datetime, time, timedelta
from datetime import timezone as dt_timezone
from zoneinfo import ZoneInfo

from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.db.models import Q

from api.exceptions import ConflitMetier
from api.models import Defense, Indisponibilite

# Garde-fou : nombre maximal de jours développés pour une même recherche.
HORIZON_MAX_JOURS = 400


def occurrences(regle, debut, fin):
    """
    Occurrences UTC [début, fin) de `regle` qui chevauchent [debut, fin).

    Paramètres :
        regle (Indisponibilite) : règle avec ses exceptions ;
        debut, fin (datetime aware) : fenêtre de recherche.
    """
    fuseau = ZoneInfo(regle.fuseau)
    exceptions = {exception.date for exception in regle.exceptions.all()}
    # Dates locales candidates (± 1 jour pour couvrir le décalage horaire).
    jour = max(regle.valide_du, debut.astimezone(fuseau).date() - timedelta(days=1))
    dernier = min(regle.valide_au, fin.astimezone(fuseau).date() + timedelta(days=1))
    resultat = []
    developpes = 0
    while jour <= dernier and developpes < HORIZON_MAX_JOURS:
        developpes += 1
        if jour.weekday() == regle.jour_semaine and jour not in exceptions:
            occ_debut = datetime.combine(jour, regle.heure_debut, tzinfo=fuseau)
            occ_fin = datetime.combine(jour, regle.heure_fin, tzinfo=fuseau)
            occ_debut = occ_debut.astimezone(dt_timezone.utc)
            occ_fin = occ_fin.astimezone(dt_timezone.utc)
            # Intervalles semi-ouverts : jointif n'est pas un chevauchement.
            if occ_debut < fin and occ_fin > debut:
                resultat.append((occ_debut, occ_fin))
        jour += timedelta(days=1)
    return resultat


def _regles_candidates(salle, noms_membres, debut, fin):
    """Règles pouvant s'appliquer à la salle ou aux membres sur la période."""
    filtre = Q(type_ressource='salle', ressource=salle)
    if noms_membres:
        filtre |= Q(type_ressource='membre', ressource__in=list(noms_membres))
    return (
        Indisponibilite.objects.filter(filtre)
        .filter(valide_du__lte=(fin + timedelta(days=1)).date(),
                valide_au__gte=(debut - timedelta(days=1)).date())
        .prefetch_related('exceptions')
    )


def _libelle(regle):
    """Description lisible d'une règle (dans son fuseau)."""
    jour = regle.get_jour_semaine_display().lower()
    return (f"{regle.ressource} est indisponible le {jour} de "
            f"{regle.heure_debut:%H:%M} à {regle.heure_fin:%H:%M} "
            f"({regle.fuseau}, du {regle.valide_du:%d/%m/%Y} au {regle.valide_au:%d/%m/%Y})")


def verifier_disponibilites(salle, noms_membres, slot):
    """
    Refuse (409) un créneau qui tombe sur une indisponibilité de la salle
    ou d'un membre du jury.
    """
    debut, fin = slot.lower, slot.upper
    for regle in _regles_candidates(salle, noms_membres, debut, fin):
        if occurrences(regle, debut, fin):
            raise ConflitMetier(
                f"Créneau impossible : {_libelle(regle)}.",
                regle='F04',
                details={'indisponibilite': regle.pk, 'ressource': regle.ressource},
            )


def soutenances_publiees_concernees(regle):
    """
    Soutenances PUBLIÉES qui tombent sur une occurrence de `regle`.

    Sert à l'alerte affichée lors de la création d'une indisponibilité : les
    soutenances ne sont jamais déplacées automatiquement.
    """
    debut = datetime.combine(regle.valide_du, time.min, tzinfo=ZoneInfo(regle.fuseau))
    fin = datetime.combine(regle.valide_au, time.max, tzinfo=ZoneInfo(regle.fuseau))
    requete = Defense.objects.filter(
        status='publie',
        slot_range__overlap=DateTimeTZRange(
            debut.astimezone(dt_timezone.utc), fin.astimezone(dt_timezone.utc), '[)'
        ),
    ).select_related('jury')
    if regle.type_ressource == 'salle':
        requete = requete.filter(room_name=regle.ressource)
    else:
        requete = requete.filter(jury__members__member_name=regle.ressource).distinct()
    concernees = []
    for soutenance in requete:
        creneau = soutenance.slot_range
        if occurrences(regle, creneau.lower, creneau.upper):
            concernees.append(soutenance)
    return concernees
