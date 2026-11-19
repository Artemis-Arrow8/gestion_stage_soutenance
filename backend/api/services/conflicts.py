"""
Service métier de contrôle des conflits — Tâche 4 (module planification).

Implémente les règles du cahier des charges et de l'ADR 0002
("Gestion de la concurrence") :

* EXG01 : interdiction absolue de chevauchement d'horaires pour une même
  salle ou un même membre du jury. La garantie ultime est assurée par les
  contraintes d'exclusion PostgreSQL (`prevent_room_double_booking` et
  `prevent_jury_double_booking` sur la table `defense`, voir
  `database/schema.sql`) ; ce service effectue le même contrôle au niveau
  applicatif afin de renvoyer à l'utilisateur des messages lisibles, puis
  traduit une éventuelle `IntegrityError` (course entre deux requêtes) en
  conflit métier 409 compréhensible. Les soutenances ANNULÉES ne réservent
  plus rien.
* STA02 : une marge de déplacement (SGSUS_MARGE_MINUTES, 0 par défaut)
  peut être imposée entre deux soutenances d'une même ressource ; avec une
  marge nulle, deux créneaux jointifs (9 h-10 h puis 10 h-11 h) sont acceptés.
* F03 : un dossier n'est planifiable que s'il est au statut « recevable »,
  atteint par l'autorisation du responsable (api/services/dossiers.py).
* F04/F05 : la salle doit exister et être active, le jury doit exister
  et compter au moins un membre ; un membre de jury ne peut pas siéger
  dans deux soutenances qui se chevauchent, même dans deux jurys
  différents ; les indisponibilités récurrentes sont respectées.
* NFR04 : les créneaux sont normalisés en UTC.

Erreurs : une donnée mal formée (date, salle inconnue) lève une
`ValidationError` (HTTP 400) ; une règle métier violée lève un
`ConflitMetier` (HTTP 409, voir api/exceptions.py).
"""
import datetime as dt
from datetime import datetime, timedelta

from django.conf import settings
from django.db import connection, transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.db.utils import IntegrityError
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.exceptions import ValidationError

from api.exceptions import ConflitMetier
from api.models import (
    Defense,
    InternshipFolder,
    Jury,
    JuryMember,
    Room,
)
from api.services.disponibilites import verifier_disponibilites

# Durée maximale d'une soutenance (garde-fou contre les créneaux absurdes).
DUREE_MAXIMALE = timedelta(hours=8)

# Seul statut de dossier planifiable (F03) : il est atteint par l'événement
# « autoriser la soutenance », qui exige l'avis favorable de l'encadreur.
STATUT_RECEVABLE = "recevable"

# Statut d'une soutenance qui ne réserve plus ni salle ni jury.
STATUT_ANNULE = "annule"

# Traduction lisible des contraintes EXG01 du schéma PostgreSQL.
TRADUCTION_CONTRAINTES = {
    "prevent_room_double_booking": (
        "Conflit d'horaire : cette salle est déjà réservée pour une autre "
        "soutenance sur ce créneau (règle EXG01)."
    ),
    "prevent_jury_double_booking": (
        "Conflit d'horaire : ce jury est déjà engagé dans une autre "
        "soutenance sur ce créneau (règle EXG01)."
    ),
}


# ---------------------------------------------------------------------------
# Normalisation des créneaux (NFR04 : tout est stocké/converti en UTC)
# ---------------------------------------------------------------------------

def _normaliser_datetime(valeur, nom_champ):
    """Convertit une valeur en datetime aware UTC ; sinon ValidationError."""
    if isinstance(valeur, str):
        parse = parse_datetime(valeur)
        if parse is None:
            raise ValidationError(
                {nom_champ: f"Format de date invalide : « {valeur} ». "
                            "Utilisez le format ISO 8601 (ex. 2026-07-10T08:00:00Z)."}
            )
        valeur = parse
    if not isinstance(valeur, datetime):
        raise ValidationError({nom_champ: "Date/heure invalide."})
    if timezone.is_naive(valeur):
        # Un créneau saisi sans fuseau est interprété comme UTC (NFR04).
        valeur = valeur.replace(tzinfo=dt.timezone.utc)
    return valeur.astimezone(dt.timezone.utc)


def construire_creneau(debut, fin):
    """
    Valide et normalise un créneau [debut, fin) ; retourne un
    `DateTimeTZRange` UTC (bornes [debut, fin) comme tstzrange PostgreSQL).
    """
    debut = _normaliser_datetime(debut, "slot_start")
    fin = _normaliser_datetime(fin, "slot_end")
    if fin <= debut:
        raise ValidationError(
            {"slot_end": "La fin du créneau doit être strictement postérieure "
                         "au début de la soutenance."}
        )
    if fin - debut > DUREE_MAXIMALE:
        raise ValidationError(
            {"slot_end": "La durée maximale d'une soutenance est de 8 heures."}
        )
    return DateTimeTZRange(debut, fin, bounds="[)")


