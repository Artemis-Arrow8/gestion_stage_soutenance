"""
Machine à états des dossiers de stage (chapitre 4 du dossier ALM : « les
changements d'état » et « les événements de validation »).

États : brouillon → soumis → a_corriger | valide → recevable, plus rejete.

* soumettre (étudiant propriétaire) : brouillon | a_corriger → soumis ;
  précondition : au moins une version du rapport déposée.
* avis_pedagogique (encadreur affecté, ou responsable) : soumis → valide
  (favorable) | a_corriger (défavorable) ; l'avis porte sur la DERNIÈRE version.
* autoriser_soutenance (responsable des stages, admin) : valide → recevable ;
  précondition : avis favorable de l'encadreur sur la dernière version.
* refuser (responsable, admin) : soumis | a_corriger | valide → rejete ;
  motif obligatoire.
* rouvrir (responsable, admin) : rejete | recevable → soumis ; motif
  obligatoire et aucune soutenance active.
* nouvelle_version (dépôt d'un PDF) : valide | recevable → soumis ; la
  recevabilité est réexaminée (STA05).

Hypothèse retenue pour la campagne de démonstration (à confirmer avec
l'établissement, voir docs/cahier-des-charges.md) : l'avis du tuteur en
entreprise n'est PAS une étape obligatoire.

Chaque transition est faite dans une transaction, avec verrou de ligne sur
le dossier (select_for_update), et laisse une trace dans HistoriqueDossier.
Toute étape sautée ou tout acteur non autorisé est refusé côté serveur
(STA11) : l'état et les décisions restent inchangés.
"""
from django.db import transaction
from rest_framework.exceptions import PermissionDenied, ValidationError

from api.exceptions import ConflitMetier
from api.journalisation import tracer_evenement
from api.models import (
    Defense,
    DocumentVersion,
    HistoriqueDossier,
    InternshipFolder,
    Review,
)
from api.roles import get_user_role

# États possibles d'un dossier.
BROUILLON = 'brouillon'
SOUMIS = 'soumis'
A_CORRIGER = 'a_corriger'
VALIDE = 'valide'
RECEVABLE = 'recevable'
REJETE = 'rejete'
STATUTS = (BROUILLON, SOUMIS, A_CORRIGER, VALIDE, RECEVABLE, REJETE)

# Décisions d'avis pédagogique reconnues.
AVIS_FAVORABLE = 'favorable'
AVIS_DEFAVORABLE = 'defavorable'

# Rôles du personnel habilités à autoriser, refuser ou rouvrir un dossier.
ROLES_RESPONSABLES = ('admin', 'responsible')


# ---------------------------------------------------------------------------
# Outils communs
# ---------------------------------------------------------------------------

def derniere_version(dossier):
    """Retourne la dernière version déposée du rapport (ou None)."""
    return (
        DocumentVersion.objects.filter(folder=dossier)
        .order_by('-version_number', '-uploaded_at')
        .first()
    )


def est_encadreur_affecte(utilisateur, dossier):
    """Vrai si `utilisateur` est encadreur affecté à `dossier`."""
    return dossier.supervisor_assignments.filter(user=utilisateur).exists()


def avis_favorable_sur_derniere_version(dossier):
    """
    Vrai si la DERNIÈRE version du rapport porte un avis favorable de
    l'encadreur. Un avis sur une version antérieure ne compte plus : il
    reste attaché à la version examinée (STA05).
    """
    version = derniere_version(dossier)
    if version is None:
        return False
    return Review.objects.filter(
        document_version=version,
        author_role='encadreur',
        decision=AVIS_FAVORABLE,
    ).exists()


def _verrouiller(dossier_id):
    """Relit le dossier en le verrouillant jusqu'à la fin de la transaction."""
    try:
        return InternshipFolder.objects.select_for_update().get(pk=dossier_id)
    except InternshipFolder.DoesNotExist as erreur:
        raise ValidationError({'dossier': "Ce dossier n'existe pas."}) from erreur


def _exiger_etat(dossier, etats_autorises, evenement):
    """Refuse (409) une transition depuis un état non prévu (étape sautée)."""
    if dossier.status not in etats_autorises:
        attendus = ', '.join(etats_autorises)
        raise ConflitMetier(
            f"Action « {evenement} » impossible : le dossier est à l'état "
            f"« {dossier.status} » (états attendus : {attendus}).",
            regle='STA11',
            details={'dossier': dossier.pk, 'statut': dossier.status},
        )


