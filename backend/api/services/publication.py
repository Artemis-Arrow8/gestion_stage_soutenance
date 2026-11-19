"""
Cycle de vie des soutenances et publication du planning (F04, F05, STA07).

États : planifie (proposée) → confirme → publie → termine (tenue) ;
reporte (créneau modifié après publication) ; annule.

* CONFIRMER (personnel) : exige un dossier recevable et un jury COMPLET
  (critère F04 : « le jury incomplet ne peut être confirmé »).
* PUBLIER (personnel) : dans UNE transaction, sous le même verrou que la
  planification, on revérifie chaque soutenance confirmée ou reportée
  (recevabilité, jury complet, conflits EXG01, indisponibilités), puis on
  fige une nouvelle VersionPlanning et on produit les convocations. Au
  moindre problème, rien n'est écrit (pas de publication partielle).
  Les anciennes convocations d'une soutenance republiée passent à
  « remplacee » avec un lien vers la nouvelle (STA07).
* REPORTER (personnel) : modifie le créneau d'une soutenance publiée
  (mêmes contrôles qu'à la planification) puis publie immédiatement une
  nouvelle version pour elle : les participants reçoivent une nouvelle
  convocation et l'ancienne reste identifiable comme remplacée.
* ANNULER (personnel) : libère salle et jury ; les convocations actives
  passent à « annulee » (elles restent consultables).

Les notifications (courriels simulés) sont mises « en attente » : leur envoi
(commande `envoyer_convocations`) peut échouer et être relancé sans jamais
annuler le planning validé.
"""
from django.db import connection, transaction
from django.db.models import Max
from rest_framework.exceptions import ValidationError

from api.exceptions import ConflitMetier
from api.journalisation import tracer_evenement
from api.models import Convocation, Defense, VersionPlanning
from api.services import conflicts

PLANIFIE = 'planifie'
CONFIRME = 'confirme'
PUBLIE = 'publie'
REPORTE = 'reporte'
TERMINE = 'termine'
ANNULE = 'annule'
STATUTS = (PLANIFIE, CONFIRME, PUBLIE, REPORTE, TERMINE, ANNULE)


def _verrou_planning():
    """Même verrou transactionnel que la planification (ADR 0002)."""
    with connection.cursor() as curseur:
        curseur.execute("SELECT pg_advisory_xact_lock(%s, %s)", [0x534753, 1])


def _verrouiller(defense_id):
    """Relit une soutenance avec verrou de ligne."""
    try:
        return Defense.objects.select_for_update(of=('self',)).select_related(
            'folder__student', 'jury',
        ).get(pk=defense_id)
    except Defense.DoesNotExist as erreur:
        raise ValidationError({'soutenance': "Cette soutenance n'existe pas."}) from erreur


def _exiger_etat(soutenance, etats, action):
    """Refuse (409) une action depuis un état non prévu."""
    if soutenance.status not in etats:
        raise ConflitMetier(
            f"Action « {action} » impossible : la soutenance #{soutenance.pk} "
            f"est à l'état « {soutenance.status} ».",
            regle='F05',
            details={'soutenance': soutenance.pk, 'statut': soutenance.status},
        )


def _exiger_jury_complet(soutenance):
    """F04 : un jury absent ou incomplet ne peut pas être confirmé."""
    if soutenance.jury is None or not soutenance.jury.is_complete:
        raise ConflitMetier(
            f"La soutenance #{soutenance.pk} ne peut pas être confirmée : son "
            "jury n'est pas déclaré complet (F04).",
            regle='F04',
            details={'soutenance': soutenance.pk},
        )


def _controler_avant_publication(soutenance):
    """
    Revérifie toutes les règles d'une soutenance au moment de publier.

    Retour : liste de messages d'erreur (vide si tout est conforme).
    """
    problemes = []
    try:
        conflicts.verifier_dossier_recevable(soutenance.folder_id)
        _exiger_jury_complet(soutenance)
        conflicts.verifier_toutes_regles(
            soutenance.folder_id, soutenance.jury_id, soutenance.room_name,
            soutenance.slot_range, defense_exclue_id=soutenance.pk,
        )
    except ConflitMetier as erreur:
        problemes.append(f"Soutenance #{soutenance.pk} : {erreur.detail}")
    except ValidationError as erreur:
        problemes.append(f"Soutenance #{soutenance.pk} : {erreur.detail}")
    return problemes


def _destinataires(soutenance):
    """Étudiant puis membres du jury : (nom, rôle, compte ou None)."""
    etudiant = soutenance.folder.student
    compte_etudiant = getattr(etudiant, 'student_account', None)
    personnes = [(
        etudiant.full_name, 'etudiant',
        compte_etudiant.user if compte_etudiant is not None else None,
    )]
    if soutenance.jury is not None:
        for membre in soutenance.jury.members.order_by('pk'):
            compte = getattr(membre, 'account', None)
            personnes.append((
                membre.member_name, membre.role_in_jury,
                compte.user if compte is not None else None,
            ))
    return personnes


