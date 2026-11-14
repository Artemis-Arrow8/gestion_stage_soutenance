"""Vérifie que le jeu de démonstration est sûr et réexécutable."""

import os
import tempfile
from io import StringIO
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.storage import default_storage
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings

from api.models import (
    Campaign,
    Defense,
    DocumentVersion,
    FolderSupervisor,
    InternshipFolder,
    JuryMemberAccount,
    StudentAccount,
)

User = get_user_model()


class SeedSgsusTests(TestCase):
    """Contrôle le jeu de données, ses liens métier et son idempotence."""

    @override_settings(DEBUG=True)
    def test_seed_cree_des_donnees_coherentes_et_reexecutables(self):
        mot_de_passe = "Demo-Sgsus!2026-Confidentiel"
        with tempfile.TemporaryDirectory() as media_root:
            with override_settings(MEDIA_ROOT=media_root):
                with patch.dict(
                    os.environ,
                    {"SGSUS_DEMO_PASSWORD": mot_de_passe},
                ):
                    call_command("seed_sgsus", stdout=StringIO())
                    call_command("seed_sgsus", stdout=StringIO())

                self.assertEqual(Campaign.objects.filter(is_active=True).count(), 1)
                self.assertEqual(InternshipFolder.objects.count(), 3)
                self.assertEqual(DocumentVersion.objects.count(), 3)
                self.assertEqual(Defense.objects.count(), 2)
                self.assertEqual(FolderSupervisor.objects.count(), 2)
                self.assertEqual(StudentAccount.objects.count(), 3)
                self.assertEqual(JuryMemberAccount.objects.count(), 1)

                for nom in (
                    "demo.admin",
                    "demo.responsable",
                    "demo.encadreur",
                    "demo.etudiant",
                    "demo.etudiant2",
                    "demo.jury",
                ):
                    self.assertTrue(
                        User.objects.get(username=nom).check_password(mot_de_passe)
                    )

                premier_document = DocumentVersion.objects.order_by("pk").first()
                with default_storage.open(premier_document.file_path, "rb") as pdf:
                    self.assertTrue(pdf.read(5).startswith(b"%PDF-"))

    @override_settings(DEBUG=False)
    def test_seed_refuse_le_mode_production_sans_confirmation(self):
        with self.assertRaisesMessage(CommandError, "Le seed est refusé"):
            call_command("seed_sgsus")
