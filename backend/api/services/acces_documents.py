"""
Droits de consultation des rapports de stage (complément F02 : confidentialité,
STA04 et STA08).

Une seule fonction décide, pour un compte et un dossier, si les rapports
(toutes versions, anciennes comprises) peuvent être consultés. Elle est
appliquée côté serveur à CHAQUE téléchargement : connaître l'URL exacte d'un
fichier ne suffit jamais (STA04).

Règles :
* étudiant : uniquement son propre dossier ;
* encadreur : uniquement les dossiers qui lui sont affectés ;
* membre de jury : uniquement les dossiers des soutenances ACTIVES de son
  jury (pas les autres) ;
* responsable / administrateur : les dossiers « standard » ;
* dossier CONFIDENTIEL : seuls l'étudiant, ses encadreurs affectés et les
  titulaires d'une habilitation valide (non révoquée, dans sa période) y
  accèdent — ni le jury, ni la scolarité, ni l'administration
  automatiquement. La fin d'un embargo ne change rien (STA08).

Chaque tentative, autorisée ou refusée, est journalisée sans contenu.
"""
from django.utils import timezone

from api.models import (
    ConfidentialiteDossier,
    Defense,
    HabilitationDossier,
    JournalAccesDocument,
)
from api.roles import get_user_role


def est_confidentiel(dossier):
    """Vrai si le dossier est marqué confidentiel."""
    return ConfidentialiteDossier.objects.filter(
        dossier=dossier, niveau='confidentiel',
    ).exists()


def habilitation_valide(utilisateur, dossier, maintenant=None):
    """Vrai si `utilisateur` détient une habilitation en cours sur `dossier`."""
    maintenant = maintenant or timezone.now()
    return (
        HabilitationDossier.objects.filter(
            dossier=dossier, beneficiaire=utilisateur, revoquee=False,
            valide_du__lte=maintenant,
        )
        .exclude(valide_au__lt=maintenant)
        .exists()
    )


def _est_proprietaire(utilisateur, dossier):
    """Vrai si le compte est celui de l'étudiant titulaire du dossier."""
    compte = getattr(dossier.student, 'student_account', None)
    return compte is not None and compte.user_id == utilisateur.pk


def dossiers_du_jury(utilisateur):
    """
    Identifiants des dossiers que `utilisateur` (membre de jury) doit lire :
    ceux des soutenances ACTIVES (non annulées) de son jury.

    Retour : sous-requête de `folder_id`, utilisable dans `pk__in=` ou
    `folder_id__in=` (une seule requête SQL, sans doublon gênant).
    """
    return (
        Defense.objects.filter(jury__members__account__user=utilisateur)
        .exclude(status='annule')
        .values('folder_id')
    )


def _siege_au_jury(utilisateur, dossier):
    """Vrai si le compte est membre du jury d'une soutenance active du dossier."""
    compte_jury = getattr(utilisateur, 'jury_member_account', None)
    if compte_jury is None:
        return False
    return (
        Defense.objects.filter(folder=dossier, jury_id=compte_jury.jury_member.jury_id)
        .exclude(status='annule')
        .exists()
    )


def decision_acces(utilisateur, dossier):
    """
    Décide si `utilisateur` peut consulter les rapports de `dossier`.

    Retour : (autorise: bool, motif_refus: str).
    """
    role = get_user_role(utilisateur)
    proprietaire = role == 'student' and _est_proprietaire(utilisateur, dossier)
    encadreur = (
        role == 'supervisor'
        and dossier.supervisor_assignments.filter(user=utilisateur).exists()
    )
    # L'étudiant et ses encadreurs gardent toujours l'accès à leur dossier.
    if proprietaire or encadreur:
        return True, ''
    if role in ('student', 'supervisor'):
        return False, 'Dossier hors de votre périmètre.'

    if est_confidentiel(dossier):
        if habilitation_valide(utilisateur, dossier):
            return True, ''
        return False, 'Rapport confidentiel : une habilitation nominative est nécessaire.'

    if role in ('admin', 'responsible'):
        return True, ''
    if role == 'jury' and _siege_au_jury(utilisateur, dossier):
        return True, ''
    return False, "Votre rôle ne permet pas de consulter ce rapport."


def journaliser_acces(utilisateur, version, autorise, motif='', action='telechargement'):
    """Trace une tentative d'accès (audit), sans le contenu du document."""
    JournalAccesDocument.objects.create(
        version_document_id=version.pk,
        utilisateur=utilisateur if getattr(utilisateur, 'is_authenticated', False) else None,
        action=action,
        autorise=autorise,
        motif=motif[:255],
    )