def _exiger_motif(motif):
    """Un refus ou une réouverture doit être motivé."""
    motif = (motif or '').strip()
    if not motif:
        raise ValidationError({'motif': 'Un motif est obligatoire pour cette action.'})
    return motif


def _changer_etat(dossier, nouvel_etat, evenement, acteur, motif='', version=None):
    """Applique la transition et enregistre la preuve dans l'historique."""
    ancien = dossier.status
    dossier.status = nouvel_etat
    dossier.save(update_fields=['status'])
    HistoriqueDossier.objects.create(
        dossier=dossier,
        evenement=evenement,
        statut_avant=ancien,
        statut_apres=nouvel_etat,
        acteur=acteur if getattr(acteur, 'is_authenticated', False) else None,
        motif=motif,
        version_document=version,
    )
    tracer_evenement(
        f'dossier.{evenement}', dossier=dossier.pk, avant=ancien,
        apres=nouvel_etat, acteur=getattr(acteur, 'pk', None),
    )
    return dossier


# ---------------------------------------------------------------------------
# Événements
# ---------------------------------------------------------------------------

# Longueur maximale du message facultatif joint à un envoi (soumettre).
LONGUEUR_MAX_MESSAGE = 1000


@transaction.atomic
def soumettre(dossier_id, acteur, message=''):
    """
    L'étudiant soumet son dossier (brouillon ou à corriger → soumis).

    Paramètres :
        message (str) : mot facultatif pour l'encadreur (ex. « J'ai repris le
            chapitre 2 »). Il est conservé comme motif de l'étape dans
            l'historique, et donc lisible par l'encadreur dans
            `derniere_etape` tant qu'aucune autre étape ne le remplace.

    Lève :
        PermissionDenied : l'appelant n'est pas l'étudiant propriétaire ;
        ConflitMetier : état incompatible ou aucun rapport déposé.
    """
    dossier = _verrouiller(dossier_id)
    compte = getattr(dossier.student, 'student_account', None)
    if get_user_role(acteur) != 'admin' and (compte is None or compte.user_id != acteur.pk):
        raise PermissionDenied("Seul l'étudiant propriétaire peut soumettre ce dossier.")
    _exiger_etat(dossier, (BROUILLON, A_CORRIGER), 'soumettre')
    version = derniere_version(dossier)
    if version is None:
        raise ConflitMetier(
            "Déposez au moins une version de votre rapport (PDF) avant de soumettre.",
            regle='F02',
            details={'dossier': dossier.pk},
        )
    # Message facultatif : espaces superflus retirés, longueur bornée.
    message = (message or '').strip()
    if len(message) > LONGUEUR_MAX_MESSAGE:
        raise ValidationError({
            'motif': f'Le message ne doit pas dépasser {LONGUEUR_MAX_MESSAGE} caractères.',
        })
    return _changer_etat(dossier, SOUMIS, 'soumettre', acteur,
                         motif=message, version=version)


@transaction.atomic
def enregistrer_avis_pedagogique(version_id, acteur, decision, commentaire=''):
    """
    L'encadreur affecté donne son avis sur une version précise du rapport.

    L'avis est TOUJOURS rattaché à la version examinée. Si le dossier est
    soumis et que la version est la dernière : avis favorable → valide,
    défavorable → a_corriger (demande de correction).

    Retour : l'avis créé (Review).
    Lève :
        PermissionDenied : encadreur non affecté au dossier ;
        ConflitMetier : dossier non soumis, ou version qui n'est plus la
            dernière (l'avis serait périmé).
    """
    if decision not in (AVIS_FAVORABLE, AVIS_DEFAVORABLE):
        raise ValidationError({'decision': 'Décision attendue : favorable ou defavorable.'})
    try:
        version = DocumentVersion.objects.select_related('folder').get(pk=version_id)
    except DocumentVersion.DoesNotExist as erreur:
        raise ValidationError({'document_version': "Cette version n'existe pas."}) from erreur
    dossier = _verrouiller(version.folder_id)
    role = get_user_role(acteur)
    if role == 'supervisor' and not est_encadreur_affecte(acteur, dossier):
        raise PermissionDenied(
            "Vous ne pouvez donner un avis que sur un dossier qui vous est affecté."
        )
    if role not in ('supervisor', 'admin', 'responsible'):
        raise PermissionDenied("Seul l'encadreur affecté peut donner l'avis pédagogique.")
    _exiger_etat(dossier, (SOUMIS,), 'avis pédagogique')
    derniere = derniere_version(dossier)
    if derniere is not None and derniere.pk != version.pk:
        raise ConflitMetier(
            f"Une version plus récente (V{derniere.version_number}) a été déposée : "
            "l'avis doit porter sur elle.",
            regle='STA05',
            details={'dossier': dossier.pk, 'derniere_version': derniere.pk},
        )
    avis = Review.objects.create(
        document_version=version,
        author=acteur,
        author_role='encadreur',
        decision=decision,
        comments=commentaire or None,
    )
    nouvel_etat = VALIDE if decision == AVIS_FAVORABLE else A_CORRIGER
    evenement = 'avis_favorable' if decision == AVIS_FAVORABLE else 'demander_correction'
    _changer_etat(dossier, nouvel_etat, evenement, acteur,
                  motif=commentaire or '', version=version)
    return avis


