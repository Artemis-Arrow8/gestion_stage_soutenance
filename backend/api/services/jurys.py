"""
Règles de composition des jurys (F04).

Règle FICTIVE retenue pour la démonstration (à confirmer avec
l'établissement, voir docs/cahier-des-charges.md, registre des ambiguïtés) :
un jury est COMPLET s'il compte au moins trois membres, dont au moins un
président et un rapporteur. Une même personne ne peut figurer qu'une fois
dans un jury (« unicité personne dans le jury », chapitre 4).

Un jury déclaré complet repasse automatiquement à « incomplet » si une
modification de sa composition casse la règle : il ne peut alors plus être
confirmé pour une soutenance (critère F04).
"""
from rest_framework.exceptions import ValidationError

# Nombre minimal de membres d'un jury complet.
MEMBRES_MINIMUM = 3
# Fonctions obligatoires dans un jury complet.
FONCTIONS_OBLIGATOIRES = ('president', 'rapporteur')


def problemes_de_composition(jury):
    """Liste les manques de composition (vide si le jury peut être complet)."""
    roles = [role.lower() for role in jury.members.values_list('role_in_jury', flat=True)]
    problemes = []
    if len(roles) < MEMBRES_MINIMUM:
        problemes.append(f'au moins {MEMBRES_MINIMUM} membres (actuellement {len(roles)})')
    for fonction in FONCTIONS_OBLIGATOIRES:
        if fonction not in roles:
            problemes.append(f'un {fonction}')
    return problemes


def exiger_composition_complete(jury):
    """Refuse de déclarer complet un jury qui ne respecte pas la règle."""
    problemes = problemes_de_composition(jury)
    if problemes:
        raise ValidationError({
            'is_complete': 'Composition insuffisante pour un jury complet : il faut '
                           + ', '.join(problemes) + '.'
        })


def reevaluer_completude(jury):
    """Après un changement de membres, retire « complet » si la règle n'est plus tenue."""
    if jury is not None and jury.is_complete and problemes_de_composition(jury):
        jury.is_complete = False
        jury.save(update_fields=['is_complete'])