def _convoquer(soutenance, version):
    """Crée les convocations de `soutenance` et remplace les précédentes."""
    anciennes = {
        (convocation.destinataire, convocation.role_destinataire): convocation
        for convocation in Convocation.objects.filter(soutenance=soutenance, statut='active')
    }
    nouvelles = []
    for nom, role, compte in _destinataires(soutenance):
        convocation = Convocation.objects.create(
            version=version,
            soutenance=soutenance,
            destinataire=nom,
            role_destinataire=role,
            compte=compte,
            debut=soutenance.slot_range.lower,
            fin=soutenance.slot_range.upper,
            salle=soutenance.room_name,
            jury=soutenance.jury.name if soutenance.jury else '',
        )
        nouvelles.append(convocation)
        ancienne = anciennes.pop((nom, role), None)
        if ancienne is not None:
            ancienne.statut = 'remplacee'
            ancienne.remplacee_par = convocation
            ancienne.save(update_fields=['statut', 'remplacee_par'])
    # Personnes qui ne sont plus convoquées (jury modifié) : remplacées sans successeur.
    for ancienne in anciennes.values():
        ancienne.statut = 'remplacee'
        ancienne.save(update_fields=['statut'])
    return nouvelles


def _publier(soutenances, acteur, commentaire):
    """Publie `soutenances` (déjà contrôlées) dans une nouvelle version."""
    numero = (VersionPlanning.objects.aggregate(m=Max('numero'))['m'] or 0) + 1
    version = VersionPlanning.objects.create(
        numero=numero, publiee_par=acteur, commentaire=commentaire,
        nombre_soutenances=len(soutenances),
    )
    for soutenance in soutenances:
        _convoquer(soutenance, version)
        soutenance.status = PUBLIE
        soutenance.save(update_fields=['status'])
    tracer_evenement('planning.publie', version=numero,
                     soutenances=[s.pk for s in soutenances],
                     acteur=getattr(acteur, 'pk', None))
    return version


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

@transaction.atomic
def confirmer(defense_id, acteur):
    """Confirme une soutenance proposée (dossier recevable, jury complet)."""
    _verrou_planning()
    soutenance = _verrouiller(defense_id)
    _exiger_etat(soutenance, (PLANIFIE,), 'confirmer')
    conflicts.verifier_dossier_recevable(soutenance.folder_id)
    _exiger_jury_complet(soutenance)
    soutenance.status = CONFIRME
    soutenance.save(update_fields=['status'])
    tracer_evenement('soutenance.confirmee', soutenance=soutenance.pk,
                     acteur=getattr(acteur, 'pk', None))
    return soutenance


@transaction.atomic
def publier(acteur, commentaire=''):
    """
    Publie toutes les soutenances confirmées ou reportées.

    Lève ConflitMetier (409) si rien n'est à publier ou si une seule règle
    est violée : dans ce cas AUCUNE écriture n'est faite.
    """
    _verrou_planning()
    soutenances = list(
        Defense.objects.select_for_update(of=('self',))
        .filter(status__in=(CONFIRME, REPORTE))
        .select_related('folder__student', 'jury')
        .order_by('slot_range', 'pk')
    )
    if not soutenances:
        raise ConflitMetier(
            "Aucune soutenance confirmée n'est en attente de publication.",
            regle='F05',
        )
    problemes = []
    for soutenance in soutenances:
        problemes.extend(_controler_avant_publication(soutenance))
    if problemes:
        raise ConflitMetier(
            "Publication refusée : corrigez les soutenances signalées.",
            regle='F05',
            details={'problemes': problemes},
        )
    return _publier(soutenances, acteur, commentaire)


@transaction.atomic
def reporter(defense_id, acteur, debut, fin, room_name=None, motif=''):
    """
    Reporte une soutenance publiée et publie une nouvelle version pour elle.

    Les contrôles de planification (EXG01, recevabilité, indisponibilités)
    s'appliquent au nouveau créneau ; les anciennes convocations restent
    consultables, marquées « remplacee » (STA07).
    """
    motif = (motif or '').strip()
    if not motif:
        raise ValidationError({'motif': 'Le motif du report est obligatoire.'})
    _verrou_planning()
    soutenance = _verrouiller(defense_id)
    _exiger_etat(soutenance, (PUBLIE, REPORTE), 'reporter')
    soutenance = conflicts.planifier_soutenance(
        soutenance.folder_id, soutenance.jury_id,
        room_name or soutenance.room_name, debut, fin,
        status=REPORTE, defense_id=soutenance.pk,
    )
    _exiger_jury_complet(soutenance)
    return _publier([soutenance], acteur, f'Report de la soutenance #{soutenance.pk} : {motif}')


@transaction.atomic
def annuler(defense_id, acteur, motif=''):
    """Annule une soutenance : salle et jury sont libérés, convocations annulées."""
    soutenance = _verrouiller(defense_id)
    _exiger_etat(soutenance, (PLANIFIE, CONFIRME, PUBLIE, REPORTE), 'annuler')
    soutenance.status = ANNULE
    soutenance.save(update_fields=['status'])
    Convocation.objects.filter(soutenance=soutenance, statut='active').update(statut='annulee')
    tracer_evenement('soutenance.annulee', soutenance=soutenance.pk, motif=motif[:200],
                     acteur=getattr(acteur, 'pk', None))
    return soutenance


@transaction.atomic
def marquer_tenue(defense_id, acteur):
    """Enregistre qu'une soutenance publiée a bien eu lieu (→ termine)."""
    soutenance = _verrouiller(defense_id)
    _exiger_etat(soutenance, (PUBLIE,), 'marquer comme tenue')
    soutenance.status = TERMINE
    soutenance.save(update_fields=['status'])
    tracer_evenement('soutenance.tenue', soutenance=soutenance.pk,
                     acteur=getattr(acteur, 'pk', None))
    return soutenance