@transaction.atomic
def autoriser_soutenance(dossier_id, acteur):
    """
    Le responsable autorise la soutenance (valide → recevable).

    La précondition est RE-vérifiée ici : l'avis favorable doit porter sur
    la dernière version (STA11 : refus si l'avis obligatoire manque).
    """
    if get_user_role(acteur) not in ROLES_RESPONSABLES:
        raise PermissionDenied("Seul le responsable des stages peut autoriser une soutenance.")
    dossier = _verrouiller(dossier_id)
    _exiger_etat(dossier, (VALIDE,), 'autoriser la soutenance')
    if not avis_favorable_sur_derniere_version(dossier):
        raise ConflitMetier(
            "Autorisation impossible : l'avis favorable de l'encadreur sur la "
            "dernière version du rapport est absent.",
            regle='F03',
            details={'dossier': dossier.pk},
        )
    return _changer_etat(dossier, RECEVABLE, 'autoriser_soutenance', acteur,
                         version=derniere_version(dossier))


@transaction.atomic
def refuser(dossier_id, acteur, motif):
    """Le responsable refuse le dossier avec un motif (→ rejete)."""
    if get_user_role(acteur) not in ROLES_RESPONSABLES:
        raise PermissionDenied("Seul le responsable des stages peut refuser un dossier.")
    motif = _exiger_motif(motif)
    dossier = _verrouiller(dossier_id)
    _exiger_etat(dossier, (SOUMIS, A_CORRIGER, VALIDE), 'refuser')
    return _changer_etat(dossier, REJETE, 'refuser', acteur, motif=motif,
                         version=derniere_version(dossier))


@transaction.atomic
def rouvrir(dossier_id, acteur, motif):
    """
    Le responsable rouvre un dossier refusé ou recevable (→ soumis).

    Refusé si une soutenance active (non annulée) existe : il faut d'abord
    l'annuler, pour ne pas laisser au planning un dossier non recevable.
    """
    if get_user_role(acteur) not in ROLES_RESPONSABLES:
        raise PermissionDenied("Seul le responsable des stages peut rouvrir un dossier.")
    motif = _exiger_motif(motif)
    dossier = _verrouiller(dossier_id)
    _exiger_etat(dossier, (REJETE, RECEVABLE), 'rouvrir')
    if Defense.objects.filter(folder=dossier).exclude(status='annule').exists():
        raise ConflitMetier(
            "Ce dossier a une soutenance planifiée : annulez-la avant de rouvrir le dossier.",
            regle='F03',
            details={'dossier': dossier.pk},
        )
    return _changer_etat(dossier, SOUMIS, 'rouvrir', acteur, motif=motif)


def apres_nouvelle_version(dossier, version, acteur):
    """
    Appelé après le dépôt d'une nouvelle version du rapport (même transaction).

    Les avis existants restent attachés aux versions examinées ; un dossier
    déjà validé ou recevable repasse à « soumis » pour que sa recevabilité
    soit réexaminée sur la nouvelle pièce (STA05). Une pièce approuvée n'est
    donc jamais remplacée silencieusement.
    """
    if dossier.status in (VALIDE, RECEVABLE):
        _changer_etat(dossier, SOUMIS, 'nouvelle_version', acteur,
                      motif=f'Dépôt de la version {version.version_number}',
                      version=version)
    else:
        HistoriqueDossier.objects.create(
            dossier=dossier, evenement='nouvelle_version',
            statut_avant=dossier.status, statut_apres=dossier.status,
            acteur=acteur if getattr(acteur, 'is_authenticated', False) else None,
            motif=f'Dépôt de la version {version.version_number}',
            version_document=version,
        )
