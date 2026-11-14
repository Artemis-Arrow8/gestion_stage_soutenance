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
  erreur 400 compréhensible.
* F03 : un dossier de stage n'est planifiable en soutenance que si
  l'avis de recevabilité de l'encadreur est favorable (table `review`
  sur la dernière version de document) ou si son statut l'explicite.
* F04/F05 : la salle doit exister et être active, le jury doit exister
  et compter au moins un membre ; un membre de jury ne peut pas siéger
  dans deux soutenances qui se chevauchent, même dans deux jurys différents.
* NFR04 : les créneaux sont normalisés en UTC.

Toutes les fonctions lèvent `rest_framework.exceptions.ValidationError`
(=> HTTP 400 avec un message structuré par champ, exploitable par Flutter).
"""
import datetime as dt
from datetime import datetime, timedelta
from django.db import connection, transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.db.utils import IntegrityError
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework.exceptions import ValidationError

from api.models import (
    Defense,
    DocumentVersion,
    InternshipFolder,
    Jury,
    JuryMember,
    Review,
    Room,
)

# Durée maximale d'une soutenance (garde-fou contre les créneaux absurdes).
DUREE_MAXIMALE = timedelta(hours=8)

# Statuts de dossier qui valident explicitement la recevabilité
# (le statut par défaut du schéma est 'brouillon').
STATUTS_DOSSIER_RECEVABLES = {
    "recevable", "valide", "validee", "validé", "approuve", "approuvee",
    "approuvé", "accepte", "accepté",
}

# Décisions de la table `review` considérées comme favorables
# (vocabulaire du schéma : 'favorable' / 'defavorable').
DECISIONS_FAVORABLES = {"favorable", "recevable", "positif"}

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
    requete = Defense.objects.filter(room_name=room_name, slot_range__overlap=slot)
    if defense_exclue_id:
        requete = requete.exclude(pk=defense_exclue_id)
    conflit = requete.order_by("slot_range").first()
    if conflit is not None:
        raise ValidationError(
            {"room_name": (
                f"Conflit d'horaire (EXG01) : la salle « {room_name} » est déjà "
                f"réservée par la soutenance #{conflit.pk} sur le créneau "
                f"{formater_creneau(conflit.slot_range)}."
            )}
        )
    return conflit


def verifier_conflit_jury(jury_id, slot, defense_exclue_id=None):
    """EXG01 : le jury ne doit pas être engagé sur un créneau chevauchant."""
    requete = Defense.objects.filter(jury_id=jury_id, slot_range__overlap=slot)
    if defense_exclue_id:
        requete = requete.exclude(pk=defense_exclue_id)
    conflit = requete.order_by("slot_range").first()
    if conflit is not None:
        raise ValidationError(
            {"jury": (
                f"Conflit d'horaire (EXG01) : ce jury est déjà engagé dans la "
                f"soutenance #{conflit.pk} sur le créneau "
                f"{formater_creneau(conflit.slot_range)}."
            )}
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
        Defense.objects
        .filter(jury__members__member_name__in=noms_membres,
                slot_range__overlap=slot)
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
        raise ValidationError(
            {"jury": (
                f"Conflit d'horaire (EXG01) : le(s) membre(s) du jury "
                f"« {noms} » siège(nt) déjà dans la soutenance #{conflit.pk} "
                f"(jury « {conflit.jury.name} ») sur le créneau "
                f"{formater_creneau(conflit.slot_range)}."
            )}
        )
    return conflit


def verifier_dossier_recevable(folder_id):
    """
    F03 : le dossier doit être recevable avant planification.

    Deux voies acceptées :
    1. statut de dossier explicitement recevable ;
    2. avis « favorable » de l'encadreur (table review) sur la dernière
       version de document du dossier.
    """
    try:
        dossier = InternshipFolder.objects.get(pk=folder_id)
    except InternshipFolder.DoesNotExist:
        raise ValidationError(
            {"folder": f"Le dossier de stage #{folder_id} n'existe pas."}
        )

    statut = (dossier.status or "").strip().lower()
    if statut in STATUTS_DOSSIER_RECEVABLES:
        return dossier

    derniere_version = (
        DocumentVersion.objects
        .filter(folder_id=folder_id)
        .order_by("-version_number", "-uploaded_at")
        .first()
    )
    if derniere_version is not None:
        avis_favorable = Review.objects.filter(
            document_version_id=derniere_version.pk,
            author_role="encadreur",
            decision__in=DECISIONS_FAVORABLES,
        ).exists()
        if avis_favorable:
            return dossier

    raise ValidationError(
        {"folder": (
            f"Le dossier de stage #{folder_id} ({dossier.company_name}) n'est "
            "pas recevable : l'avis de recevabilité de l'encadreur (F03) est "
            "absent ou défavorable sur la dernière version du document."
        )}
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
    return dossier, jury


# ---------------------------------------------------------------------------
# Traduction des contraintes PostgreSQL (filet de sécurité EXG01, ADR 0002)
# ---------------------------------------------------------------------------

def traduire_integrity_error(erreur):
    """
    Convertit une IntegrityError (contrainte d'exclusion PostgreSQL) en
    ValidationError lisible. Couvre le cas de la course entre deux
    validations applicatives simultanées : la contrainte SQL tranche.
    Retourne None pour les autres erreurs afin qu'elles restent visibles.
    """
    message = str(erreur)
    for nom_contrainte, message_lisible in TRADUCTION_CONTRAINTES.items():
        if nom_contrainte in message:
            return ValidationError({"detail": message_lisible})
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
       l'écriture (concurrence), l'IntegrityError est traduite en erreur 400.

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
