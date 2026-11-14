"""Crée un jeu de données cohérent pour les démonstrations SGSUS."""

import os
from datetime import datetime, timezone

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand, CommandError
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.backends.postgresql.psycopg_any import DateTimeTZRange

from api.models import (
    Campaign,
    Defense,
    DocumentVersion,
    FolderSupervisor,
    InternshipFolder,
    Jury,
    JuryMember,
    JuryMemberAccount,
    Review,
    Room,
    Student,
    StudentAccount,
)
from api.roles import ROLE_GROUPS


User = get_user_model()


class Command(BaseCommand):
    """Peuple une base déjà migrée sans supprimer ni dupliquer les données."""

    help = (
        "Crée des comptes, dossiers, documents et soutenances de démonstration "
        "SGSUS de façon réexécutable."
    )

    def add_arguments(self, parser):
        """Ajoute un garde-fou explicite contre le seed accidentel en production."""
        parser.add_argument(
            "--allow-production",
            action="store_true",
            help=(
                "Autorise explicitement le seed en mode production ; "
                "à réserver à une instance de démonstration isolée."
            ),
        )

    def handle(self, *args, **options):
        """Valide les secrets puis crée l'ensemble des données atomiquement."""
        if not settings.DEBUG and not options["allow_production"]:
            raise CommandError(
                "Le seed est refusé avec DEBUG=False. Pour une instance de "
                "démonstration isolée seulement, ajoutez --allow-production."
            )

        password = os.getenv("SGSUS_DEMO_PASSWORD", "")
        if len(password) < 12:
            raise CommandError(
                "Définissez SGSUS_DEMO_PASSWORD avec une phrase secrète "
                "d'au moins 12 caractères avant de lancer cette commande."
            )

        with transaction.atomic():
            campagne = self._creer_campagne()
            comptes = self._creer_comptes(password)
            dossiers = self._creer_dossiers(campagne, comptes)
            jurys = self._creer_jurys(comptes)
            self._affecter_encadreur(comptes["supervisor"], dossiers)
            documents = self._creer_documents(dossiers)
            self._creer_avis(comptes["supervisor"], documents)
            soutenances = self._creer_planning(dossiers, jurys)

        self.stdout.write(self.style.SUCCESS(
            "Démonstration SGSUS prête : "
            f"{len(comptes)} comptes, {len(dossiers)} dossiers, "
            f"{len(documents)} documents et {len(soutenances)} soutenances."
        ))
        self.stdout.write(
            "Comptes : demo.admin, demo.responsable, demo.encadreur, "
            "demo.etudiant, demo.etudiant2, demo.etudiant3, demo.jury."
        )
        self.stdout.write(
            "Le mot de passe commun est celui fourni dans "
            "SGSUS_DEMO_PASSWORD ; il n'est pas affiché."
        )

    def _creer_campagne(self):
        """Crée la campagne de démonstration active si elle n'existe pas."""
        campagne, _ = Campaign.objects.get_or_create(
            academic_year="2026-2027",
            defaults={"is_active": True},
        )
        if not campagne.is_active:
            campagne.is_active = True
            campagne.save(update_fields=["is_active"])
        return campagne

    def _creer_compte(self, username, email, password, role):
        """Crée ou actualise un compte de démo et son groupe de rôle unique."""
        user, _ = User.objects.get_or_create(
            username=username,
            defaults={"email": email},
        )
        user.email = email
        user.is_active = True
        user.is_staff = role == "admin"
        user.is_superuser = role == "admin"
        user.set_password(password)
        user.save()

        groupes_sgsus = Group.objects.filter(name__in=ROLE_GROUPS)
        user.groups.remove(*groupes_sgsus)
        groupe, _ = Group.objects.get_or_create(name=role)
        user.groups.add(groupe)
        return user

    def _creer_comptes(self, password):
        """Prépare les profils requis et lie chaque rôle à son identité métier."""
        comptes = {}

        comptes["admin"] = self._creer_compte(
            "demo.admin",
            "demo.admin@example.test",
            password,
            "admin",
        )
        comptes["responsible"] = self._creer_compte(
            "demo.responsable",
            "demo.responsable@example.test",
            password,
            "responsible",
        )
        comptes["supervisor"] = self._creer_compte(
            "demo.encadreur",
            "demo.encadreur@example.test",
            password,
            "supervisor",
        )

        for numero, nom, adresse, identifiant in (
            (1, "Aminata Traoré", "aminata@example.test", "DEMO-ETU-001"),
            (2, "Moussa Konaté", "moussa@example.test", "DEMO-ETU-002"),
            (3, "Fatoumata Diarra", "fatoumata@example.test", "DEMO-ETU-003"),
        ):
            etudiant, _ = Student.objects.get_or_create(
                student_number=identifiant,
                defaults={"full_name": nom, "email": adresse},
            )
            if etudiant.full_name != nom or etudiant.email != adresse:
                etudiant.full_name = nom
                etudiant.email = adresse
                etudiant.save(update_fields=["full_name", "email"])

            utilisateur = self._creer_compte(
                "demo.etudiant" if numero == 1 else f"demo.etudiant{numero}",
                adresse,
                password,
                "student",
            )
            StudentAccount.objects.update_or_create(
                user=utilisateur,
                defaults={"student": etudiant},
            )
            comptes[f"student{numero}"] = utilisateur

        membre = self._obtenir_membre_jury(
            "Jury A — Président", "president", "Jury A"
        )
        compte_jury = self._creer_compte(
            "demo.jury",
            "demo.jury@example.test",
            password,
            "jury",
        )
        JuryMemberAccount.objects.update_or_create(
            user=compte_jury,
            defaults={"jury_member": membre},
        )
        comptes["jury"] = compte_jury

        return comptes

    def _obtenir_membre_jury(self, nom, role, nom_jury):
        """Crée le jury et un membre stable pour rendre le seed réexécutable."""
        jury, _ = Jury.objects.get_or_create(
            name=nom_jury,
            defaults={"is_complete": True},
        )
        if not jury.is_complete:
            jury.is_complete = True
            jury.save(update_fields=["is_complete"])
        membre, _ = JuryMember.objects.get_or_create(
            jury=jury,
            member_name=nom,
            defaults={"role_in_jury": role},
        )
        if membre.role_in_jury != role:
            membre.role_in_jury = role
            membre.save(update_fields=["role_in_jury"])
        return membre

    def _creer_jurys(self, comptes):
        """Crée deux jurys complets avec des membres sans conflit croisé."""
        membres = (
            ("Jury A — Président", "president", "Jury A"),
            ("Jury A — Rapporteur", "rapporteur", "Jury A"),
            ("Jury A — Examinateur", "examinateur", "Jury A"),
            ("Jury B — Président", "president", "Jury B"),
            ("Jury B — Rapporteur", "rapporteur", "Jury B"),
            ("Jury B — Examinateur", "examinateur", "Jury B"),
        )
        jurys = {}
        for nom, role, nom_jury in membres:
            membre = self._obtenir_membre_jury(nom, role, nom_jury)
            jurys[nom_jury] = membre.jury

        # Le compte jury de démonstration représente le président du Jury A.
        JuryMemberAccount.objects.update_or_create(
            user=comptes["jury"],
            defaults={
                "jury_member": JuryMember.objects.get(
                    jury=jurys["Jury A"],
                    role_in_jury="president",
                    member_name="Jury A — Président",
                )
            },
        )
        return [jurys["Jury A"], jurys["Jury B"]]

    def _creer_dossiers(self, campagne, comptes):
        """Crée trois dossiers réalistes dont deux sont recevables."""
        eleves = (
            ("student1", "demo.etudiant", "Banque de l'Union", "Automatisation du suivi des stages", "recevable"),
            ("student2", "demo.etudiant2", "Hôpital du District", "Portail de gestion des rendez-vous", "recevable"),
            ("student3", "demo.etudiant3", "Université de Bamako", "Tableau de bord des inscriptions", "brouillon"),
        )
        dossiers = []
        for cle, username, entreprise, sujet, statut in eleves:
            compte = comptes[cle]
            etudiant = compte.student_account.student
            dossier, _ = InternshipFolder.objects.get_or_create(
                student=etudiant,
                campaign=campagne,
                defaults={
                    "company_name": entreprise,
                    "subject": sujet,
                    "status": statut,
                },
            )
            champs_modifies = []
            for champ, valeur in (
                ("company_name", entreprise),
                ("subject", sujet),
                ("status", statut),
            ):
                if getattr(dossier, champ) != valeur:
                    setattr(dossier, champ, valeur)
                    champs_modifies.append(champ)
            if champs_modifies:
                dossier.save(update_fields=champs_modifies)
            dossiers.append(dossier)
        return dossiers

    def _affecter_encadreur(self, encadreur, dossiers):
        """Limite l'accès de l'encadreur aux deux dossiers recevables."""
        for dossier in dossiers[:2]:
            FolderSupervisor.objects.get_or_create(
                user=encadreur,
                folder=dossier,
            )

    def _creer_documents(self, dossiers):
        """Ajoute une version PDF de démonstration à chacun des dossiers."""
        contenu = self._contenu_pdf()
        documents = []
        for dossier in dossiers:
            chemin = f"documents/demo/folder_{dossier.pk}/rapport.pdf"
            if not default_storage.exists(chemin):
                default_storage.save(chemin, ContentFile(contenu))
            document, _ = DocumentVersion.objects.get_or_create(
                folder=dossier,
                version_number=1,
                defaults={"file_path": chemin},
            )
            documents.append(document)
        return documents

    def _creer_avis(self, encadreur, documents):
        """Ajoute un avis favorable traçable pour chaque dossier recevable."""
        for document in documents[:2]:
            Review.objects.get_or_create(
                document_version=document,
                author=encadreur,
                defaults={
                    "author_role": "encadreur",
                    "decision": "favorable",
                    "comments": (
                        "Dossier de démonstration : le rapport est recevable."
                    ),
                },
            )

    def _creer_planning(self, dossiers, jurys):
        """Planifie deux soutenances successives sans conflit de ressources."""
        salles = (
            ("Salle 101", 30),
            ("Salle 102", 25),
        )
        for nom, capacite in salles:
            Room.objects.update_or_create(
                name=nom,
                defaults={"capacity": capacite, "is_active": True},
            )

        debut_jour = datetime(2026, 12, 1, tzinfo=timezone.utc)
        reservations = (
            (dossiers[0], jurys[0], salles[0][0], 9, 10),
            (dossiers[1], jurys[1], salles[1][0], 10, 11),
        )
        soutenances = []
        for dossier, jury, salle, heure_debut, heure_fin in reservations:
            debut = debut_jour.replace(hour=heure_debut)
            fin = debut_jour.replace(hour=heure_fin)
            soutenance, _ = Defense.objects.update_or_create(
                folder=dossier,
                defaults={
                    "jury": jury,
                    "room_name": salle,
                    "slot_range": DateTimeTZRange(debut, fin, bounds="[)"),
                    "status": "planifie",
                },
            )
            soutenances.append(soutenance)
        return soutenances

    @staticmethod
    def _contenu_pdf():
        """Construit un PDF minimal valide afin que le seed soit autonome."""
        flux = (
            b"BT /F1 14 Tf 30 150 Td "
            b"(Rapport de stage SGSUS - Demo) Tj ET"
        )
        objets = [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] "
            b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            b"<< /Length " + str(len(flux)).encode("ascii")
            + b" >>\nstream\n" + flux + b"\nendstream",
        ]
        contenu = bytearray(b"%PDF-1.4\n")
        positions = [0]
        for identifiant, objet in enumerate(objets, start=1):
            positions.append(len(contenu))
            contenu.extend(f"{identifiant} 0 obj\n".encode("ascii"))
            contenu.extend(objet + b"\nendobj\n")
        debut_xref = len(contenu)
        contenu.extend(f"xref\n0 {len(positions)}\n".encode("ascii"))
        contenu.extend(b"0000000000 65535 f \n")
        for position in positions[1:]:
            contenu.extend(f"{position:010d} 00000 n \n".encode("ascii"))
        contenu.extend(
            (
                f"trailer\n<< /Size {len(positions)} /Root 1 0 R >>\n"
                f"startxref\n{debut_xref}\n%%EOF\n"
            ).encode("ascii")
        )
        return bytes(contenu)
