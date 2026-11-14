"""
Tests SANS base de données : validation des horaires, traduction des
contraintes PostgreSQL, lecture des paramètres de date.

Aucun marqueur django_db : pytest-django interdit tout accès à la base dans
ce fichier, ce qui prouve que ces règles ne dépendent pas de PostgreSQL.
"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest import mock

import pytest
from django.db.utils import IntegrityError
from rest_framework.exceptions import ValidationError
from rest_framework.request import Request
from rest_framework.test import APIRequestFactory

from api import views
from api.services import conflicts

UTC = timezone.utc


def _debut():
    return datetime(2026, 7, 10, 9, 0, tzinfo=UTC)


def _texte(exc_info):
    return str(exc_info.value.detail)


# ---------------------------------------------------------------------------
# construire_creneau : bornes, UTC, durée
# ---------------------------------------------------------------------------

class TestConstruireCreneau:
    def test_creneau_valide_bornes_fermee_ouverte(self):
        slot = conflicts.construire_creneau(_debut(), _debut() + timedelta(hours=1))
        assert slot.lower_inc is True
        assert slot.upper_inc is False
        assert slot.lower == _debut()
        assert slot.upper == _debut() + timedelta(hours=1)

    def test_conversion_en_utc_nfr04(self):
        slot = conflicts.construire_creneau(
            "2026-07-10T09:00:00+02:00", "2026-07-10T10:00:00+02:00"
        )
        assert slot.lower == datetime(2026, 7, 10, 7, 0, tzinfo=UTC)
        assert slot.upper == datetime(2026, 7, 10, 8, 0, tzinfo=UTC)

    def test_date_sans_fuseau_interpretee_en_utc(self):
        slot = conflicts.construire_creneau(
            datetime(2026, 7, 10, 9, 0), datetime(2026, 7, 10, 10, 0)
        )
        assert slot.lower.tzinfo is not None
        assert slot.lower == _debut()

    def test_chaine_iso_avec_z(self):
        slot = conflicts.construire_creneau(
            "2026-07-10T09:00:00Z", "2026-07-10T10:30:00Z"
        )
        assert slot.upper - slot.lower == timedelta(hours=1, minutes=30)

    def test_fin_egale_au_debut_refusee(self):
        with pytest.raises(ValidationError) as exc:
            conflicts.construire_creneau(_debut(), _debut())
        assert "slot_end" in exc.value.detail

    def test_fin_avant_debut_refusee(self):
        with pytest.raises(ValidationError) as exc:
            conflicts.construire_creneau(_debut(), _debut() - timedelta(minutes=1))
        assert "slot_end" in exc.value.detail

    def test_duree_de_huit_heures_acceptee(self):
        slot = conflicts.construire_creneau(_debut(), _debut() + timedelta(hours=8))
        assert slot.upper - slot.lower == timedelta(hours=8)

    def test_duree_superieure_a_huit_heures_refusee(self):
        with pytest.raises(ValidationError) as exc:
            conflicts.construire_creneau(
                _debut(), _debut() + timedelta(hours=8, minutes=1)
            )
        assert "8 heures" in _texte(exc)

    def test_format_de_date_invalide(self):
        with pytest.raises(ValidationError) as exc:
            conflicts.construire_creneau("pas-une-date", _debut())
        assert "slot_start" in exc.value.detail
        assert "ISO 8601" in _texte(exc)

    def test_type_invalide(self):
        with pytest.raises(ValidationError) as exc:
            conflicts.construire_creneau(12345, _debut())
        assert "slot_start" in exc.value.detail

    def test_creneaux_jointifs_ne_se_chevauchent_pas(self):
        """STA02 (niveau intervalle) : [9h,10h) et [10h,11h) sont disjoints."""
        a = conflicts.construire_creneau(_debut(), _debut() + timedelta(hours=1))
        b = conflicts.construire_creneau(
            _debut() + timedelta(hours=1), _debut() + timedelta(hours=2)
        )
        assert a.upper == b.lower
        assert a.lower_inc is True and a.upper_inc is False
        assert b.lower_inc is True and b.upper_inc is False
    def test_formater_creneau_lisible(self):
        slot = conflicts.construire_creneau(_debut(), _debut() + timedelta(hours=1))
        assert conflicts.formater_creneau(slot) == "10/07/2026 09:00 → 10:00 UTC"


# ---------------------------------------------------------------------------
# Contrôles qui ne lisent la base que via des objets simulés
# ---------------------------------------------------------------------------

class TestSalleSimulee:
    def test_salle_inexistante(self):
        with mock.patch.object(conflicts, "Room") as room:
            room.objects.filter.return_value.first.return_value = None
            with pytest.raises(ValidationError) as exc:
                conflicts.verifier_salle_existe_et_active("Salle fantôme")
        assert "room_name" in exc.value.detail
        assert "n'existe pas" in _texte(exc)

    def test_salle_inactive(self):
        with mock.patch.object(conflicts, "Room") as room:
            room.objects.filter.return_value.first.return_value = SimpleNamespace(
                is_active=False
            )
            with pytest.raises(ValidationError) as exc:
                conflicts.verifier_salle_existe_et_active("Salle 101")
        assert "inactive" in _texte(exc)

    def test_salle_active_acceptee(self):
        salle = SimpleNamespace(is_active=True)
        with mock.patch.object(conflicts, "Room") as room:
            room.objects.filter.return_value.first.return_value = salle
            assert conflicts.verifier_salle_existe_et_active("Salle 101") is salle


class TestOrdreDesControles:
    def test_dossier_non_recevable_arrete_tout_avant_les_conflits(self):
        """F03 : un dossier non recevable est rejeté avant tout autre contrôle."""
        slot = conflicts.construire_creneau(_debut(), _debut() + timedelta(hours=1))
        erreur = ValidationError({"folder": "non recevable"})
        with mock.patch.object(
            conflicts, "verifier_dossier_recevable", side_effect=erreur
        ), mock.patch.object(conflicts, "Jury") as jury, mock.patch.object(
            conflicts, "verifier_conflit_salle"
        ) as conflit_salle:
            with pytest.raises(ValidationError) as exc:
                conflicts.verifier_toutes_regles(1, 1, "Salle 101", slot)
        assert "folder" in exc.value.detail
        jury.objects.get.assert_not_called()
        conflit_salle.assert_not_called()


# ---------------------------------------------------------------------------
# Traduction des contraintes PostgreSQL
# ---------------------------------------------------------------------------

class TestTraductionIntegrityError:
    @pytest.mark.parametrize(
        "contrainte, mot_cle",
        [
            ("prevent_room_double_booking", "salle"),
            ("prevent_jury_double_booking", "jury"),
        ],
    )
    def test_contraintes_exg01_traduites(self, contrainte, mot_cle):
        erreur = IntegrityError(
            f'conflicting key value violates exclusion constraint "{contrainte}"'
        )
        traduite = conflicts.traduire_integrity_error(erreur)
        assert isinstance(traduite, ValidationError)
        message = str(traduite.detail["detail"])
        assert mot_cle in message and "EXG01" in message

    def test_contrainte_inconnue_n_est_pas_presentee_comme_un_conflit(self):
        traduite = conflicts.traduire_integrity_error(IntegrityError("autre chose"))
        assert traduite is None


# ---------------------------------------------------------------------------
# Lecture des paramètres de requête (planning par date / période)
# ---------------------------------------------------------------------------

def _requete(**params):
    return Request(APIRequestFactory().get("/api/soutenances/planning/", params))


class TestParametreDate:
    def test_date_valide(self):
        assert views._parametre_date(_requete(date="2026-07-10"), "date").isoformat() == "2026-07-10"

    def test_parametre_absent_facultatif(self):
        assert views._parametre_date(_requete(), "date") is None

    def test_parametre_absent_obligatoire(self):
        with pytest.raises(ValidationError) as exc:
            views._parametre_date(_requete(), "date", obligatoire=True)
        assert "date" in exc.value.detail

    @pytest.mark.parametrize("valeur", ["10/07/2026", "2026-13-40", "demain"])
    def test_format_invalide(self, valeur):
        with pytest.raises(ValidationError) as exc:
            views._parametre_date(_requete(date=valeur), "date")
        assert "YYYY-MM-DD" in _texte(exc)

    def test_jour_utc_debut_de_journee(self):
        jour = datetime(2026, 7, 10).date()
        assert views._jour_UTC(jour) == datetime(2026, 7, 10, 0, 0, tzinfo=UTC)
