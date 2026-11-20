"""
Jeu de démonstration du chapitre 5 (`seed_demo`) : volumes demandés,
dossiers menés par les services métier, pièce remplacée, conflits refusés
sans écriture et réexécution sans doublon.
"""

import os
import tempfile
from io import StringIO
from unittest.mock import patch

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings

from api.models import (
    Campaign,
    Defense,
    DocumentVersion,
    FolderSupervisor,
    HistoriqueDossier,
    InternshipFolder,
    JuryMember,
    JuryMemberAccount,
    Review,
    Room,
    Student,
)

MOT_DE_PASSE = "Demo-Chapitre5!2026"


class SeedDemoTests(TestCase):
    """Contrôle le jeu de données demandé par le chapitre 5 du dossier."""

    def _lancer(self):
        """Exécute la commande et renvoie sa sortie texte."""
        sortie = StringIO()
        with patch.dict(os.environ, {"SGSUS_DEMO_PASSWORD": MOT_DE_PASSE}):
            call_command("seed_demo", stdout=sortie)
        return sortie.getvalue()

    @override_settings(DEBUG=True)
    def test_jeu_du_chapitre_5_complet_et_reexecutable(self):
        with tempfile.TemporaryDirectory() as media_root, override_settings(MEDIA_ROOT=media_root):
            sortie = self._lancer()

            # Volumes exigés par le chapitre 5.
            self.assertEqual(Campaign.objects.filter(academic_year__endswith="(démo ALM)").count(), 2)
            self.assertEqual(Student.objects.filter(student_number__startswith="DEMO5-").count(), 12)
            self.assertEqual(
                FolderSupervisor.objects.filter(user__username__startswith="demo5.encadreur")
                .values("user").distinct().count(),
                4,
            )
            self.assertEqual(
                JuryMember.objects.filter(jury__name__endswith="(démo)")
                .values("member_name").distinct().count(),
                6,
            )
            self.assertEqual(JuryMemberAccount.objects.filter(user__username__startswith="demo5.jure").count(), 6)
            self.assertEqual(Room.objects.filter(name__endswith="(démo)").count(), 3)

            demo = InternshipFolder.objects.filter(student__student_number__startswith="DEMO5-")
            # Deux dossiers incomplets : brouillon, aucun rapport déposé.
            incomplets = demo.filter(status="brouillon", document_versions__isnull=True)
            self.assertEqual(incomplets.count(), 2)

            # Une pièce remplacée : V1 et V2, l'avis (corrections) reste sur V1.
            remplace = demo.get(student__student_number="DEMO5-007")
            self.assertEqual(remplace.status, "soumis")
            versions = DocumentVersion.objects.filter(folder=remplace).order_by("version_number")
            self.assertEqual([v.version_number for v in versions], [1, 2])
            self.assertTrue(Review.objects.filter(document_version=versions[0], decision="defavorable").exists())
            self.assertFalse(Review.objects.filter(document_version=versions[1]).exists())

            # Les dossiers ont avancé par les services : historique réel.
            self.assertTrue(HistoriqueDossier.objects.filter(dossier=remplace, evenement="nouvelle_version").exists())
            self.assertEqual(demo.filter(status="recevable").count(), 6)

            # Quatre soutenances valides ; les deux conflits n'ont rien écrit.
            self.assertEqual(Defense.objects.filter(folder__in=demo).count(), 4)
            self.assertIn("Conflit de salle", sortie)
            self.assertIn("Conflit de personne", sortie)
            self.assertEqual(sortie.count("refusé (EXG01)"), 2)

            # Réexécution : rien n'est dupliqué.
            self.assertIn("déjà présent", self._lancer())
            self.assertEqual(Student.objects.filter(student_number__startswith="DEMO5-").count(), 12)
            self.assertEqual(Defense.objects.filter(folder__in=demo).count(), 4)

    @override_settings(DEBUG=False)
    def test_refuse_en_production_sans_option_explicite(self):
        with self.assertRaises(CommandError):
            self._lancer()
        self.assertFalse(Campaign.objects.filter(academic_year__endswith="(démo ALM)").exists())
