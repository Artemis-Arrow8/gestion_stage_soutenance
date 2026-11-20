"""
Jeu de démonstration du chapitre 5 du dossier ALM (commande `seed_demo`).

Le dossier demande : « deux campagnes, douze étudiants fictifs, quatre
encadreurs, six jurés, trois salles, deux dossiers incomplets, une pièce
remplacée et plusieurs soutenances avec conflits de salle ou de personne ».

Particularités de cette commande :

* toutes les données sont FICTIVES (noms inventés, adresses en
  `example.test`) ; aucune donnée réelle n'est copiée ;
* les dossiers avancent par les VRAIS services métier (dépôt PDF,
  soumission, avis de l'encadreur, autorisation du responsable) : leur
  historique est donc identique à celui d'un usage réel ;
* les soutenances sont créées par le service de planification, avec tous
  ses contrôles (EXG01, F03, STA09) ;
* les « soutenances avec conflits » ne peuvent PAS exister en base (c'est
  justement la règle centrale EXG01) : la commande TENTE de les créer et
  affiche le refus obtenu, sans aucune écriture ;
* elle est reproductible : sur une base vide, elle produit toujours le même
  jeu ; relancée, elle constate que le jeu est déjà présent et ne crée rien.

Usage (base locale ou instance de démonstration isolée) :

    SGSUS_DEMO_PASSWORD="une phrase secrète de 12 caractères ou plus"
    python manage.py seed_demo

Avec DEBUG=False, la commande refuse de s'exécuter sauf `--allow-production`
(à réserver à une instance de démonstration isolée).
"""

import os
from datetime import datetime, timezone

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from api.documents.services import upload_document
from api.exceptions import ConflitMetier
from api.management.commands.seed_sgsus import Command as SeedSgsus
from api.models import (
    Campaign,
    FolderSupervisor,
    InternshipFolder,
    Jury,
    JuryMember,
    JuryMemberAccount,
    Room,
    Student,
    StudentAccount,
)
from api.roles import ROLE_GROUPS
from api.services import dossiers
from api.services.conflicts import planifier_soutenance

User = get_user_model()

# Libellés des deux campagnes (l'ancienne est close, la seconde est active).
CAMPAGNE_ANCIENNE = "2025-2026 (démo ALM)"
CAMPAGNE_ACTIVE = "2026-2027 (démo ALM)"

# Douze étudiants fictifs : (numéro, nom, campagne, scénario du dossier).
# Scénarios : « recevable » (soutenance autorisée), « valide » (accepté par
# l'encadreur), « soumis », « a_corriger », « piece_remplacee » (V1 refusée
# puis V2 déposée) et « incomplet » (aucun rapport déposé).
ETUDIANTS = (
    (1, "Awa Coulibaly", "ancienne", "recevable"),
    (2, "Bakary Sissoko", "ancienne", "recevable"),
    (3, "Rokia Kanté", "active", "recevable"),
    (4, "Oumar Dembélé", "active", "recevable"),
    (5, "Salimata Touré", "active", "recevable"),
    (6, "Issa Sangaré", "active", "recevable"),
    (7, "Hawa Ballo", "active", "piece_remplacee"),
    (8, "Modibo Keïta", "active", "a_corriger"),
    (9, "Fanta Camara", "active", "soumis"),
    (10, "Seydou Diallo", "active", "valide"),
    (11, "Aïssata Maïga", "active", "incomplet"),
    (12, "Drissa Togola", "active", "incomplet"),
)

# Quatre encadreurs fictifs.
ENCADREURS = (
    "Dr Aminata Cissé",
    "Dr Boubacar Traoré",
    "M. Karim Doumbia",
    "Mme Nènè Samaké",
)

# Six jurés (personnes distinctes) répartis en trois jurys complets.
# « Pr Ibrahim Konaté » siège dans les jurys Alpha ET Gamma : c'est lui qui
# provoque le conflit de PERSONNE tenté plus bas.
JURES = (
    "Pr Ibrahim Konaté",
    "Dr Mariétou Diakité",
    "M. Lassine Coulibaly",
    "Pr Adama Bagayoko",
    "Dr Kadia Sow",
    "M. Yaya Fofana",
)
JURYS = {
    "Jury Alpha (démo)": (
        ("Pr Ibrahim Konaté", "president"),
        ("Dr Mariétou Diakité", "rapporteur"),
        ("M. Lassine Coulibaly", "examinateur"),
    ),
    "Jury Bêta (démo)": (
        ("Pr Adama Bagayoko", "president"),
        ("Dr Kadia Sow", "rapporteur"),
        ("M. Yaya Fofana", "examinateur"),
    ),
    "Jury Gamma (démo)": (
        ("Pr Ibrahim Konaté", "president"),
        ("Dr Kadia Sow", "rapporteur"),
        ("M. Yaya Fofana", "examinateur"),
    ),
}

