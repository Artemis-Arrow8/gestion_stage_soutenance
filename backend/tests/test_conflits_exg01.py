"""
Tests d'intégration PostgreSQL de la règle EXG01 et de F03 (recevabilité).

Couvre STA01, STA02, STA05 (niveau planification) et vérifie qu'un refus
n'écrit RIEN (pas de réservation partielle). Ces tests utilisent les vraies
contraintes d'exclusion de database/schema.sql.

Convention : une règle métier violée lève ConflitMetier (HTTP 409), une
donnée invalide (salle inconnue, date mal formée) lève ValidationError (400).
"""

import pytest
from django.db import IntegrityError, transaction
from rest_framework.exceptions import ValidationError

from api.exceptions import ConflitMetier
from api.models import Defense
from api.services import conflicts, dossiers

from .factories import (
    affecter_encadreur,
    creer_avis,
    creer_compte,
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
    with pytest.raises(ConflitMetier) as exc:
        _planifier(creer_dossier(), jury, "Salle 102", t(9, 30), t(10, 30))
    assert exc.value.details["champ"] == "jury"
    assert exc.value.regle == "EXG01"
    assert "EXG01" in _texte(exc)
    assert Defense.objects.count() == 1  # aucune réservation partielle


def test_sta01_meme_salle_chevauchement_refuse_avec_conflit_identifie():
    existante = creer_defense(
        creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0)
    )
    with pytest.raises(ConflitMetier) as exc:
        _planifier(creer_dossier(), creer_jury(), "Salle 101", t(9, 30), t(10, 30))
    assert exc.value.details["champ"] == "room_name"
    assert f"#{existante.pk}" in _texte(exc)  # le conflit est identifié
    assert Defense.objects.count() == 1


def test_creneau_inclus_dans_un_autre_refuse():
    jury = creer_jury()
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 12, 0))
    with pytest.raises(ConflitMetier):
        _planifier(creer_dossier(), creer_jury(), "Salle 101", t(10), t(11))


def test_soutenance_existante_incluse_dans_le_nouveau_creneau_refusee():
    """Cas « englobant inverse » : le nouveau créneau contient l'ancien."""
    creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(10, 0, 10, 30))
    with pytest.raises(ConflitMetier):
        _planifier(creer_dossier(), creer_jury(), "Salle 101", t(9), t(12))


def test_autre_salle_et_autre_jury_meme_horaire_acceptes():
    creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0))
    _planifier(creer_dossier(), creer_jury(), "Salle 102", t(9), t(10))
    assert Defense.objects.count() == 2


def test_membre_commun_a_deux_jurys_refuse():
    """Un même juré ne peut pas siéger dans deux jurys au même moment."""
    jury_a = creer_jury(noms=("Dr Traoré", "Dr Keita", "Dr Coulibaly"))
    jury_b = creer_jury(noms=("Dr Traoré", "Dr Diallo", "Dr Sidibé"))
    creer_defense(creer_dossier(), jury_a, "Salle 101", creneau(9, 0, 10, 0))
    with pytest.raises(ConflitMetier) as exc:
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


def test_sta02_creneaux_jointifs_refuses_si_marge_configuree(settings):
    """Avec 15 min de marge de déplacement, 10 h-11 h suit de trop près 9 h-10 h."""
    settings.SGSUS_MARGE_MINUTES = 15
    jury = creer_jury()
    _planifier(creer_dossier(), jury, "Salle 101", t(9), t(10))
    with pytest.raises(ConflitMetier) as exc:
        _planifier(creer_dossier(), jury, "Salle 101", t(10), t(11))
    assert exc.value.regle == "EXG01"
    assert Defense.objects.count() == 1
    # Au-delà de la marge, le créneau est accepté.
    _planifier(creer_dossier(), jury, "Salle 101", t(10, 15), t(11, 15))
    assert Defense.objects.count() == 2


def test_soutenance_annulee_libere_salle_et_jury():
    """Une réservation annulée n'est plus active : le créneau redevient libre."""
    jury = creer_jury()
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 10, 0), statut="annule")
    _planifier(creer_dossier(), jury, "Salle 101", t(9), t(10))
    assert Defense.objects.exclude(status="annule").count() == 1


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
    with pytest.raises(ConflitMetier):
        _planifier(
            dossier_b, jury_b, "Salle 101", t(9, 30), t(10, 30),
            defense_id=defense_b.pk,
        )
    assert Defense.objects.get(pk=defense_b.pk).slot_range.lower == t(11)


