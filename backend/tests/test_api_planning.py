"""
Tests de l'API REST du module planification (salles, soutenances, planning).

Hypothèses à vérifier sur DefenseSerializer : les champs d'entrée sont
`folder`, `jury`, `room_name`, `slot_start`, `slot_end` (le planning trie sur
`slot_start`). Si vos noms diffèrent, adaptez `_payload`.
Hypothèse d'accès : les routes ne demandent pas encore d'authentification.
"""

from datetime import datetime

import pytest
from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework.test import APIClient

from api.models import Defense, Room

from .factories import creer_defense, creer_dossier, creer_jury, creneau

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("salles_demo")]


@pytest.fixture
def client(db):
    client = APIClient()
    user = get_user_model().objects.create_superuser(
        username="planning_test_admin",
        email="planning-admin@example.test",
        password="Sgsus-Test-Password!2026",
    )
    client.force_authenticate(user=user)
    return client


def _payload(dossier, jury, salle="Salle 101",
             debut="2026-07-10T09:00:00Z", fin="2026-07-10T10:00:00Z"):
    return {
        "folder": dossier.pk,
        "jury": jury.pk,
        "room_name": salle,
        "slot_start": debut,
        "slot_end": fin,
    }


# ---------------------------------------------------------------------------
# Création de soutenances
# ---------------------------------------------------------------------------

def test_creation_valide_renvoie_201(client):
    reponse = client.post(
        reverse("soutenance-list"), _payload(creer_dossier(), creer_jury()),
        format="json",
    )
    assert reponse.status_code == 201, reponse.content
    assert Defense.objects.count() == 1


def test_creation_en_conflit_renvoie_400_sans_ecriture(client):
    creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0))
    reponse = client.post(
        reverse("soutenance-list"),
        _payload(creer_dossier(), creer_jury(),
                 debut="2026-07-10T09:30:00Z", fin="2026-07-10T10:30:00Z"),
        format="json",
    )
    assert reponse.status_code == 400
    assert "EXG01" in str(reponse.json())
    assert Defense.objects.count() == 1


def test_creation_creneaux_jointifs_acceptee(client):
    jury = creer_jury()
    creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 10, 0))
    reponse = client.post(
        reverse("soutenance-list"),
        _payload(creer_dossier(), jury,
                 debut="2026-07-10T10:00:00Z", fin="2026-07-10T11:00:00Z"),
        format="json",
    )
    assert reponse.status_code == 201, reponse.content


def test_creation_dossier_non_recevable_renvoie_400(client):
    reponse = client.post(
        reverse("soutenance-list"),
        _payload(creer_dossier("brouillon"), creer_jury()),
        format="json",
    )
    assert reponse.status_code == 400
    assert Defense.objects.count() == 0


def test_creation_fin_avant_debut_renvoie_400(client):
    reponse = client.post(
        reverse("soutenance-list"),
        _payload(creer_dossier(), creer_jury(),
                 debut="2026-07-10T10:00:00Z", fin="2026-07-10T09:00:00Z"),
        format="json",
    )
    assert reponse.status_code == 400
    assert Defense.objects.count() == 0


# ---------------------------------------------------------------------------
# Planning par date / période
# ---------------------------------------------------------------------------

@pytest.fixture
def planning_de_test():
    """Deux soutenances le 10 juillet (11h puis 9h), une le 11 juillet."""
    creer_defense(creer_dossier(), creer_jury(), "Salle 102", creneau(11, 0, 12, 0))
    creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0))
    creer_defense(creer_dossier(), creer_jury(), "Salle 101",
                  creneau(9, 0, 10, 0, jour=11))


def test_planning_d_une_date_trie_par_heure(client, planning_de_test):
    reponse = client.get(reverse("soutenance-planning"), {"date": "2026-07-10"})
    assert reponse.status_code == 200
    corps = reponse.json()
    assert corps["total"] == 2
    debuts = [s["slot_start"] for s in corps["soutenances"]]
    assert debuts == sorted(debuts)


def test_planning_periode(client, planning_de_test):
    reponse = client.get(
        reverse("soutenance-planning"),
        {"date_debut": "2026-07-10", "date_fin": "2026-07-11"},
    )
    assert reponse.json()["total"] == 3


def test_planning_filtre_par_salle(client, planning_de_test):
    reponse = client.get(
        reverse("soutenance-planning"), {"date": "2026-07-10", "salle": "Salle 102"}
    )
    assert reponse.json()["total"] == 1


def test_planning_date_invalide_renvoie_400(client):
    reponse = client.get(reverse("soutenance-planning"), {"date": "10-07-2026"})
    assert reponse.status_code == 400


def test_planning_periode_inversee_renvoie_400(client):
    reponse = client.get(
        reverse("soutenance-planning"),
        {"date_debut": "2026-07-12", "date_fin": "2026-07-10"},
    )
    assert reponse.status_code == 400


def test_planning_jury_invalide_renvoie_400(client):
    reponse = client.get(reverse("soutenance-planning"), {"jury": "abc"})
    assert reponse.status_code == 400


# ---------------------------------------------------------------------------
# Disponibilités d'une salle
# ---------------------------------------------------------------------------

def test_disponibilites_salle_creneaux_occupes_et_libres(client):
    creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0))
    salle = Room.objects.get(name="Salle 101")
    reponse = client.get(
        reverse("salle-disponibilites", args=[salle.pk]), {"date": "2026-07-10"}
    )
    assert reponse.status_code == 200
    corps = reponse.json()
    assert len(corps["creneaux_occupes"]) == 1
    libres = [
        (datetime.fromisoformat(c["debut"]).hour, datetime.fromisoformat(c["fin"]).hour)
        for c in corps["creneaux_libres"]
    ]
    assert libres == [(8, 9), (10, 20)]


def test_disponibilites_sans_date_renvoie_400(client):
    salle = Room.objects.get(name="Salle 101")
    reponse = client.get(reverse("salle-disponibilites", args=[salle.pk]))
    assert reponse.status_code == 400
