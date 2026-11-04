"""
Tests d'intégration PostgreSQL de la règle EXG01 et de F03 (recevabilité).

Couvre STA01, STA02, STA05 (niveau planification) et vérifie qu'un refus
n'écrit RIEN (pas de réservation partielle). Ces tests utilisent les vraies
contraintes d'exclusion de database/schema.sql.
"""

import pytest
from django.db import IntegrityError, transaction
from rest_framework.exceptions import ValidationError

from api.models import Defense
from api.services import conflicts

from .factories import (
    creer_avis,
    creer_defense,
    creer_dossier,
    creer_jury,
    creer_version,
    creneau,
    t,
)

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("salles_demo")]


def _texte(exc_info):
    return str(exc_info.value.detail)


def _planifier(dossier, jury, salle, debut, fin, **kw):
    return conflicts.planifier_soutenance(
        dossier.pk, jury.pk, salle, debut, fin, **kw
    )


# ---------------------------------------------------------------------------
# Cas nominal
# ---------------------------------------------------------------------------

def test_planification_valide_enregistre_la_soutenance():
    dossier, jury = creer_dossier(), creer_jury()
    defense = _planifier(dossier, jury, "Salle 101", t(9), t(10))
    assert Defense.objects.count() == 1
    assert defense.slot_range.lower == t(9) and defense.slot_range.upper == t(10)
    assert defense.status == "planifie"


# ---------------------------------------------------------------------------
# STA01 : chevauchement
# ---------------------------------------------------------------------------

def test_sta01_meme_jury_chevauchement_refuse_sans_ecriture():
    jury = creer_jury()
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 10, 0))
    with pytest.raises(ValidationError) as exc:
        _planifier(creer_dossier(), jury, "Salle 102", t(9, 30), t(10, 30))
    assert "jury" in exc.value.detail
    assert "EXG01" in _texte(exc)
    assert Defense.objects.count() == 1  # aucune réservation partielle


def test_sta01_meme_salle_chevauchement_refuse_avec_conflit_identifie():
    existante = creer_defense(
        creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0)
    )
    with pytest.raises(ValidationError) as exc:
        _planifier(creer_dossier(), creer_jury(), "Salle 101", t(9, 30), t(10, 30))
    assert "room_name" in exc.value.detail
    assert f"#{existante.pk}" in _texte(exc)  # le conflit est identifié
    assert Defense.objects.count() == 1


def test_creneau_inclus_dans_un_autre_refuse():
    jury = creer_jury()
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 12, 0))
    with pytest.raises(ValidationError):
        _planifier(creer_dossier(), creer_jury(), "Salle 101", t(10), t(11))


def test_membre_commun_a_deux_jurys_refuse():
    """Un même juré ne peut pas siéger dans deux jurys au même moment."""
    jury_a = creer_jury(noms=("Dr Traoré", "Dr Keita", "Dr Coulibaly"))
    jury_b = creer_jury(noms=("Dr Traoré", "Dr Diallo", "Dr Sidibé"))
    creer_defense(creer_dossier(), jury_a, "Salle 101", creneau(9, 0, 10, 0))
    with pytest.raises(ValidationError) as exc:
        _planifier(creer_dossier(), jury_b, "Salle 102", t(9, 30), t(10, 30))
    assert "Dr Traoré" in _texte(exc)
    assert Defense.objects.count() == 1


def test_membre_commun_mais_creneaux_disjoints_accepte():
    jury_a = creer_jury(noms=("Dr Traoré", "Dr Keita"))
    jury_b = creer_jury(noms=("Dr Traoré", "Dr Diallo"))
    creer_defense(creer_dossier(), jury_a, "Salle 101", creneau(9, 0, 10, 0))
    _planifier(creer_dossier(), jury_b, "Salle 102", t(11), t(12))
    assert Defense.objects.count() == 2


# ---------------------------------------------------------------------------
# STA02 : créneaux jointifs (marge zéro)
# ---------------------------------------------------------------------------

def test_sta02_creneaux_jointifs_acceptes_avec_marge_zero():
    jury = creer_jury()
    _planifier(creer_dossier(), jury, "Salle 101", t(9), t(10))
    _planifier(creer_dossier(), jury, "Salle 101", t(10), t(11))
    assert Defense.objects.count() == 2


@pytest.mark.skip(
    reason="Marge de déplacement non implémentée dans conflicts.py : "
    "STA02 exige le refus des créneaux jointifs si une marge est configurée."
)
def test_sta02_creneaux_jointifs_refuses_si_marge_configuree():
    ...


# ---------------------------------------------------------------------------
# Modification d'une soutenance existante
# ---------------------------------------------------------------------------

def test_modification_ne_entre_pas_en_conflit_avec_elle_meme():
    dossier, jury = creer_dossier(), creer_jury()
    defense = _planifier(dossier, jury, "Salle 101", t(9), t(10))
    modifiee = _planifier(
        dossier, jury, "Salle 101", t(9, 30), t(10, 30), defense_id=defense.pk
    )
    assert modifiee.pk == defense.pk
    assert Defense.objects.count() == 1
    assert Defense.objects.get(pk=defense.pk).slot_range.lower == t(9, 30)