# ---------------------------------------------------------------------------
# F03 / STA05 : recevabilité du dossier
# ---------------------------------------------------------------------------

def test_dossier_brouillon_sans_avis_refuse():
    with pytest.raises(ConflitMetier) as exc:
        _planifier(creer_dossier("brouillon"), creer_jury(), "Salle 101", t(9), t(10))
    assert exc.value.details["champ"] == "folder"
    assert exc.value.regle == "F03"
    assert Defense.objects.count() == 0


def test_dossier_inexistant_refuse():
    with pytest.raises(ValidationError) as exc:
        conflicts.planifier_soutenance(999999, creer_jury().pk, "Salle 101", t(9), t(10))
    assert "n'existe pas" in _texte(exc)


def test_avis_favorable_seul_ne_suffit_pas_il_faut_l_autorisation():
    """
    F03 : l'avis favorable fait passer le dossier à « valide » ; seule
    l'autorisation du responsable le rend « recevable », donc planifiable.
    """
    dossier = creer_dossier("soumis")
    encadreur = affecter_encadreur(dossier)
    version = creer_version(dossier, numero=1)
    dossiers.enregistrer_avis_pedagogique(version.pk, encadreur, "favorable")
    dossier.refresh_from_db()
    assert dossier.status == "valide"
    with pytest.raises(ConflitMetier):
        _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))
    dossiers.autoriser_soutenance(dossier.pk, creer_compte("responsible"))
    _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))
    assert Defense.objects.count() == 1


def test_avis_defavorable_demande_une_correction():
    dossier = creer_dossier("soumis")
    encadreur = affecter_encadreur(dossier)
    version = creer_version(dossier, numero=1)
    dossiers.enregistrer_avis_pedagogique(version.pk, encadreur, "defavorable", "Bibliographie absente")
    dossier.refresh_from_db()
    assert dossier.status == "a_corriger"
    with pytest.raises(ConflitMetier):
        _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))


def test_sta11_avis_du_tuteur_seul_ne_permet_pas_l_autorisation():
    """STA11 : sans l'avis obligatoire de l'encadreur, l'autorisation est refusée."""
    dossier = creer_dossier("valide")
    creer_avis(dossier, "favorable", "tuteur")
    with pytest.raises(ConflitMetier) as exc:
        dossiers.autoriser_soutenance(dossier.pk, creer_compte("responsible"))
    assert exc.value.regle == "F03"
    dossier.refresh_from_db()
    assert dossier.status == "valide"  # état et décisions inchangés


def test_sta05_avis_sur_v1_ne_couvre_pas_une_v2():
    """Une nouvelle version du rapport impose un nouvel avis et une nouvelle autorisation."""
    dossier = creer_dossier("soumis")
    encadreur = affecter_encadreur(dossier)
    responsable = creer_compte("responsible")
    v1 = creer_version(dossier, numero=1)
    avis_v1 = dossiers.enregistrer_avis_pedagogique(v1.pk, encadreur, "favorable")
    dossiers.autoriser_soutenance(dossier.pk, responsable)
    # Dépôt de la V2 : le dossier repasse à « soumis », l'avis reste sur V1.
    v2 = creer_version(dossier, numero=2)
    dossier.refresh_from_db()  # comme le dépôt, qui relit le dossier verrouillé
    dossiers.apres_nouvelle_version(dossier, v2, None)
    dossier.refresh_from_db()
    assert dossier.status == "soumis"
    avis_v1.refresh_from_db()
    assert avis_v1.document_version_id == v1.pk
    with pytest.raises(ConflitMetier):
        _planifier(dossier, creer_jury(), "Salle 101", t(9), t(10))
    assert Defense.objects.count() == 0
    # Un avis sur l'ANCIENNE version est refusé : il doit porter sur la V2.
    with pytest.raises(ConflitMetier) as exc:
        dossiers.enregistrer_avis_pedagogique(v1.pk, encadreur, "favorable")
    assert exc.value.regle == "STA05"
    dossiers.enregistrer_avis_pedagogique(v2.pk, encadreur, "favorable")
    dossiers.autoriser_soutenance(dossier.pk, responsable)
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
