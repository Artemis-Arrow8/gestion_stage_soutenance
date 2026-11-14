"""Fabriques de données entièrement fictives pour les tests."""

import itertools
from datetime import datetime, timezone

from django.db.backends.postgresql.psycopg_any import DateTimeTZRange

from api.models import (
    Campaign,
    Defense,
    DocumentVersion,
    InternshipFolder,
    Jury,
    JuryMember,
    Review,
    Student,
)

_compteur = itertools.count(1)

# Salles insérées par database/schema.sql
SALLES_DEMO = (
    ("Amphithéâtre A", 120),
    ("Salle 101", 30),
    ("Salle 102", 30),
    ("Salle 103", 25),
)


def t(heure, minute=0, jour=10):
    """Instant UTC le `jour` juillet 2026."""
    return datetime(2026, 7, jour, heure, minute, tzinfo=timezone.utc)


def creneau(h1, m1, h2, m2, jour=10):
    """Créneau [début, fin) en UTC."""
    return DateTimeTZRange(t(h1, m1, jour), t(h2, m2, jour), "[)")


def creer_dossier(statut="recevable"):
    n = next(_compteur)
    campagne = Campaign.objects.create(academic_year=f"2026-2027 (test {n})")
    etudiant = Student.objects.create(
        student_number=f"ETU{n:05d}",
        full_name=f"Étudiant Fictif {n}",
        email=f"etudiant{n}@example.org",
    )
    return InternshipFolder.objects.create(
        student=etudiant,
        campaign=campagne,
        company_name=f"Entreprise Fictive {n}",
        subject="Sujet de stage fictif",
        status=statut,
    )


def creer_jury(noms=None, nom=None):
    """Jury avec membres fictifs uniques (ou les noms fournis)."""
    n = next(_compteur)
    jury = Jury.objects.create(name=nom or f"Jury {n}")
    if noms is None:
        noms = (f"Président {n}", f"Rapporteur {n}", f"Examinateur {n}")
    roles = ("president", "rapporteur", "examinateur")
    for i, nom_membre in enumerate(noms):
        JuryMember.objects.create(
            jury=jury, member_name=nom_membre, role_in_jury=roles[i % 3]
        )
    return jury


def creer_version(dossier, numero=1):
    version, _ = DocumentVersion.objects.get_or_create(
        folder=dossier,
        version_number=numero,
        defaults={"file_path": f"rapports/fictif_v{numero}.pdf"},
    )
    return version


def creer_avis(dossier, decision="favorable", role="encadreur", version=1):
    """Avis rattaché à une version précise du rapport."""
    return Review.objects.create(
        document_version=creer_version(dossier, version),
        author_role=role,
        decision=decision,
    )


def creer_defense(dossier, jury, salle, slot, statut="planifie"):
    return Defense.objects.create(
        folder=dossier,
        jury=jury,
        room_name=salle,
        slot_range=slot,
        status=statut,
    )
