"""
Tests de validation qui n'exigent PAS de base de données (SimpleTestCase) :

* normalisation/validation des créneaux (api.services.conflicts) ;
* validations de champs des serializers (Salle, JuryMember) ;
* traduction des IntegrityError PostgreSQL en erreurs lisibles (EXG01).
"""

from datetime import datetime, timedelta

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange
from django.test import SimpleTestCase
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from api.serializers import JuryMemberSerializer, SalleSerializer
from api.documents.validators import MAX_DOCUMENT_SIZE, validate_pdf_file
from api.services import conflicts

UTC = timezone.UTC


class ConstruireCreneauTests(SimpleTestCase):
    """Validation et normalisation des créneaux (NFR04)."""

    def test_creneau_valide_deux_datetimes_naifs_interpretes_utc(self):
        slot = conflicts.construire_creneau(
            datetime(2026, 7, 10, 8, 0), datetime(2026, 7, 10, 10, 0)
        )
        self.assertIsInstance(slot, DateTimeTZRange)
        self.assertEqual(slot.lower, datetime(2026, 7, 10, 8, 0, tzinfo=UTC))
        self.assertEqual(slot.upper, datetime(2026, 7, 10, 10, 0, tzinfo=UTC))
        self.assertTrue(slot.lower_inc)
        self.assertFalse(slot.upper_inc)


    def test_chaine_iso_avec_offset_convertie_en_utc(self):
        # 10:00 à Bamako (UTC+2) => 08:00 UTC
        slot = conflicts.construire_creneau(
            "2026-07-10T10:00:00+02:00", "2026-07-10T12:00:00+02:00"
        )
        self.assertEqual(slot.lower, datetime(2026, 7, 10, 8, 0, tzinfo=UTC))
        self.assertEqual(slot.upper, datetime(2026, 7, 10, 10, 0, tzinfo=UTC))

    def test_chaine_iso_avec_suffixe_z(self):
        slot = conflicts.construire_creneau(
            "2026-07-10T08:00:00Z", "2026-07-10T09:30:00Z"
        )
        self.assertEqual(slot.lower, datetime(2026, 7, 10, 8, 0, tzinfo=UTC))

    def test_fin_egal_debut_refuse(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.construire_creneau(
                "2026-07-10T08:00:00Z", "2026-07-10T08:00:00Z"
            )
        self.assertIn("slot_end", ctx.exception.detail)

    def test_fin_avant_debut_refuse(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.construire_creneau(
                "2026-07-10T10:00:00Z", "2026-07-10T08:00:00Z"
            )
        self.assertIn("slot_end", ctx.exception.detail)

    def test_duree_excessive_refusee(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.construire_creneau(
                datetime(2026, 7, 10, 8, 0, tzinfo=UTC),
                datetime(2026, 7, 10, 17, 0, 1, tzinfo=UTC),
            )
        self.assertIn("slot_end", ctx.exception.detail)

    def test_format_invalide_refuse(self):
        with self.assertRaises(ValidationError) as ctx:
            conflicts.construire_creneau("pas-une-date", "2026-07-10T10:00:00Z")
        self.assertIn("slot_start", ctx.exception.detail)

    def test_valeur_manquante_refusee(self):
        with self.assertRaises(ValidationError):
            conflicts.construire_creneau(None, None)


class ValidationPdfTests(SimpleTestCase):
    """Garantit le type, la signature et la taille maximale des dépôts."""

    def test_pdf_valide_accepte(self):
        fichier = SimpleUploadedFile(
            "rapport.pdf",
            b"%PDF-1.4 contenu",
            content_type="application/pdf",
        )

        self.assertIs(validate_pdf_file(fichier), fichier)

    def test_extension_non_pdf_refusee(self):
        fichier = SimpleUploadedFile("rapport.txt", b"%PDF-1.4 contenu")

        with self.assertRaisesMessage(
            DjangoValidationError, "Seuls les fichiers PDF"
        ):
            validate_pdf_file(fichier)

    def test_fausse_signature_pdf_refusee(self):
        fichier = SimpleUploadedFile("rapport.pdf", b"texte sans signature")

        with self.assertRaisesMessage(DjangoValidationError, "pas un véritable"):
            validate_pdf_file(fichier)

    def test_fichier_superieur_a_dix_mo_refuse(self):
        fichier = SimpleUploadedFile(
            "rapport.pdf",
            b"%PDF-" + b"x" * MAX_DOCUMENT_SIZE,
        )

        with self.assertRaisesMessage(
            DjangoValidationError, "ne doit pas dépasser 10 Mo"
        ):
            validate_pdf_file(fichier)


class ChampsSerializersTests(SimpleTestCase):
    """Validations de champs ne touchant pas la base."""

    def setUp(self):
        self.salle = SalleSerializer()
        self.membre = JuryMemberSerializer()

    def test_nom_salle_est_nettoye(self):
        self.assertEqual(self.salle.validate_name("  Salle 101  "), "Salle 101")

    def test_capacite_valide(self):
        self.assertEqual(self.salle.validate_capacity(30), 30)
        self.assertEqual(self.salle.validate_capacity(1), 1)

    def test_capacite_nulle_ou_negative_refusee(self):
        for valeur in (0, -5, None):
            with self.assertRaises(ValidationError):
                self.salle.validate_capacity(valeur)

    def test_nom_membre_est_nettoye(self):
        self.assertEqual(
            self.membre.validate_member_name("  Dr. Traoré  "), "Dr. Traoré"
        )

    def test_roles_valides(self):
        for role in ("president", "rapporteur", "examinateur"):
            self.assertEqual(self.membre.validate_role_in_jury(role), role)

    def test_role_accepte_majuscules_et_espaces(self):
        self.assertEqual(
            self.membre.validate_role_in_jury("  PRESIDENT "), "president"
        )

    def test_role_invalide_refuse(self):
        with self.assertRaises(ValidationError):
            self.membre.validate_role_in_jury("chef")


class TraduireIntegrityErrorTests(SimpleTestCase):
    """Traduction des contraintes d'exclusion PostgreSQL en messages EXG01."""

    def test_contrainte_salle_reconnue(self):
        erreur = Exception(
            'new row for relation "defense" violates exclusion constraint '
            '"prevent_room_double_booking"'
        )
        message = str(conflicts.traduire_integrity_error(erreur).detail["detail"])
        self.assertIn("salle", message)
        self.assertIn("EXG01", message)

    def test_contrainte_jury_reconnue(self):
        erreur = Exception(
            'new row for relation "defense" violates exclusion constraint '
            '"prevent_jury_double_booking"'
        )
        message = str(conflicts.traduire_integrity_error(erreur).detail["detail"])
        self.assertIn("jury", message)

    def test_erreur_inconnue_n_est_pas_presentee_comme_un_conflit(self):
        erreur_traduitee = conflicts.traduire_integrity_error(
            Exception("erreur inconnue")
        )
        self.assertIsNone(erreur_traduitee)