def formater_creneau(slot_range):
    """Représentation lisible d'un créneau pour les messages d'erreur."""
    debut = slot_range.lower
    fin = slot_range.upper
    if isinstance(debut, datetime) and isinstance(fin, datetime):
        return (f"{debut:%d/%m/%Y %H:%M} → {fin:%H:%M} UTC")
    return str(slot_range)


def creneau_avec_marge(slot):
    """
    Élargit le créneau de la marge de déplacement (STA02) pour la recherche
    de conflits : avec une marge de 15 min, 10 h-11 h entre en conflit avec
    une soutenance qui finit à 10 h. Marge nulle : créneau inchangé.
    """
    marge = timedelta(minutes=getattr(settings, "SGSUS_MARGE_MINUTES", 0))
    if not marge:
        return slot
    return DateTimeTZRange(slot.lower - marge, slot.upper + marge, bounds="[)")


def _soutenances_actives():
    """Soutenances qui réservent une ressource (toutes sauf annulées)."""
    return Defense.objects.exclude(status=STATUT_ANNULE)


# ---------------------------------------------------------------------------
# Contrôles métier individuels
# ---------------------------------------------------------------------------

def verifier_salle_existe_et_active(room_name):
    """F04/F05 : la salle référencée doit exister et être active."""
    salle = Room.objects.filter(name=room_name).first()
    if salle is None:
        raise ValidationError(
            {"room_name": f"La salle « {room_name} » n'existe pas dans le "
                          "catalogue des salles."}
        )
    if not salle.is_active:
        raise ValidationError(
            {"room_name": f"La salle « {room_name} » est inactive et ne peut "
                          "pas être réservée."}
        )
    return salle


def verifier_conflit_salle(room_name, slot, defense_exclue_id=None):
    """EXG01 : la salle ne doit pas être occupée sur un créneau chevauchant."""
    requete = _soutenances_actives().filter(
        room_name=room_name, slot_range__overlap=creneau_avec_marge(slot)
    )
    if defense_exclue_id:
        requete = requete.exclude(pk=defense_exclue_id)
    conflit = requete.order_by("slot_range").first()
    if conflit is not None:
        # Le message identifie la ressource et la soutenance, sans détail
        # sur le dossier (qui peut être hors du périmètre de l'appelant).
        raise ConflitMetier(
            f"Conflit d'horaire (EXG01) : la salle « {room_name} » est déjà "
            f"réservée par la soutenance #{conflit.pk} sur le créneau "
            f"{formater_creneau(conflit.slot_range)}.",
            regle="EXG01",
            details={"champ": "room_name", "soutenance": conflit.pk},
        )
    return conflit


def verifier_conflit_jury(jury_id, slot, defense_exclue_id=None):
    """EXG01 : le jury ne doit pas être engagé sur un créneau chevauchant."""
    requete = _soutenances_actives().filter(
        jury_id=jury_id, slot_range__overlap=creneau_avec_marge(slot)
    )
    if defense_exclue_id:
        requete = requete.exclude(pk=defense_exclue_id)
    conflit = requete.order_by("slot_range").first()
    if conflit is not None:
        raise ConflitMetier(
            f"Conflit d'horaire (EXG01) : ce jury est déjà engagé dans la "
            f"soutenance #{conflit.pk} sur le créneau "
            f"{formater_creneau(conflit.slot_range)}.",
            regle="EXG01",
            details={"champ": "jury", "soutenance": conflit.pk},
        )
    return conflit


def verifier_conflit_membres_jury(jury_id, slot, defense_exclue_id=None):
    """
    EXG01 : aucun membre du jury ne peut siéger, sur un même créneau, dans
    une autre soutenance (même via un second jury auquel il appartient).
    """
    noms_membres = list(
        JuryMember.objects.filter(jury_id=jury_id)
        .values_list("member_name", flat=True)
    )
    if not noms_membres:
        raise ValidationError(
            {"jury": "Ce jury ne compte aucun membre : "
                     "constituez-le avant de planifier une soutenance (F04)."}
        )
    # Défenses chevauchant le créneau dont le jury contient l'un des membres
    # du jury considéré, hors les défenses du jury lui-même (déjà couvertes
    # par verifier_conflit_jury) et hors la défense en cours de modification.
    requete = (
        _soutenances_actives()
        .filter(jury__members__member_name__in=noms_membres,
                slot_range__overlap=creneau_avec_marge(slot))
        .exclude(jury_id=jury_id)
    )
    if defense_exclue_id:
        requete = requete.exclude(pk=defense_exclue_id)
    conflit = requete.distinct().order_by("slot_range").first()
    if conflit is not None:
        membres_en_conflit = list(
            conflit.jury.members.filter(member_name__in=noms_membres)
            .values_list("member_name", flat=True)
        )
        noms = ", ".join(sorted(membres_en_conflit))
        raise ConflitMetier(
            f"Conflit d'horaire (EXG01) : le(s) membre(s) du jury "
            f"« {noms} » siège(nt) déjà dans la soutenance #{conflit.pk} "
            f"(jury « {conflit.jury.name} ») sur le créneau "
            f"{formater_creneau(conflit.slot_range)}.",
            regle="EXG01",
            details={"champ": "jury", "soutenance": conflit.pk},
        )
    return conflit


