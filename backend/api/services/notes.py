"""
Notes, grille d'évaluation et procès-verbaux (F06, STA06, STA10, STA12).

Règles appliquées CÔTÉ SERVEUR (le client ne fournit jamais la moyenne) :

* la grille de la campagne fixe les coefficients (règle fictive de
  démonstration : rapport 40 %, oral 60 %) et la note maximale (20) ;
* calcul en type décimal exact, arrondi au centième, demi supérieur
  (ROUND_HALF_UP) : 14 et 16 donnent 15,20 ;
* une note absente RESTE absente : pas de zéro implicite, pas de moyenne ;
* l'approbation est bloquée tant qu'une note manque ou que le jury n'est pas
  complet (« quorum fictif » retenu pour la démonstration) ;
* une note approuvée n'est plus modifiable par une simple mise à jour
  (STA06) : seule la RECTIFICATION, réservée au responsable des stages,
  la corrige, avec un motif, et produit une nouvelle version du
  procès-verbal ; l'ancienne reste consultable (STA12).
"""
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from rest_framework.exceptions import PermissionDenied, ValidationError

from api.exceptions import ConflitMetier
from api.journalisation import tracer_evenement
from api.models import Assessment, GrilleEvaluation, ProcesVerbal
from api.roles import get_user_role

# Précision des moyennes : deux décimales.
CENTIEME = Decimal('0.01')
# Rôles qui gèrent les notes sans restriction de périmètre.
ROLES_PERSONNEL = ('admin', 'responsible')
# Rôle du jury qui approuve le procès-verbal pour le jury.
ROLE_PRESIDENT = 'president'


# ---------------------------------------------------------------------------
# Grille et calcul
# ---------------------------------------------------------------------------

def grille_de_la_campagne(campagne):
    """
    Retourne la grille en vigueur pour la campagne (dernière version).

    Si la campagne n'en a pas encore, la version 1 est créée avec la règle
    fictive de démonstration (40 % / 60 %).
    """
    grille = GrilleEvaluation.objects.filter(campagne=campagne).order_by('-version').first()
    if grille is None:
        grille, _ = GrilleEvaluation.objects.get_or_create(campagne=campagne, version=1)
    return grille


def grille_affichee(campagne):
    """
    Description de la grille en vigueur pour l'affichage, SANS la créer
    (une lecture ne doit pas écrire en base) : valeurs par défaut du modèle
    si la campagne n'a pas encore de grille.
    """
    grille = GrilleEvaluation.objects.filter(campagne=campagne).order_by('-version').first()
    if grille is None:
        champ = GrilleEvaluation._meta.get_field
        return {
            'version': None,
            'poids_rapport': str(champ('poids_rapport').default),
            'poids_oral': str(champ('poids_oral').default),
            'note_maximale': str(champ('note_maximale').default),
        }
    return {
        'version': grille.version,
        'poids_rapport': str(grille.poids_rapport),
        'poids_oral': str(grille.poids_oral),
        'note_maximale': str(grille.note_maximale),
    }


def verifier_bornes(grille, note, champ):
    """Refuse une note hors de [0 ; note maximale de la grille]."""
    if note is None:
        return None
    note = Decimal(str(note))
    if note < 0 or note > grille.note_maximale:
        raise ValidationError(
            {champ: f'La note doit être comprise entre 0 et {grille.note_maximale}.'}
        )
    return note


def calculer_moyenne(grille, note_rapport, note_oral):
    """
    Moyenne pondérée exacte, ou None si une note manque.

    Exemple (grille fictive 40/60) : 14 et 16 → 0,4 × 14 + 0,6 × 16 = 15,20.
    """
    if note_rapport is None or note_oral is None:
        return None
    moyenne = (
        grille.poids_rapport * Decimal(str(note_rapport))
        + grille.poids_oral * Decimal(str(note_oral))
    )
    return moyenne.quantize(CENTIEME, rounding=ROUND_HALF_UP)


def recalculer(evaluation):
    """Met à jour la moyenne d'une évaluation NON approuvée selon la grille."""
    grille = grille_de_la_campagne(evaluation.defense.folder.campaign)
    verifier_bornes(grille, evaluation.report_grade, 'report_grade')
    verifier_bornes(grille, evaluation.oral_grade, 'oral_grade')
    evaluation.final_average = calculer_moyenne(
        grille, evaluation.report_grade, evaluation.oral_grade,
    )
    return evaluation


# ---------------------------------------------------------------------------
# Droits
# ---------------------------------------------------------------------------

def _membre_du_jury(utilisateur, evaluation):
    """Retourne le membre de jury du compte s'il siège à cette soutenance."""
    compte = getattr(utilisateur, 'jury_member_account', None)
    if compte is None or evaluation.defense.jury_id is None:
        return None
    membre = compte.jury_member
    return membre if membre.jury_id == evaluation.defense.jury_id else None


def peut_saisir(utilisateur, evaluation):
    """Personnel, ou membre du jury de la soutenance évaluée."""
    if get_user_role(utilisateur) in ROLES_PERSONNEL:
        return True
    return _membre_du_jury(utilisateur, evaluation) is not None


def peut_approuver(utilisateur, evaluation):
    """Personnel, ou président du jury de la soutenance évaluée."""
    if get_user_role(utilisateur) in ROLES_PERSONNEL:
        return True
    membre = _membre_du_jury(utilisateur, evaluation)
    return membre is not None and membre.role_in_jury.lower() == ROLE_PRESIDENT