# Trois salles fictives.
SALLES = (("Salle D1 (démo)", 30), ("Salle D2 (démo)", 24), ("Salle D3 (démo)", 18))

# Jour des soutenances de démonstration (heures en UTC ; le fuseau métier
# par défaut, Africa/Bamako, est aussi UTC+0).
JOUR = datetime(2026, 12, 14, tzinfo=timezone.utc)


def _heure(h, m=0):
    """Instant UTC du jour de démonstration à `h` h `m`."""
    return JOUR.replace(hour=h, minute=m)


class Command(BaseCommand):
    """Crée le jeu de démonstration du chapitre 5 (données fictives)."""

    help = (
        "Crée le jeu de démonstration du chapitre 5 : 2 campagnes, 12 "
        "étudiants, 4 encadreurs, 6 jurés, 3 salles, 2 dossiers incomplets, "
        "une pièce remplacée et des tentatives de conflit refusées."
    )

    def add_arguments(self, parser):
        """Garde-fou explicite contre une exécution accidentelle en production."""
        parser.add_argument(
            "--allow-production",
            action="store_true",
            help="Autorise l'exécution avec DEBUG=False (instance de démonstration isolée).",
        )

    # ------------------------------------------------------------------
    # Point d'entrée
    # ------------------------------------------------------------------

    def handle(self, *args, **options):
        """Vérifie les garde-fous, puis crée tout le jeu en une transaction."""
        if not settings.DEBUG and not options["allow_production"]:
            raise CommandError(
                "seed_demo est refusé avec DEBUG=False. Pour une instance de "
                "démonstration isolée seulement, ajoutez --allow-production."
            )
        mot_de_passe = os.getenv("SGSUS_DEMO_PASSWORD", "")
        if len(mot_de_passe) < 12:
            raise CommandError(
                "Définissez SGSUS_DEMO_PASSWORD (12 caractères au moins) avant "
                "de lancer cette commande ; il n'est jamais affiché."
            )
        # Reproductible : un jeu déjà présent n'est ni modifié ni dupliqué.
        if Campaign.objects.filter(academic_year=CAMPAGNE_ACTIVE).exists():
            self.stdout.write(self.style.WARNING(
                "Le jeu de démonstration du chapitre 5 est déjà présent : "
                "rien n'a été créé."
            ))
            return

        with transaction.atomic():
            campagnes = self._creer_campagnes()
            responsable = self._creer_compte("demo5.responsable", "responsible", mot_de_passe)
            encadreurs = [
                self._creer_compte(f"demo5.encadreur{i}", "supervisor", mot_de_passe,
                                   nom_complet=nom)
                for i, nom in enumerate(ENCADREURS, start=1)
            ]
            dossiers_crees = self._creer_dossiers(campagnes, encadreurs, responsable,
                                                  mot_de_passe)
            jurys = self._creer_jurys(mot_de_passe)
            self._creer_salles()
            soutenances, refus = self._planifier(dossiers_crees, jurys)

        self._resume(dossiers_crees, soutenances, refus)

    # ------------------------------------------------------------------
    # Comptes et référentiels
    # ------------------------------------------------------------------

    def _creer_campagnes(self):
        """Une campagne close (année passée) et une campagne active."""
        ancienne = Campaign.objects.create(academic_year=CAMPAGNE_ANCIENNE, is_active=False)
        active = Campaign.objects.create(academic_year=CAMPAGNE_ACTIVE, is_active=True)
        return {"ancienne": ancienne, "active": active}

    def _creer_compte(self, identifiant, role, mot_de_passe, nom_complet=""):
        """Compte de connexion fictif rattaché à un seul groupe de rôle."""
        prenom, _, nom = nom_complet.partition(" ")
        compte = User.objects.create_user(
            username=identifiant,
            email=f"{identifiant}@example.test",
            password=mot_de_passe,
            first_name=prenom,
            last_name=nom,
        )
        groupe, _ = Group.objects.get_or_create(name=role)
        compte.groups.remove(*Group.objects.filter(name__in=ROLE_GROUPS))
        compte.groups.add(groupe)
        return compte

    def _creer_salles(self):
        """Trois salles actives."""
        for nom, capacite in SALLES:
            Room.objects.update_or_create(
                name=nom, defaults={"capacity": capacite, "is_active": True},
            )

    def _creer_jurys(self, mot_de_passe):
        """
        Trois jurys complets (président, rapporteur, examinateur) formés de
        six personnes. Chaque juré reçoit un compte relié à sa PREMIÈRE
        place de jury (un compte ne peut être lié qu'à une place).
        """
        jurys = {}
        places = {}
        for nom_jury, membres in JURYS.items():
            jury = Jury.objects.create(name=nom_jury, is_complete=False)
            for nom, fonction in membres:
                membre = JuryMember.objects.create(
                    jury=jury, member_name=nom, role_in_jury=fonction,
                )
                places.setdefault(nom, membre)
            # La composition respecte la règle F04 : le jury peut être complet.
            jury.is_complete = True
            jury.save(update_fields=["is_complete"])
            jurys[nom_jury] = jury
        for numero, nom in enumerate(JURES, start=1):
            compte = self._creer_compte(f"demo5.jure{numero}", "jury", mot_de_passe,
                                        nom_complet=nom)
            JuryMemberAccount.objects.create(user=compte, jury_member=places[nom])
        return jurys

    # ------------------------------------------------------------------
    # Dossiers (par les services métier)
    # ------------------------------------------------------------------

    @staticmethod
    def _pdf(nom):
        """Rapport PDF minimal valide (contenu fictif)."""
        return SimpleUploadedFile(nom, SeedSgsus._contenu_pdf(), content_type="application/pdf")

    def _creer_dossiers(self, campagnes, encadreurs, responsable, mot_de_passe):
        """
        Douze étudiants et leurs dossiers, chacun mené jusqu'à l'état de son
        scénario par les services métier (historique réel).
        """
        resultat = {}
        for numero, nom, campagne, scenario in ETUDIANTS:
            etudiant = Student.objects.create(
                student_number=f"DEMO5-{numero:03d}",
                full_name=nom,
                email=f"demo5.etu{numero:02d}@example.test",
            )
            compte = self._creer_compte(f"demo5.etu{numero:02d}", "student", mot_de_passe,
                                        nom_complet=nom)
            StudentAccount.objects.create(user=compte, student=etudiant)
            dossier = InternshipFolder.objects.create(
                student=etudiant,
                campaign=campagnes[campagne],
                company_name=f"Entreprise fictive n° {numero}",
                subject=f"Sujet de stage fictif n° {numero}",
                status=dossiers.BROUILLON,
            )
            # Répartition des dossiers : trois par encadreur.
            encadreur = encadreurs[(numero - 1) % len(encadreurs)]
            FolderSupervisor.objects.create(user=encadreur, folder=dossier)
            self._mener(dossier, scenario, compte, encadreur, responsable)
            dossier.refresh_from_db()
            resultat[numero] = dossier
        return resultat

    def _mener(self, dossier, scenario, etudiant, encadreur, responsable):
        """Fait avancer `dossier` jusqu'au `scenario` voulu."""
        if scenario == "incomplet":
            # Dossier incomplet : entreprise et sujet saisis, aucun rapport.
            return
        v1 = upload_document(dossier.pk, self._pdf("rapport_v1.pdf"), etudiant)
        dossiers.soumettre(dossier.pk, etudiant)
        if scenario == "soumis":
            return
        if scenario in ("a_corriger", "piece_remplacee"):
            dossiers.enregistrer_avis_pedagogique(
                v1.pk, encadreur, dossiers.AVIS_DEFAVORABLE,
                "Compléter la bibliographie et revoir le chapitre 2.",
            )
            if scenario == "piece_remplacee":
                # V2 déposée et renvoyée : l'avis reste attaché à V1 (STA05).
                upload_document(dossier.pk, self._pdf("rapport_v2.pdf"), etudiant)
                dossiers.soumettre(dossier.pk, etudiant)
            return
        dossiers.enregistrer_avis_pedagogique(
            v1.pk, encadreur, dossiers.AVIS_FAVORABLE, "Rapport recevable.",
        )
        if scenario == "recevable":
            dossiers.autoriser_soutenance(dossier.pk, responsable)

    # ------------------------------------------------------------------
    # Planning : soutenances acceptées et conflits refusés
    # ------------------------------------------------------------------

    def _tenter(self, libelle, dossier, jury, salle, debut, fin):
        """
        Tente une planification censée être REFUSÉE ; retourne le message de
        refus. Le point de sauvegarde garantit l'absence d'écriture.
        """
        try:
            with transaction.atomic():
                planifier_soutenance(dossier.pk, jury.pk, salle, debut, fin)
        except ConflitMetier as refus:
            # Refus attendu : la règle (EXG01) et le message lisible.
            return f"{libelle} : refusé ({refus.regle}) — {refus.detail}"
        raise CommandError(f"{libelle} : la tentative de conflit aurait dû être refusée.")

    def _planifier(self, d, jurys):
        """
        Quatre soutenances valides le 14/12/2026, puis deux tentatives de
        conflit (salle, personne) qui doivent être refusées.
        """
        alpha = jurys["Jury Alpha (démo)"]
        beta = jurys["Jury Bêta (démo)"]
        gamma = jurys["Jury Gamma (démo)"]
        salle1, salle2, salle3 = (nom for nom, _ in SALLES)

        soutenances = [
            planifier_soutenance(d[3].pk, alpha.pk, salle1, _heure(9), _heure(10)),
            planifier_soutenance(d[4].pk, beta.pk, salle2, _heure(9), _heure(10)),
            planifier_soutenance(d[5].pk, alpha.pk, salle1, _heure(14), _heure(15)),
        ]
        refus = [
            # Conflit de SALLE : Salle D1 déjà prise de 14 h à 15 h.
            self._tenter("Conflit de salle (Salle D1, 14 h 30-15 h 30)",
                         d[6], beta, salle1, _heure(14, 30), _heure(15, 30)),
            # Conflit de PERSONNE : Pr Konaté (jury Gamma) siège déjà à 9 h
            # dans le jury Alpha, dans une autre salle.
            self._tenter("Conflit de personne (Pr Konaté, 9 h 30-10 h 30)",
                         d[6], gamma, salle3, _heure(9, 30), _heure(10, 30)),
        ]
        # Le même dossier est ensuite planifié sur un créneau compatible.
        soutenances.append(
            planifier_soutenance(d[6].pk, gamma.pk, salle3, _heure(10, 30), _heure(11, 30))
        )
        return soutenances, refus

    # ------------------------------------------------------------------
    # Compte rendu
    # ------------------------------------------------------------------

    def _resume(self, dossiers_crees, soutenances, refus):
        """Affiche ce qui a été créé et les conflits refusés."""
        par_statut = {}
        for dossier in dossiers_crees.values():
            par_statut[dossier.status] = par_statut.get(dossier.status, 0) + 1
        self.stdout.write(self.style.SUCCESS(
            "Jeu de démonstration du chapitre 5 créé : 2 campagnes, "
            f"{len(dossiers_crees)} étudiants et dossiers, {len(ENCADREURS)} encadreurs, "
            f"{len(JURES)} jurés ({len(JURYS)} jurys), {len(SALLES)} salles, "
            f"{len(soutenances)} soutenances planifiées le 14/12/2026."
        ))
        self.stdout.write("Dossiers par statut : " + ", ".join(
            f"{statut} = {nombre}" for statut, nombre in sorted(par_statut.items())
        ))
        self.stdout.write(
            "Pièce remplacée : dossier DEMO5-007 (V1 avec corrections demandées, V2 soumise)."
        )
        self.stdout.write("Tentatives de conflit (aucune écriture) :")
        for ligne in refus:
            self.stdout.write(f"  - {ligne}")
        self.stdout.write(
            "Comptes : demo5.responsable, demo5.encadreur1 à 4, demo5.etu01 à 12, "
            "demo5.jure1 à 6 ; mot de passe = SGSUS_DEMO_PASSWORD (jamais affiché)."
        )
