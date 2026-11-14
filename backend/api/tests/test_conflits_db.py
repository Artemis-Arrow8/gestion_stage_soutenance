"""
Tests d'intégration des règles métier contre une base PostgreSQL réelle.

La base de test est créée et remplie par ``config.test_runner.SchemaTestRunner``
qui exécute ``database/schema.sql`` : les contraintes d'exclusion EXG01
(``prevent_room_double_booking``, ``prevent_jury_double_booking``) sont donc
actives, exactement comme en production.
"""

from datetime import datetime

from django.db import IntegrityError, transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.test import TestCase
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from api.models import (
    Campaign,
    Defense,
    DocumentVersion,
    InternshipFolder,
    Jury,
    JuryMember,
    Review,
    Room,
    Student,
)
from api.services import conflicts

UTC = timezone.UTC

# Créneau de référence des tests : 2026-07-10 (pas d'effet de bord réel,
# table de test dédiée).
JOUR = datetime(2026, 7, 10)


def creneau(heure_debut, heure_fin, jour=JOUR):
    """Intervalle [debut, fin) en UTC pour la journée de test."""
    return DateTimeTZRange(
        datetime(jour.year, jour.month, jour.day, heure_debut, tzinfo=UTC),
        datetime(jour.year, jour.month, jour.day, heure_fin, tzinfo=UTC),
        bounds="[)",
    )


class DonneesDeBase(TestCase):
    """Jeu de données commun : campagne, étudiant, dossiers, salles, jurys."""

    @classmethod
    def setUpTestData(cls):
        cls.campagne = Campaign.objects.create(
            academic_year="2025-2026", is_active=True
        )
        cls.etudiant = Student.objects.create(
            student_number="2026-001",
            full_name="Mariam Diarra",
            email="mariam.diarra@etu-test.edu",
        )
        # Dossier explicitement recevable (statut)
        cls.dossier_recevable = InternshipFolder.objects.create(
            student=cls.etudiant,
            campaign=cls.campagne,
            company_name="NSIA Banque",
            subject="Digitalisation des guichets",
            status="recevable",
        )
        # Dossier au statut par défaut (brouillon) : recevabilité à prouver
        # par un avis d'encadreur sur la dernière version de document.
        cls.dossier_brouillon = InternshipFolder.objects.create(
            student=cls.etudiant,
            campaign=cls.campagne,
            company_name="Orange Mali",
            subject="Application mobile de paiement",
            status="brouillon",
        )
        # Salles (noms propres aux tests, hors salles de démonstration)
        cls.salle_a = Room.objects.create(name="Salle Test Alpha", capacity=30)
        cls.salle_b = Room.objects.create(name="Salle Test Beta", capacity=25)
        cls.salle_inactive = Room.objects.create(
            name="Salle Test Inactive", capacity=10, is_active=False
        )
        # Jury 1 : deux membres
        cls.jury1 = Jury.objects.create(name="Jury Test 1", is_complete=True)
        JuryMember.objects.create(
            jury=cls.jury1, member_name="A. Traoré", role_in_jury="president"
        )
        JuryMember.objects.create(
            jury=cls.jury1, member_name="B. Diarra", role_in_jury="rapporteur"
        )
        # Jury 2 : un membre en commun avec jury1 (B. Diarra) => chevauchement
        # croisé possible
        cls.jury2 = Jury.objects.create(name="Jury Test 2", is_complete=True)
        JuryMember.objects.create(
            jury=cls.jury2, member_name="B. Diarra", role_in_jury="president"
        )
        JuryMember.objects.create(
            jury=cls.jury2, member_name="C. Sanogo", role_in_jury="examinateur"
        )
        # Jury 3 : membres totalement distincts
        cls.jury3 = Jury.objects.create(name="Jury Test 3", is_complete=True)
        JuryMember.objects.create(
            jury=cls.jury3, member_name="D. Cissé", role_in_jury="president"
        )
        JuryMember.objects.create(
            jury=cls.jury3, member_name="E. Touré", role_in_jury="rapporteur"
        )
        # Jury vide (aucun membre)
        cls.jury_vide = Jury.objects.create(name="Jury Test Vide")

    def regles_ok(self, dossier, jury, salle, slot):
        """Appel utilitaire : ne doit pas lever."""
        return conflicts.verifier_toutes_regles(
            dossier.pk, jury.pk, salle.name, slot
        )


