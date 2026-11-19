"""
Tests des champs d'affichage de la liste des dossiers (/api/internship-folders/).

Ces champs en lecture seule permettent à l'écran « Dossiers » de montrer
d'un coup d'œil À QUI appartient le dossier, QUELLE version du rapport
attend une décision et QUELLE a été la dernière décision :

* `student_name`, `student_number`, `nombre_versions`, `derniere_version` ;
* `dernier_avis` : soumis à la MÊME règle de lecture que /api/reviews/
  (la matrice des droits n'est pas élargie) ;
* `derniere_etape` : dernière transition, avec son motif (ex. refus).

Le nombre de requêtes SQL de la liste ne dépend pas du nombre de dossiers.
"""
import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from api.models import StudentAccount

from .factories import affecter_encadreur, creer_avis, creer_compte, creer_dossier

pytestmark = pytest.mark.django_db

# Contenu minimal accepté par le contrôle de signature PDF du serveur.
PDF = b"%PDF-1.4 rapport fictif pour les tests d'affichage"


@pytest.fixture
def stockage(settings, tmp_path):
    """Fichiers déposés écrits dans un dossier temporaire."""
    settings.MEDIA_ROOT = str(tmp_path)
    return tmp_path


def client_de(compte):
    """Client API authentifié avec le compte donné."""
    client = APIClient()
    client.force_authenticate(user=compte)
    return client


def compte_etudiant(dossier):
    """Compte de connexion lié à l'étudiant du dossier."""
    compte = creer_compte("student")
    StudentAccount.objects.create(user=compte, student=dossier.student)
    return compte


def deposer(client, dossier):
    """Dépose une version PDF du rapport par l'API."""
    fichier = SimpleUploadedFile("rapport.pdf", PDF, content_type="application/pdf")
    return client.post("/api/documents/upload/",
                       {"folder_id": dossier.pk, "file": fichier}, format="multipart")


def dossier_liste(client, dossier):
    """Ligne du dossier dans la liste renvoyée au compte du client."""
    reponse = client.get("/api/internship-folders/")
    assert reponse.status_code == 200, reponse.content
    lignes = reponse.json()
    lignes = lignes["results"] if isinstance(lignes, dict) else lignes
    return next(ligne for ligne in lignes if ligne["id"] == dossier.pk)


def test_liste_indique_l_etudiant_et_la_version_a_examiner(stockage):
    """L'encadreur voit qui a déposé quoi, sans ouvrir le dossier."""
    dossier = creer_dossier("brouillon")
    etudiant = client_de(compte_etudiant(dossier))
    encadreur = client_de(affecter_encadreur(dossier))

    # Avant tout dépôt : aucune version, aucun avis.
    ligne = dossier_liste(encadreur, dossier)
    assert ligne["student_name"] == dossier.student.full_name
    assert ligne["student_number"] == dossier.student.student_number
    assert ligne["nombre_versions"] == 0
    assert ligne["derniere_version"] is None
    assert ligne["dernier_avis"] is None

    # Deux dépôts : la DERNIÈRE version est celle qui attend une décision.
    assert deposer(etudiant, dossier).status_code == 201
    assert deposer(etudiant, dossier).status_code == 201
    ligne = dossier_liste(encadreur, dossier)
    assert ligne["nombre_versions"] == 2
    assert ligne["derniere_version"]["version_number"] == 2
    assert ligne["derniere_version"]["uploaded_at"]


def test_dernier_avis_respecte_la_matrice_des_droits(stockage):
    """
    La demande de correction est lisible par l'étudiant et par son auteur,
    mais pas par le responsable (qui ne lit pas les avis dans /api/reviews/).
    """
    dossier = creer_dossier("brouillon")
    compte_eleve = compte_etudiant(dossier)
    etudiant = client_de(compte_eleve)
    compte_encadreur = affecter_encadreur(dossier)
    encadreur = client_de(compte_encadreur)
    responsable = client_de(creer_compte("responsible"))

    assert deposer(etudiant, dossier).status_code == 201
    assert etudiant.post(f"/api/internship-folders/{dossier.pk}/soumettre/").status_code == 200
    version = dossier.document_versions.get()
    reponse = encadreur.post("/api/reviews/", {
        "document_version": version.pk,
        "decision": "defavorable",
        "comments": "Ajouter la bibliographie.",
    }, format="json")
    assert reponse.status_code == 201, reponse.content

    for client in (etudiant, encadreur):
        avis = dossier_liste(client, dossier)["dernier_avis"]
        assert avis["decision"] == "defavorable"
        assert avis["comments"] == "Ajouter la bibliographie."
        assert avis["version_number"] == 1

    ligne_responsable = dossier_liste(responsable, dossier)
    assert ligne_responsable["dernier_avis"] is None
    # Le statut et la dernière étape restent visibles pour décider.
    assert ligne_responsable["status"] == "a_corriger"
    assert ligne_responsable["derniere_etape"]["statut_apres"] == "a_corriger"

    # Un autre encadreur affecté ne lit pas l'avis de son collègue.
    autre = client_de(affecter_encadreur(dossier))
    assert dossier_liste(autre, dossier)["dernier_avis"] is None


def test_motif_du_refus_visible_par_l_etudiant():
    """Après un refus, l'étudiant lit le motif directement dans la liste."""
    dossier = creer_dossier("soumis")
    etudiant = client_de(compte_etudiant(dossier))
    responsable = client_de(creer_compte("responsible"))

    reponse = responsable.post(f"/api/internship-folders/{dossier.pk}/refuser/",
                               {"motif": "Stage hors période."}, format="json")
    assert reponse.status_code == 200, reponse.content
    # La réponse de la transition porte déjà la nouvelle étape.
    assert reponse.json()["derniere_etape"]["motif"] == "Stage hors période."

    etape = dossier_liste(etudiant, dossier)["derniere_etape"]
    assert etape["statut_apres"] == "rejete"
    assert etape["motif"] == "Stage hors période."


def test_nombre_de_requetes_constant():
    """Lister 2 ou 6 dossiers coûte le même nombre de requêtes SQL."""
    administrateur = client_de(creer_compte("admin"))

    def requetes_de_la_liste():
        with CaptureQueriesContext(connection) as capture:
            assert administrateur.get("/api/internship-folders/").status_code == 200
        return len(capture.captured_queries)

    for _ in range(2):
        creer_avis(creer_dossier("soumis"))
    # Premier appel « de chauffe » : la fiche étudiante du compte est mise en
    # cache sur l'objet utilisateur ; seule la suite est comparée.
    requetes_de_la_liste()
    avant = requetes_de_la_liste()
    for _ in range(4):
        creer_avis(creer_dossier("soumis"))
    assert requetes_de_la_liste() == avant