def refuser_si_approuvee(evaluation):
    """STA06 : une note approuvée ne se modifie que par rectification."""
    if evaluation.is_approved:
        raise ConflitMetier(
            "Cette note est approuvée : elle ne peut être corrigée que par la "
            "procédure de rectification (responsable des stages, avec motif).",
            regle='STA06',
            details={'evaluation': evaluation.pk},
        )


# ---------------------------------------------------------------------------
# Approbation et rectification
# ---------------------------------------------------------------------------

def _composition_jury(evaluation):
    """Copie figée de la composition du jury pour le procès-verbal."""
    jury = evaluation.defense.jury
    if jury is None:
        return []
    return [
        {'nom': membre.member_name, 'role': membre.role_in_jury}
        for membre in jury.members.order_by('pk')
    ]


def _prochaine_version(evaluation):
    """Numéro de la prochaine version de procès-verbal."""
    derniere = evaluation.proces_verbaux.order_by('-version').first()
    return 1 if derniere is None else derniere.version + 1


@transaction.atomic
def approuver(evaluation_id, acteur):
    """
    Approuve les notes et produit la version 1 du procès-verbal.

    Lève :
        PermissionDenied : ni personnel, ni président du jury ;
        ConflitMetier : déjà approuvée, note manquante (STA10) ou jury
            incomplet (quorum fictif).
    """
    evaluation = Assessment.objects.select_for_update(of=('self',)).select_related(
        'defense__jury', 'defense__folder__campaign',
    ).get(pk=evaluation_id)
    if not peut_approuver(acteur, evaluation):
        raise PermissionDenied(
            "Seuls le président du jury et le responsable des stages approuvent les notes."
        )
    refuser_si_approuvee(evaluation)
    if evaluation.report_grade is None or evaluation.oral_grade is None:
        raise ConflitMetier(
            "Approbation bloquée : les notes du rapport ET de l'oral sont "
            "obligatoires (une note absente n'est jamais comptée comme zéro).",
            regle='STA10',
            details={'evaluation': evaluation.pk},
        )
    jury = evaluation.defense.jury
    if jury is None or not jury.is_complete:
        raise ConflitMetier(
            "Approbation bloquée : le jury de cette soutenance n'est pas complet "
            "(quorum fictif de démonstration).",
            regle='F06',
            details={'evaluation': evaluation.pk},
        )
    grille = grille_de_la_campagne(evaluation.defense.folder.campaign)
    moyenne = calculer_moyenne(grille, evaluation.report_grade, evaluation.oral_grade)
    evaluation.final_average = moyenne
    evaluation.is_approved = True
    evaluation.save(update_fields=['final_average', 'is_approved'])
    pv = ProcesVerbal.objects.create(
        evaluation=evaluation,
        version=_prochaine_version(evaluation),
        grille=grille,
        note_rapport=evaluation.report_grade,
        note_oral=evaluation.oral_grade,
        moyenne=moyenne,
        membres_jury=_composition_jury(evaluation),
        approuve_par=acteur,
    )
    tracer_evenement('notes.approuvees', evaluation=evaluation.pk,
                     pv=pv.version, acteur=acteur.pk)
    return pv


@transaction.atomic
def rectifier(evaluation_id, acteur, note_rapport, note_oral, motif):
    """
    Rectifie une note APPROUVÉE (procédure attribuée au responsable).

    Crée la version suivante du procès-verbal (motif, auteur, approbation),
    marque la précédente « remplace » et met à jour l'évaluation. La grille
    utilisée reste celle, figée, du procès-verbal d'origine.
    """
    if get_user_role(acteur) not in ROLES_PERSONNEL:
        raise PermissionDenied("La rectification est réservée au responsable des stages.")
    motif = (motif or '').strip()
    if not motif:
        raise ValidationError({'motif': 'Le motif de la rectification est obligatoire.'})
    evaluation = Assessment.objects.select_for_update(of=('self',)).select_related(
        'defense__jury', 'defense__folder__campaign',
    ).get(pk=evaluation_id)
    if not evaluation.is_approved:
        raise ConflitMetier(
            "Cette note n'est pas encore approuvée : modifiez-la directement.",
            regle='STA12',
            details={'evaluation': evaluation.pk},
        )
    precedent = evaluation.proces_verbaux.filter(statut='approuve').order_by('-version').first()
    grille = precedent.grille if precedent else grille_de_la_campagne(
        evaluation.defense.folder.campaign
    )
    if note_rapport is None or note_oral is None:
        raise ValidationError({'detail': 'Les deux notes sont obligatoires pour une rectification.'})
    note_rapport = verifier_bornes(grille, note_rapport, 'report_grade')
    note_oral = verifier_bornes(grille, note_oral, 'oral_grade')
    moyenne = calculer_moyenne(grille, note_rapport, note_oral)
    if precedent is not None:
        precedent.statut = 'remplace'
        precedent.save(update_fields=['statut'])
    evaluation.report_grade = note_rapport
    evaluation.oral_grade = note_oral
    evaluation.final_average = moyenne
    evaluation.save(update_fields=['report_grade', 'oral_grade', 'final_average'])
    pv = ProcesVerbal.objects.create(
        evaluation=evaluation,
        version=_prochaine_version(evaluation),
        grille=grille,
        note_rapport=note_rapport,
        note_oral=note_oral,
        moyenne=moyenne,
        membres_jury=_composition_jury(evaluation),
        motif=motif,
        approuve_par=acteur,
    )
    tracer_evenement('notes.rectifiees', evaluation=evaluation.pk,
                     pv=pv.version, acteur=acteur.pk)
    return pv