def verifier_dossier_recevable(folder_id):
    """
    F03 : le dossier doit être au statut « recevable » avant planification
    ou publication (« un étudiant non recevable ne peut être publié »).

    Ce statut n'est atteint que par l'autorisation du responsable, qui
    exige l'avis favorable de l'encadreur sur la DERNIÈRE version ; un
    nouveau dépôt fait repasser le dossier à « soumis » (STA05).
    """
    try:
        dossier = InternshipFolder.objects.get(pk=folder_id)
    except InternshipFolder.DoesNotExist:
        raise ValidationError(
            {"folder": f"Le dossier de stage #{folder_id} n'existe pas."}
        )
    if (dossier.status or "").strip().lower() == STATUT_RECEVABLE:
        return dossier
    raise ConflitMetier(
        f"Le dossier de stage #{folder_id} n'est pas recevable (statut "
        f"« {dossier.status} ») : la soutenance doit d'abord être autorisée "
        "par le responsable des stages, après l'avis favorable de l'encadreur (F03).",
        regle="F03",
        details={"champ": "folder", "dossier": dossier.pk},
    )


def verifier_toutes_regles(folder_id, jury_id, room_name, slot,
                           defense_exclue_id=None):
    """
    Exécute l'ensemble des contrôles applicatifs avant une création ou une
    modification de soutenance. Retourne le dossier validé.
    """
    dossier = verifier_dossier_recevable(folder_id)

    try:
        jury = Jury.objects.get(pk=jury_id)
    except Jury.DoesNotExist:
        raise ValidationError({"jury": f"Le jury #{jury_id} n'existe pas."})

    verifier_salle_existe_et_active(room_name)
    verifier_conflit_salle(room_name, slot, defense_exclue_id)
    verifier_conflit_jury(jury_id, slot, defense_exclue_id)
    verifier_conflit_membres_jury(jury_id, slot, defense_exclue_id)
    # Indisponibilités récurrentes de la salle et des membres (STA09).
    noms_membres = jury.members.values_list("member_name", flat=True)
    verifier_disponibilites(room_name, noms_membres, slot)
    return dossier, jury


# ---------------------------------------------------------------------------
# Traduction des contraintes PostgreSQL (filet de sécurité EXG01, ADR 0002)
# ---------------------------------------------------------------------------

def traduire_integrity_error(erreur):
    """
    Convertit une IntegrityError (contrainte d'exclusion PostgreSQL) en
    conflit métier lisible (409). Couvre le cas de la course entre deux
    validations applicatives simultanées : la contrainte SQL tranche.
    Retourne None pour les autres erreurs afin qu'elles restent visibles.
    """
    message = str(erreur)
    for nom_contrainte, message_lisible in TRADUCTION_CONTRAINTES.items():
        if nom_contrainte in message:
            return ConflitMetier(message_lisible, regle="EXG01",
                                 details={"contrainte": nom_contrainte})
    return None


# ---------------------------------------------------------------------------
# Orchestration : planification / modification dans une transaction atomique
# ---------------------------------------------------------------------------

@transaction.atomic
def planifier_soutenance(folder_id, jury_id, room_name, debut, fin,
                         status="planifie", defense_id=None):
    """
    Crée (defense_id=None) ou modifie (defense_id=<pk>) une soutenance :

    1. contrôle applicatif complet (dossier recevable, salle, jury, membres) ;
    2. écriture dans une transaction atomique ;
    3. si la contrainte d'exclusion PostgreSQL rejette tout de même
       l'écriture (concurrence), l'IntegrityError est traduite en conflit 409.

    Retourne l'instance `Defense` enregistrée.
    """
    slot = construire_creneau(debut, fin)
    # Le verrou transactionnel protège aussi les membres partagés entre jurys.
    with connection.cursor() as cursor:
        cursor.execute("SELECT pg_advisory_xact_lock(%s, %s)", [0x534753, 1])
    verifier_toutes_regles(folder_id, jury_id, room_name, slot,
                           defense_exclue_id=defense_id)
    try:
        with transaction.atomic():
            if defense_id is None:
                defense = Defense.objects.create(
                    folder_id=folder_id,
                    jury_id=jury_id,
                    room_name=room_name,
                    slot_range=slot,
                    status=status or "planifie",
                )
            else:
                defense = Defense.objects.get(pk=defense_id)
                defense.folder_id = folder_id
                defense.jury_id = jury_id
                defense.room_name = room_name
                defense.slot_range = slot
                if status:
                    defense.status = status
                defense.save()
    except IntegrityError as erreur:
        erreur_traduite = traduire_integrity_error(erreur)
        if erreur_traduite is None:
            raise
        raise erreur_traduite from erreur
    return defense