def test_modification_vers_un_creneau_occupe_refusee_et_inchangee():
    jury_a, jury_b = creer_jury(), creer_jury()
    creer_defense(creer_dossier(), jury_a, "Salle 101", creneau(9, 0, 10, 0))
    dossier_b = creer_dossier()
    defense_b = _planifier(dossier_b, jury_b, "Salle 101", t(11), t(12))
    with pytest.raises(ValidationError):
        _planifier(
            dossier_b, jury_b, "Salle 101", t(9, 30), t(10, 30),
            defense_id=defense_b.pk,
        )
    assert Defense.objects.get(pk=defense_b.pk).slot_range.lower == t(11)


# ---------------------------------------------------------------------------
# F03 / STA05 : recevabilité du dossier
# ---------------------------------------------------------------------------

def test_dossier_brouillon_sans_avis_refuse():
    with pytest.raises(ValidationError) as exc:
        _planifier(creer_dossier("brouillon"), creer_jury(), "Salle 101", t(9), t(10))
    assert "folder" in exc.value.detail
    assert Defense.objects.count() == 0


def test_dossier_inexistant_refuse():
    with pytest.raises(ValidationError) as exc:
        conflicts.planifier_soutenance(999999, creer_jury().pk, "Salle 101", t(9), t(10))
    assert "n'existe pas" in _texte(exc)


def test_avis_favorable_encadreur_rend_le_dossier_planifiable():
    dossier = creer_dossier("soumis")
    creer_avis(dossier, "favorable", "encadreur", version=1)
    _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))
    assert Defense.objects.count() == 1


def test_avis_defavorable_refuse():
    dossier = creer_dossier("soumis")
    creer_avis(dossier, "defavorable", "encadreur")
    with pytest.raises(ValidationError):
        _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))


def test_avis_du_tuteur_seul_ne_suffit_pas():
    dossier = creer_dossier("soumis")
    creer_avis(dossier, "favorable", "tuteur")
    with pytest.raises(ValidationError):
        _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))


def test_sta05_avis_sur_v1_ne_couvre_pas_une_v2():
    """Une nouvelle version du rapport impose un nouvel avis."""
    dossier = creer_dossier("soumis")
    creer_avis(dossier, "favorable", "encadreur", version=1)
    creer_version(dossier, numero=2)
    with pytest.raises(ValidationError):
        _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))
    assert Defense.objects.count() == 0
    creer_avis(dossier, "favorable", "encadreur", version=2)
    _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))
    assert Defense.objects.count() == 1


# ---------------------------------------------------------------------------
# Salle et jury (F04 / F05)
# ---------------------------------------------------------------------------

def test_salle_inexistante_refusee():
    with pytest.raises(ValidationError) as exc:
        _planifier(creer_dossier(), creer_jury(), "Salle 999", t(9), t(10))
    assert "room_name" in exc.value.detail


def test_salle_inactive_refusee():
    from api.models import Room

    Room.objects.create(name="Salle fermée", capacity=10, is_active=False)
    with pytest.raises(ValidationError) as exc:
        _planifier(creer_dossier(), creer_jury(), "Salle fermée", t(9), t(10))
    assert "inactive" in _texte(exc)


def test_jury_inexistant_refuse():
    with pytest.raises(ValidationError) as exc:
        conflicts.planifier_soutenance(
            creer_dossier().pk, 999999, "Salle 101", t(9), t(10)
        )
    assert "jury" in exc.value.detail


def test_jury_sans_membre_refuse():
    jury_vide = creer_jury(noms=())
    with pytest.raises(ValidationError) as exc:
        _planifier(creer_dossier(), jury_vide, "Salle 101", t(9), t(10))
    assert "aucun membre" in _texte(exc)
    assert Defense.objects.count() == 0


def test_creneau_invalide_refuse_avant_toute_ecriture():
    with pytest.raises(ValidationError):
        _planifier(creer_dossier(), creer_jury(), "Salle 101", t(10), t(9))
    assert Defense.objects.count() == 0


# ---------------------------------------------------------------------------
# Contraintes d'exclusion PostgreSQL (dernier rempart d'EXG01)
# ---------------------------------------------------------------------------

def test_contrainte_sql_salle_rejette_le_chevauchement():
    creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0))
    with pytest.raises(IntegrityError) as exc:
        with transaction.atomic():
            creer_defense(
                creer_dossier(), creer_jury(), "Salle 101", creneau(9, 30, 10, 30)
            )
    assert "prevent_room_double_booking" in str(exc.value)
    assert "salle" in str(conflicts.traduire_integrity_error(exc.value).detail)


def test_contrainte_sql_jury_rejette_le_chevauchement():
    jury = creer_jury()
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 10, 0))
    with pytest.raises(IntegrityError) as exc:
        with transaction.atomic():
            creer_defense(creer_dossier(), jury, "Salle 102", creneau(9, 30, 10, 30))
    assert "prevent_jury_double_booking" in str(exc.value)


def test_contrainte_sql_accepte_les_creneaux_jointifs():
    jury = creer_jury()
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 10, 0))
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(10, 0, 11, 0))
    assert Defense.objects.count() == 2
