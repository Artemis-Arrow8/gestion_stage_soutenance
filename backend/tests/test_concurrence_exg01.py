"""
STA03 : deux publications simultanées du même créneau.

Ces tests utilisent de VRAIES transactions et DEUX connexions PostgreSQL
(un thread = une connexion). Un test séquentiel ou sur SQLite ne démontrerait
pas la résistance aux opérations simultanées.
"""

import threading
from unittest import mock

import pytest
from django.db import connections
from rest_framework.exceptions import ValidationError

from api.models import Defense
from api.services import conflicts

from .factories import creer_dossier, creer_jury, t

pytestmark = pytest.mark.usefixtures("base_propre", "salles_demo")


def _lancer_en_parallele(taches):
    """
    Exécute chaque tâche dans son propre thread (donc sa propre connexion),
    démarrage synchronisé par une barrière. Retourne la liste des résultats.
    """
    barriere = threading.Barrier(len(taches))
    resultats = []
    verrou = threading.Lock()

    def travailleur(tache):
        try:
            barriere.wait(timeout=15)
            tache()
            issue = ("ok", None)
        except ValidationError as erreur:
            issue = ("conflit", str(erreur.detail))
        except Exception as erreur:  # noqa: BLE001 - on veut tout voir
            issue = ("erreur", repr(erreur))
        finally:
            connections.close_all()
        with verrou:
            resultats.append(issue)

    fils = [threading.Thread(target=travailleur, args=(t_,)) for t_ in taches]
    for fil in fils:
        fil.start()
    for fil in fils:
        fil.join(timeout=30)
        assert not fil.is_alive(), "un thread est resté bloqué (verrou ?)"
    return resultats


def _verifier_un_seul_gagnant(resultats):
    issues = sorted(r[0] for r in resultats)
    assert issues == ["conflit", "ok"], resultats
    assert Defense.objects.count() == 1


def test_sta03_meme_salle_une_seule_reservation_validee():
    dossier_1, dossier_2 = creer_dossier(), creer_dossier()
    jury_1, jury_2 = creer_jury(), creer_jury()

    def publier(dossier, jury):
        return lambda: conflicts.planifier_soutenance(
            dossier.pk, jury.pk, "Salle 101", t(9), t(10)
        )

    resultats = _lancer_en_parallele(
        [publier(dossier_1, jury_1), publier(dossier_2, jury_2)]
    )
    _verifier_un_seul_gagnant(resultats)


def test_sta03_meme_jury_une_seule_reservation_validee():
    jury = creer_jury()
    dossier_1, dossier_2 = creer_dossier(), creer_dossier()

    def publier(dossier, salle):
        return lambda: conflicts.planifier_soutenance(
            dossier.pk, jury.pk, salle, t(9), t(10)
        )

    resultats = _lancer_en_parallele(
        [publier(dossier_1, "Salle 101"), publier(dossier_2, "Salle 102")]
    )
    _verifier_un_seul_gagnant(resultats)


def test_sta03_meme_membre_dans_deux_jurys_une_seule_reservation_validee():
    dossier_1, dossier_2 = creer_dossier(), creer_dossier()
    jury_1 = creer_jury(noms=("Dr Commun", "Dr Traoré"))
    jury_2 = creer_jury(noms=("Dr Commun", "Dr Keita"))

    def publier(dossier, jury, salle):
        return lambda: conflicts.planifier_soutenance(
            dossier.pk, jury.pk, salle, t(9), t(10)
        )

    resultats = _lancer_en_parallele([
        publier(dossier_1, jury_1, "Salle 101"),
        publier(dossier_2, jury_2, "Salle 102"),
    ])
    _verifier_un_seul_gagnant(resultats)
    message = next(r[1] for r in resultats if r[0] == "conflit")
    assert "Dr Commun" in message


def test_filet_de_securite_base_quand_le_controle_applicatif_est_contourne():
    """
    On désactive les contrôles applicatifs : les deux threads passent donc
    « le premier contrôle ». C'est la contrainte d'exclusion PostgreSQL qui
    doit trancher, et l'IntegrityError doit être traduite en erreur lisible.
    """
    dossier_1, dossier_2 = creer_dossier(), creer_dossier()
    jury_1, jury_2 = creer_jury(), creer_jury()

    def publier(dossier, jury):
        return lambda: conflicts.planifier_soutenance(
            dossier.pk, jury.pk, "Salle 101", t(9), t(10)
        )

    with mock.patch.object(conflicts, "verifier_toutes_regles"):
        resultats = _lancer_en_parallele(
            [publier(dossier_1, jury_1), publier(dossier_2, jury_2)]
        )

    _verifier_un_seul_gagnant(resultats)
    message = next(r[1] for r in resultats if r[0] == "conflit")
    assert "EXG01" in message


def test_creneaux_disjoints_en_parallele_sont_tous_acceptes():
    """Contre-épreuve : la protection ne bloque pas les créneaux légitimes."""
    dossiers = [creer_dossier(), creer_dossier()]
    jurys = [creer_jury(), creer_jury()]
    horaires = [(t(9), t(10)), (t(10), t(11))]

    def publier(i):
        return lambda: conflicts.planifier_soutenance(
            dossiers[i].pk, jurys[i].pk, "Salle 101", *horaires[i]
        )

    resultats = _lancer_en_parallele([publier(0), publier(1)])
    assert [r[0] for r in resultats] == ["ok", "ok"], resultats
    assert Defense.objects.count() == 2
