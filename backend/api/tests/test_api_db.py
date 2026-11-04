"""
Tests d'intégration de l'API REST (module planification, Tâche 4).

Endpoints couverts :

* /api/salles/ + /api/salles/{id}/disponibilites/
* /api/jurys/ + /api/membres-jury/
* /api/soutenances/ (création/modification avec contrôle EXG01)
* /api/soutenances/planning/ (lecture, filtres date/période/salle/statut)

Chaque erreur métier doit renvoyer HTTP 400 avec un message exploitable par
Flutter (structure par champ ou {"detail": ...}).
"""

from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from api.models import (
    Campaign,
    InternshipFolder,
    Jury,
    JuryMember,
    Room,
    Student,
)

UTC = timezone.utc
JOUR = "2026-07-10"


class DonneesApi(APITestCase):
    """Données et helpers communs aux tests API."""

    @classmethod
    def setUpTestData(cls):
        cls.campagne = Campaign.objects.create(
            academic_year="2025-2026", is_active=True
        )
        cls.etudiant = Student.objects.create(
            student_number="2026-API-01",
            full_name="Étudiant API",
            email="etudiant.api@etu-test.edu",
        )
        cls.dossier = InternshipFolder.objects.create(
            student=cls.etudiant,
            campaign=cls.campagne,
            company_name="NSIA Banque",
            subject="Digitalisation des guichets",
            status="recevable",
        )
        cls.salle_a = Room.objects.create(name="Salle API A", capacity=30)
        cls.salle_b = Room.objects.create(name="Salle API B", capacity=20)
        cls.jury1 = Jury.objects.create(name="Jury API 1", is_complete=True)
        JuryMember.objects.create(
            jury=cls.jury1, member_name="A. Traoré", role_in_jury="president"
        )
        JuryMember.objects.create(
            jury=cls.jury1, member_name="B. Diarra", role_in_jury="rapporteur"
        )
        cls.jury2 = Jury.objects.create(name="Jury API 2", is_complete=True)
        JuryMember.objects.create(
            jury=cls.jury2, member_name="C. Sanogo", role_in_jury="president"
        )

    @staticmethod
    def creneau_iso(heure_debut, heure_fin):
        return (
            f"{JOUR}T{heure_debut:02d}:00:00Z",
            f"{JOUR}T{heure_fin:02d}:00:00Z",
        )

    def payload_soutenance(self, salle=None, jury=None, dossier=None,
                           heure_debut=8, heure_fin=10):
        """Payload JSON ; salle = nom textuel, jury/dossier = identifiants."""
        debut, fin = self.creneau_iso(heure_debut, heure_fin)
        return {
            "folder": self.dossier.pk if dossier is None else dossier,
            "jury": self.jury1.pk if jury is None else jury,
            "room_name": salle or self.salle_a.name,
            "slot_start": debut,
            "slot_end": fin,
            "status": "planifie",
        }

    def creer_soutenance(self, **kwargs):
        return self.client.post(
            reverse("soutenance-list"),
            self.payload_soutenance(**kwargs),
            format="json",
        )


class SalleApiTests(DonneesApi):
    """Catalogue des salles."""

    def test_creation_salle_valide(self):
        reponse = self.client.post(
            reverse("salle-list"),
            {"name": "  Salle API C  ", "capacity": 35},
            format="json",
        )
        self.assertEqual(reponse.status_code, 201)
        self.assertEqual(reponse.data["name"], "Salle API C")
        self.assertTrue(reponse.data["is_active"])

    def test_capacite_nulle_refusee(self):
        reponse = self.client.post(
            reverse("salle-list"),
            {"name": "Salle API D", "capacity": 0},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)

    def test_liste_salles(self):
        reponse = self.client.get(reverse("salle-list"))
        self.assertEqual(reponse.status_code, 200)
        noms = [item["name"] for item in reponse.data]
        self.assertIn(self.salle_a.name, noms)