class RecevabiliteDossierTests(DonneesDeBase):
    """F03 : avis de recevabilité de l'encadreur."""

    def test_statut_explicitement_recevable_passe(self):
        dossier, jury = self.regles_ok(
            self.dossier_recevable, self.jury1, self.salle_a, creneau(8, 10)
        )
        self.assertEqual(dossier.pk, self.dossier_recevable.pk)
        self.assertEqual(jury.pk, self.jury1.pk)

    def test_brouillon_sans_avis_refuse(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.verifier_dossier_recevable(self.dossier_brouillon.pk)
        self.assertIn("folder", ctx.exception.detail)
        self.assertIn("recevable", str(ctx.exception.detail["folder"]))

    def test_avis_favorable_encadreur_suffit(self):
        version = DocumentVersion.objects.create(
            folder=self.dossier_brouillon,
            version_number=1,
            file_path="/tmp/rapport-v1.pdf",
        )
        Review.objects.create(
            document_version=version,
            author_role="encadreur",
            decision="favorable",
        )
        dossier = conflicts.verifier_dossier_recevable(self.dossier_brouillon.pk)
        self.assertEqual(dossier.pk, self.dossier_brouillon.pk)

    def test_avis_defavorable_bloque(self):
        version = DocumentVersion.objects.create(
            folder=self.dossier_brouillon,
            version_number=1,
            file_path="/tmp/rapport-v1.pdf",
        )
        Review.objects.create(
            document_version=version,
            author_role="encadreur",
            decision="defavorable",
        )
        with self.assertRaises(ValidationError):
            conflicts.verifier_dossier_recevable(self.dossier_brouillon.pk)

    def test_seule_la_derniere_version_compte(self):
        v1 = DocumentVersion.objects.create(
            folder=self.dossier_brouillon,
            version_number=1,
            file_path="/tmp/rapport-v1.pdf",
        )
        v2 = DocumentVersion.objects.create(
            folder=self.dossier_brouillon,
            version_number=2,
            file_path="/tmp/rapport-v2.pdf",
        )
        # v1 favorable mais v2 défavorable => bloqué
        Review.objects.create(
            document_version=v1, author_role="encadreur", decision="favorable"
        )
        Review.objects.create(
            document_version=v2, author_role="encadreur", decision="defavorable"
        )
        with self.assertRaises(ValidationError):
            conflicts.verifier_dossier_recevable(self.dossier_brouillon.pk)
        # v1 défavorable, v2 favorable => autorisé
        Review.objects.all().delete()
        Review.objects.create(
            document_version=v1, author_role="encadreur", decision="defavorable"
        )
        Review.objects.create(
            document_version=v2, author_role="encadreur", decision="favorable"
        )
        dossier = conflicts.verifier_dossier_recevable(self.dossier_brouillon.pk)
        self.assertEqual(dossier.pk, self.dossier_brouillon.pk)

    def test_avis_tuteur_seul_ne_suffit_pas(self):
        version = DocumentVersion.objects.create(
            folder=self.dossier_brouillon,
            version_number=1,
            file_path="/tmp/rapport-v1.pdf",
        )
        Review.objects.create(
            document_version=version, author_role="tuteur", decision="favorable"
        )
        with self.assertRaises(ValidationError):
            conflicts.verifier_dossier_recevable(self.dossier_brouillon.pk)

    def test_dossier_inexistant_refuse(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.verifier_dossier_recevable(999999)
        self.assertIn("folder", ctx.exception.detail)


class SalleEtJuryTests(DonneesDeBase):
    """F04/F05 : existence et activation de la salle, jury renseigné."""

    def test_salle_inexistante_refusee(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.verifier_toutes_regles(
                self.dossier_recevable.pk, self.jury1.pk,
                "Salle Fantome", creneau(8, 10),
            )
        self.assertIn("room_name", ctx.exception.detail)

    def test_salle_inactive_refusee(self):
        with self.assertRaises(ValidationError) as ctx:
            self.regles_ok(
                self.dossier_recevable, self.jury1,
                self.salle_inactive, creneau(8, 10),
            )
        self.assertIn("room_name", ctx.exception.detail)
        self.assertIn("inactive", str(ctx.exception.detail["room_name"]))

    def test_jury_inexistant_refuse(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.verifier_toutes_regles(
                self.dossier_recevable.pk, 999999,
                self.salle_a.name, creneau(8, 10),
            )
        self.assertIn("jury", ctx.exception.detail)

    def test_jury_sans_membres_refuse(self):
        with self.assertRaises(ValidationError) as ctx:
            self.regles_ok(
                self.dossier_recevable, self.jury_vide,
                self.salle_a, creneau(8, 10),
            )
        self.assertIn("jury", ctx.exception.detail)


class ConflitSalleTests(DonneesDeBase):
    """EXG01 : une salle ne peut pas accueillir deux soutenances qui se chevauchent."""

    def test_chevauchement_partiel_detecte(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        with self.assertRaises(ValidationError) as ctx:
            self.regles_ok(
                self.dossier_recevable, self.jury3, self.salle_a, creneau(9, 11)
            )
        message = str(ctx.exception.detail["room_name"])
        self.assertIn("EXG01", message)

    def test_englobant_detecte(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        with self.assertRaises(ValidationError):
            self.regles_ok(
                self.dossier_recevable, self.jury3, self.salle_a, creneau(7, 11)
            )

    def test_englobant_inverse_detecte(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 12).lower, creneau(8, 12).upper,
        )
        with self.assertRaises(ValidationError):
            self.regles_ok(
                self.dossier_recevable, self.jury3, self.salle_a, creneau(9, 10)
            )

    def test_autre_salle_meme_horaire_autorise(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        self.regles_ok(
            self.dossier_recevable, self.jury3, self.salle_b, creneau(9, 11)
        )

    def test_bornes_fermees_ouverture_pas_de_conflit_adjacent(self):
        # Intervalle [debut, fin) : fin = début d'un autre créneau => OK
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        self.regles_ok(
            self.dossier_recevable, self.jury3, self.salle_a, creneau(10, 12)
        )


class ConflitJuryTests(DonneesDeBase):
    """EXG01 : un jury (et ses membres) ne peut pas siéger deux fois."""

    def test_meme_jury_autre_salle_detecte(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        with self.assertRaises(ValidationError) as ctx:
            self.regles_ok(
                self.dossier_recevable, self.jury1, self.salle_b, creneau(9, 11)
            )
        self.assertIn("jury", ctx.exception.detail)

    def test_membres_croises_detectes_entre_deux_jurys(self):
        # B. Diarra siège dans jury1 ET jury2 : deux soutenances simultanées
        # avec ces deux jurys doivent être refusées.
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        with self.assertRaises(ValidationError) as ctx:
            self.regles_ok(
                self.dossier_recevable, self.jury2, self.salle_b, creneau(9, 11)
            )
        message = str(ctx.exception.detail["jury"])
        self.assertIn("B. Diarra", message)

    def test_membres_distincts_pas_de_conflit(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        self.regles_ok(
            self.dossier_recevable, self.jury3, self.salle_b, creneau(9, 11)
        )

    def test_membres_croises_reussissent_si_creneaux_disjoints(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        self.regles_ok(
            self.dossier_recevable, self.jury2, self.salle_b, creneau(10, 12)
        )


class PlanifierSoutenanceTests(DonneesDeBase):
    """Orchestration : création et modification via le service."""

    def test_creation_retourne_defense_planifiee(self):
        defense = conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        self.assertIsNotNone(defense.pk)
        self.assertEqual(defense.status, "planifie")
        self.assertEqual(defense.room_name, self.salle_a.name)
        self.assertEqual(defense.slot_range.lower, creneau(8, 10).lower)

    def test_statut_personnalise_conserve(self):
        defense = conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
            status="valide",
        )
        self.assertEqual(defense.status, "valide")

    def test_modification_deplace_sans_auto_conflit(self):
        defense = conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        modifiee = conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(10, 12).lower, creneau(10, 12).upper,
            defense_id=defense.pk,
        )
        modifiee.refresh_from_db()
        self.assertEqual(modifiee.slot_range.lower, creneau(10, 12).lower)
        # l'ancien créneau est libéré : une nouvelle réservation 08-10 passe
        self.regles_ok(
            self.dossier_recevable, self.jury3, self.salle_a, creneau(8, 10)
        )

    def test_modification_conflit_avec_autre_soutenance(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        d2 = conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury3.pk,
            self.salle_a.name, creneau(10, 12).lower, creneau(10, 12).upper,
        )
        # d2 veut empiéter sur le créneau de d1 : refusé (d1 exclu du contrôle
        # uniquement quand c'est elle qui est modifiée).
        with self.assertRaises(ValidationError):
            conflicts.planifier_soutenance(
                self.dossier_recevable.pk, self.jury3.pk,
                self.salle_a.name, creneau(9, 11).lower, creneau(9, 11).upper,
                defense_id=d2.pk,
            )

    def test_creation_conflit_n_ecrit_rien(self):
        conflicts.planifier_soutenance(
            self.dossier_recevable.pk, self.jury1.pk,
            self.salle_a.name, creneau(8, 10).lower, creneau(8, 10).upper,
        )
        total_avant = Defense.objects.count()
        with self.assertRaises(ValidationError):
            conflicts.planifier_soutenance(
                self.dossier_recevable.pk, self.jury3.pk,
                self.salle_a.name, creneau(9, 11).lower, creneau(9, 11).upper,
            )
        self.assertEqual(Defense.objects.count(), total_avant)

    def test_creation_invalide_horaire_n_ecrit_rien(self):
        total_avant = Defense.objects.count()
        with self.assertRaises(ValidationError):
            conflicts.planifier_soutenance(
                self.dossier_recevable.pk, self.jury1.pk,
                self.salle_a.name, creneau(10, 8).lower, creneau(10, 8).upper,
            )
        self.assertEqual(Defense.objects.count(), total_avant)


class ContraintesSQLTests(DonneesDeBase):
    """
    Filet de sécurité PostgreSQL : les contraintes d'exclusion EXG01 doivent
    rejeter elles-mêmes les insertions chevauchantes (cas de course entre deux
    requêtes concurrentes qui passeraient le contrôle applicatif).
    """

    def _inserer(self, jury, salle, heure_debut, heure_fin):
        return Defense.objects.create(
            folder=self.dossier_recevable,
            jury=jury,
            room_name=salle.name,
            slot_range=creneau(heure_debut, heure_fin),
            status="planifie",
        )

    def test_double_reservation_salle_rejetee_par_postgresql(self):
        self._inserer(self.jury1, self.salle_a, 8, 10)
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                self._inserer(self.jury3, self.salle_a, 9, 11)

    def test_double_reservation_jury_rejetee_par_postgresql(self):
        self._inserer(self.jury1, self.salle_a, 8, 10)
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                self._inserer(self.jury1, self.salle_b, 9, 11)

    def test_insertions_disjointes_acceptees(self):
        d1 = self._inserer(self.jury1, self.salle_a, 8, 10)
        d2 = self._inserer(self.jury1, self.salle_a, 10, 12)  # bornes [) : OK
        self.assertEqual(
            Defense.objects.filter(
                room_name=self.salle_a.name, pk__in=[d1.pk, d2.pk]
            ).count(),
            2,
        )

    def test_aucune_insertion_application_pour_defense_refusee(self):
        # Le contrôle applicatif doit intercepter le conflit AVANT l'écriture :
        # aucune IntegrityError brute ne doit remonter à l'utilisateur.
        self._inserer(self.jury1, self.salle_a, 8, 10)
        total_avant = Defense.objects.count()
        with self.assertRaises(ValidationError):
            conflicts.planifier_soutenance(
                self.dossier_recevable.pk, self.jury3.pk,
                self.salle_a.name, creneau(9, 11).lower, creneau(9, 11).upper,
            )
        self.assertEqual(Defense.objects.count(), total_avant)