class JuryApiTests(DonneesApi):
    """Jurys et membres (F04)."""

    def test_creation_jury_avec_membres_imbriques_en_lecture(self):
        reponse = self.client.post(
            reverse("jury-list"), {"name": "Jury API 3"}, format="json"
        )
        self.assertEqual(reponse.status_code, 201)
        jury_id = reponse.data["id"]

        membre = self.client.post(
            reverse("membre-jury-list"),
            {"jury": jury_id, "member_name": "E. Touré", "role_in_jury": "examinateur"},
            format="json",
        )
        self.assertEqual(membre.status_code, 201)

        detail = self.client.get(reverse("jury-detail", args=[jury_id]))
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(len(detail.data["members"]), 1)
        self.assertEqual(detail.data["members"][0]["member_name"], "E. Touré")

    def test_role_invalide_refuse(self):
        reponse = self.client.post(
            reverse("membre-jury-list"),
            {"jury": self.jury1.pk, "member_name": "X. Y", "role_in_jury": "chef"},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("role_in_jury", str(reponse.data))


class SoutenanceApiTests(DonneesApi):
    """Cycle de vie d'une soutenance avec contrôle des conflits EXG01."""

    def test_creation_valide_201(self):
        reponse = self.creer_soutenance()
        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["room_name"], self.salle_a.name)
        self.assertTrue(
            reponse.data["slot_start"].startswith(f"{JOUR}T08:00"),
            reponse.data["slot_start"],
        )
        self.assertTrue(
            reponse.data["slot_end"].startswith(f"{JOUR}T10:00"),
            reponse.data["slot_end"],
        )

    def test_conflit_meme_salle_meme_horaire_400(self):
        # Scénario de démonstration : 2e soutenance, même salle, même horaire.
        premiere = self.creer_soutenance()
        self.assertEqual(premiere.status_code, 201, premiere.data)
        conflit = self.creer_soutenance(jury=self.jury2)
        self.assertEqual(conflit.status_code, 400)
        self.assertIn("EXG01", str(conflit.data))

    def test_conflit_meme_jury_autre_salle_400(self):
        premiere = self.creer_soutenance()
        self.assertEqual(premiere.status_code, 201, premiere.data)
        conflit = self.creer_soutenance(salle=self.salle_b.name)
        self.assertEqual(conflit.status_code, 400)

    def test_horaires_inverses_400(self):
        reponse = self.creer_soutenance(heure_debut=10, heure_fin=8)
        self.assertEqual(reponse.status_code, 400)

    def test_dossier_non_recevable_400(self):
        dossier_brouillon = InternshipFolder.objects.create(
            student=self.etudiant,
            campaign=self.campagne,
            company_name="Orange Mali",
            subject="App mobile",
            status="brouillon",
        )
        reponse = self.creer_soutenance(dossier=dossier_brouillon.pk)
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("folder", str(reponse.data))

    def test_salle_inexistante_400(self):
        reponse = self.creer_soutenance(salle="Salle Fantôme")
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("room_name", str(reponse.data))

    def test_jury_inexistant_400(self):
        reponse = self.creer_soutenance(jury=999999)
        self.assertEqual(reponse.status_code, 400)

    def test_patch_deplacement_creneau_valide(self):
        premiere = self.creer_soutenance()
        self.assertEqual(premiere.status_code, 201, premiere.data)
        soutenance_id = premiere.data["id"]

        debut, fin = self.creneau_iso(14, 16)
        reponse = self.client.patch(
            reverse("soutenance-detail", args=[soutenance_id]),
            {"slot_start": debut, "slot_end": fin},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertTrue(reponse.data["slot_start"].startswith(f"{JOUR}T14:00"))

    def test_patch_conflit_refuse(self):
        premiere = self.creer_soutenance()
        self.assertEqual(premiere.status_code, 201, premiere.data)
        seconde = self.creer_soutenance(salle=self.salle_b.name, jury=self.jury2)
        self.assertEqual(seconde.status_code, 201, seconde.data)

        debut, fin = self.creneau_iso(9, 11)  # chevauche la première (08-10)
        reponse = self.client.patch(
            reverse("soutenance-detail", args=[seconde.data["id"]]),
            {"room_name": self.salle_a.name, "slot_start": debut, "slot_end": fin},
            format="json",
        )
        self.assertEqual(reponse.status_code, 400)
        self.assertIn("EXG01", str(reponse.data))

    def test_patch_apres_conflit_on_peut_choisir_autre_salle(self):
        # Suite du scénario de démo : refus puis choix d'un autre créneau/salle.
        premiere = self.creer_soutenance()
        seconde = self.creer_soutenance(salle=self.salle_b.name, jury=self.jury2)
        self.assertEqual(premiere.status_code, 201)
        self.assertEqual(seconde.status_code, 201)

        debut, fin = self.creneau_iso(12, 14)
        reponse = self.client.patch(
            reverse("soutenance-detail", args=[seconde.data["id"]]),
            {"room_name": self.salle_a.name, "slot_start": debut, "slot_end": fin},
            format="json",
        )
        self.assertEqual(reponse.status_code, 200, reponse.data)
        self.assertEqual(reponse.data["room_name"], self.salle_a.name)

    def test_planning_filtre_par_date(self):
        self.creer_soutenance()
        planning = self.client.get(
            reverse("soutenance-planning"), {"date": JOUR}
        )
        self.assertEqual(planning.status_code, 200)
        self.assertEqual(planning.data["total"], 1)

        vide = self.client.get(
            reverse("soutenance-planning"), {"date": "2026-07-11"}
        )
        self.assertEqual(vide.data["total"], 0)

    def test_planning_filtre_par_periode(self):
        self.creer_soutenance()  # 08:00-10:00 le JOUR
        planning = self.client.get(
            reverse("soutenance-planning"),
            {"date_debut": JOUR, "date_fin": "2026-07-12"},
        )
        self.assertEqual(planning.data["total"], 1)
        vide = self.client.get(
            reverse("soutenance-planning"),
            {"date_debut": "2026-07-11", "date_fin": "2026-07-12"},
        )
        self.assertEqual(vide.data["total"], 0)

    def test_planning_filtre_par_salle_et_statut(self):
        self.creer_soutenance()  # salle A / statut planifie
        planning = self.client.get(
            reverse("soutenance-planning"), {"salle": self.salle_a.name}
        )
        self.assertEqual(planning.data["total"], 1)
        planning_b = self.client.get(
            reverse("soutenance-planning"), {"salle": self.salle_b.name}
        )
        self.assertEqual(planning_b.data["total"], 0)
        statut = self.client.get(
            reverse("soutenance-planning"), {"statut": "planifie"}
        )
        self.assertEqual(statut.data["total"], 1)
        statut_inconnu = self.client.get(
            reverse("soutenance-planning"), {"statut": "terminee"}
        )
        self.assertEqual(statut_inconnu.data["total"], 0)

    def test_planning_tri_chronologique(self):
        # Création dans le désordre : 10-12 d'abord, 08-10 ensuite.
        premiere = self.creer_soutenance(heure_debut=10, heure_fin=12)
        self.assertEqual(premiere.status_code, 201, premiere.data)
        seconde = self.creer_soutenance(
            salle=self.salle_b.name, jury=self.jury2,
            heure_debut=8, heure_fin=10,
        )
        self.assertEqual(seconde.status_code, 201, seconde.data)

        planning = self.client.get(reverse("soutenance-planning"))
        horaires = [s["slot_start"] for s in planning.data["soutenances"]]
        self.assertEqual(len(horaires), 2)
        self.assertTrue(horaires[0] < horaires[1], horaires)


class DisponibilitesApiTests(DonneesApi):
    """Créneaux occupés/libres d'une salle (GET /api/salles/{id}/disponibilites/)."""

    def test_sans_reservation_journee_libre(self):
        reponse = self.client.get(
            reverse("salle-disponibilites", args=[self.salle_a.pk]),
            {"date": JOUR},
        )
        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(reponse.data["creneaux_occupes"], [])
        libres = reponse.data["creneaux_libres"]
        self.assertEqual(len(libres), 1)
        self.assertTrue(libres[0]["debut"].startswith(f"{JOUR}T08:00"))
        self.assertTrue(libres[0]["fin"].startswith(f"{JOUR}T20:00"))

    def test_avec_reservation_creneau_retranche(self):
        self.creer_soutenance()  # 08:00-10:00 dans salle A
        reponse = self.client.get(
            reverse("salle-disponibilites", args=[self.salle_a.pk]),
            {"date": JOUR},
        )
        occupes = reponse.data["creneaux_occupes"]
        self.assertEqual(len(occupes), 1)
        self.assertTrue(occupes[0]["debut"].startswith(f"{JOUR}T08:00"))
        self.assertEqual(occupes[0]["statut"], "planifie")

        libres = reponse.data["creneaux_libres"]
        self.assertEqual(len(libres), 1)
        self.assertTrue(libres[0]["debut"].startswith(f"{JOUR}T10:00"))
        self.assertTrue(libres[0]["fin"].startswith(f"{JOUR}T20:00"))

    def test_date_manquante_400(self):
        reponse = self.client.get(
            reverse("salle-disponibilites", args=[self.salle_a.pk])
        )
        self.assertEqual(reponse.status_code, 400)

    def test_date_invalide_400(self):
        reponse = self.client.get(
            reverse("salle-disponibilites", args=[self.salle_a.pk]),
            {"date": "10/07/2026"},
        )
        self.assertEqual(reponse.status_code, 400)
