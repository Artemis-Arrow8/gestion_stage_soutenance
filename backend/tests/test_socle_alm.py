"""
Tests du socle du dossier ALM (chapitres 3 à 6 et cas de recette du chapitre 5).

Chaque test porte dans son nom l'identifiant de la règle ou du cas de recette
qu'il démontre (STA06, STA07…, F01, F04…) : il est référencé tel quel dans
docs/recette.md et docs/tracabilite.csv. Tous les tests tournent sur
PostgreSQL (contraintes réelles, transactions réelles).

Contenu :
* F02/F03 : parcours complet d'un dossier, étapes sautées (STA11) ;
* F06 : grille 40/60 et note absente (STA10), note approuvée (STA06),
  rectification versionnée (STA12), droits du jury ;
* F05 : publication versionnée, convocations, report (STA07), idempotence ;
* F04 : indisponibilité récurrente avec exception et fuseau (STA09),
  composition des jurys, alerte après publication ;
* F02 : confidentialité, embargo et habilitations (STA04, STA08) ;
* F01 : import idempotent des étudiants ;
* exploitation : sondes de santé, identifiant de requête, limitation des
  tentatives de connexion.
"""
from datetime import date
from decimal import Decimal
from unittest import mock

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient
from rest_framework.throttling import ScopedRateThrottle

from api.exceptions import ConflitMetier
from api.models import (
    Assessment,
    Convocation,
    Defense,
    HistoriqueDossier,
    Indisponibilite,
    InternshipFolder,
    JournalAccesDocument,
    JuryMember,
    JuryMemberAccount,
    ProcesVerbal,
    Student,
    StudentAccount,
    VersionPlanning,
)
from api.services import conflicts

from .factories import (
    affecter_encadreur,
    creer_compte,
    creer_defense,
    creer_dossier,
    creer_jury,
    creneau,
    t,
)

pytestmark = [pytest.mark.django_db, pytest.mark.usefixtures("salles_demo")]

PDF = b"%PDF-1.4 rapport fictif"


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

def client_de(compte):
    """Client API authentifié avec le compte donné."""
    client = APIClient()
    client.force_authenticate(user=compte)
    return client


def jury_complet(noms=None):
    """Jury de trois membres (président, rapporteur, examinateur) déclaré complet."""
    jury = creer_jury(noms=noms)
    jury.is_complete = True
    jury.save()
    return jury


def compte_etudiant(dossier):
    """Compte de connexion lié à l'étudiant du dossier."""
    compte = creer_compte("student")
    StudentAccount.objects.create(user=compte, student=dossier.student)
    return compte


def compte_membre(jury, role):
    """Compte de connexion lié au membre de `jury` ayant ce rôle."""
    membre = jury.members.get(role_in_jury=role)
    compte = creer_compte("jury")
    JuryMemberAccount.objects.create(user=compte, jury_member=membre)
    return compte


@pytest.fixture
def stockage(settings, tmp_path):
    """Fichiers déposés écrits dans un dossier temporaire."""
    settings.MEDIA_ROOT = str(tmp_path)
    return tmp_path


def deposer(client, dossier):
    """Dépose une version PDF du rapport par l'API."""
    fichier = SimpleUploadedFile("rapport.pdf", PDF, content_type="application/pdf")
    return client.post("/api/documents/upload/",
                       {"folder_id": dossier.pk, "file": fichier}, format="multipart")


# ---------------------------------------------------------------------------
# F02 / F03 : parcours du dossier et étapes sautées
# ---------------------------------------------------------------------------

def test_f03_parcours_complet_du_dossier_par_l_api(stockage):
    """Dépôt → soumission → avis favorable → autorisation : chaque étape est tracée."""
    dossier = creer_dossier("brouillon")
    etudiant = client_de(compte_etudiant(dossier))
    encadreur = affecter_encadreur(dossier)
    responsable = client_de(creer_compte("responsible"))

    assert deposer(etudiant, dossier).status_code == 201
    reponse = etudiant.post(f"/api/internship-folders/{dossier.pk}/soumettre/")
    assert reponse.status_code == 200, reponse.content
    assert reponse.json()["status"] == "soumis"

    version = dossier.document_versions.get()
    avis = client_de(encadreur).post("/api/reviews/", {
        "document_version": version.pk, "decision": "favorable", "comments": "Rapport complet",
    }, format="json")
    assert avis.status_code == 201, avis.content
    dossier.refresh_from_db()
    assert dossier.status == "valide"

    reponse = responsable.post(f"/api/internship-folders/{dossier.pk}/autoriser/")
    assert reponse.status_code == 200, reponse.content
    assert reponse.json()["status"] == "recevable"

    historique = etudiant.get(f"/api/internship-folders/{dossier.pk}/historique/").json()
    assert [ligne["evenement"] for ligne in historique] == [
        "nouvelle_version", "soumettre", "avis_favorable", "autoriser_soutenance",
    ]
    assert historique[-1]["statut_apres"] == "recevable"


def test_sta11_statut_non_modifiable_et_etape_sautee_refusee():
    """Le statut ne change ni par PATCH, ni en sautant une étape (STA11)."""
    dossier = creer_dossier("brouillon")
    responsable = client_de(creer_compte("responsible"))

    responsable.patch(f"/api/internship-folders/{dossier.pk}/", {"status": "recevable"},
                      format="json")
    dossier.refresh_from_db()
    assert dossier.status == "brouillon"

    reponse = responsable.post(f"/api/internship-folders/{dossier.pk}/autoriser/")
    assert reponse.status_code == 409
    assert reponse.json()["regle"] == "STA11"
    dossier.refresh_from_db()
    assert dossier.status == "brouillon"
    assert not HistoriqueDossier.objects.filter(dossier=dossier).exists()


def test_f02_soumission_sans_rapport_refusee():
    dossier = creer_dossier("brouillon")
    reponse = client_de(compte_etudiant(dossier)).post(
        f"/api/internship-folders/{dossier.pk}/soumettre/"
    )
    assert reponse.status_code == 409
    assert reponse.json()["regle"] == "F02"


def test_refus_motive_puis_reouverture():
    dossier = creer_dossier("soumis")
    responsable = client_de(creer_compte("responsible"))
    url = f"/api/internship-folders/{dossier.pk}"
    assert responsable.post(f"{url}/refuser/", {}, format="json").status_code == 400
    assert responsable.post(f"{url}/refuser/", {"motif": "Pièces manquantes"},
                            format="json").json()["status"] == "rejete"
    assert responsable.post(f"{url}/rouvrir/", {"motif": "Pièces reçues"},
                            format="json").json()["status"] == "soumis"


def test_un_seul_dossier_par_etudiant_et_par_campagne():
    dossier = creer_dossier()
    reponse = client_de(creer_compte("responsible")).post("/api/internship-folders/", {
        "student": dossier.student_id, "campaign": dossier.campaign_id,
        "company_name": "Autre", "subject": "Autre sujet",
    }, format="json")
    assert reponse.status_code == 409
    assert reponse.json()["regle"] == "F01"


# ---------------------------------------------------------------------------
# F06 : notes, grille et procès-verbaux
# ---------------------------------------------------------------------------

@pytest.fixture
def evaluation_du_jury():
    """Soutenance d'un jury complet, avec un responsable authentifié."""
    jury = jury_complet()
    defense = creer_defense(creer_dossier(), jury, "Salle 101", creneau(9, 0, 10, 0))
    return defense, jury, client_de(creer_compte("responsible"))


def test_sta10_ponderation_40_60_et_note_absente(evaluation_du_jury):
    """14 et 16 donnent 15,20 ; une note retirée reste absente et bloque l'approbation."""
    defense, _, responsable = evaluation_du_jury
    reponse = responsable.post("/api/assessments/", {
        "defense": defense.pk, "report_grade": "14", "oral_grade": "16",
    }, format="json")
    assert reponse.status_code == 201, reponse.content
    assert Decimal(reponse.json()["final_average"]) == Decimal("15.20")
    assert reponse.json()["grille"]["poids_oral"] == "0.600"

    evaluation = reponse.json()["id"]
    sans_oral = responsable.patch(f"/api/assessments/{evaluation}/", {"oral_grade": None},
                                  format="json")
    assert sans_oral.json()["final_average"] is None  # pas de zéro implicite
    refus = responsable.post(f"/api/assessments/{evaluation}/approuver/")
    assert refus.status_code == 409
    assert refus.json()["regle"] == "STA10"
    assert not ProcesVerbal.objects.exists()


def test_note_hors_bornes_refusee(evaluation_du_jury):
    defense, _, responsable = evaluation_du_jury
    reponse = responsable.post("/api/assessments/", {
        "defense": defense.pk, "report_grade": "21", "oral_grade": "10",
    }, format="json")
    assert reponse.status_code == 400


def test_sta06_note_approuvee_non_modifiable_par_appel_direct(evaluation_du_jury):
    defense, _, responsable = evaluation_du_jury
    evaluation = Assessment.objects.create(defense=defense, report_grade=12, oral_grade=13)
    assert responsable.post(f"/api/assessments/{evaluation.pk}/approuver/").status_code == 201
    modification = responsable.patch(f"/api/assessments/{evaluation.pk}/",
                                     {"report_grade": "20"}, format="json")
    assert modification.status_code == 409
    assert modification.json()["regle"] == "STA06"
    assert responsable.delete(f"/api/assessments/{evaluation.pk}/").status_code == 409
    evaluation.refresh_from_db()
    assert evaluation.report_grade == Decimal("12.00")


def test_sta12_rectification_versionnee_et_historique_conserve(evaluation_du_jury):
    defense, _, responsable = evaluation_du_jury
    evaluation = Assessment.objects.create(defense=defense, report_grade=12, oral_grade=13)
    responsable.post(f"/api/assessments/{evaluation.pk}/approuver/")
    url = f"/api/assessments/{evaluation.pk}/rectifier/"

    sans_motif = responsable.post(url, {"report_grade": "14", "oral_grade": "13"},
                                  format="json")
    assert sans_motif.status_code == 400
    pv = responsable.post(url, {"report_grade": "14", "oral_grade": "13",
                                "motif": "Erreur de report de la note écrite"}, format="json")
    assert pv.status_code == 201, pv.content
    assert pv.json()["version"] == 2 and pv.json()["moyenne"] == "13.40"

    versions = responsable.get(f"/api/assessments/{evaluation.pk}/proces-verbaux/").json()
    assert [(v["version"], v["statut"]) for v in versions] == [(1, "remplace"), (2, "approuve")]
    assert versions[1]["motif"] == "Erreur de report de la note écrite"
    assert versions[0]["moyenne"] == "12.60"  # l'ancienne version reste lisible


def test_president_du_jury_approuve_les_autres_membres_non(evaluation_du_jury):
    defense, jury, _ = evaluation_du_jury
    evaluation = Assessment.objects.create(defense=defense, report_grade=15, oral_grade=15)
    examinateur = client_de(compte_membre(jury, "examinateur"))
    president = client_de(compte_membre(jury, "president"))
    assert examinateur.post(f"/api/assessments/{evaluation.pk}/approuver/").status_code == 403
    assert president.post(f"/api/assessments/{evaluation.pk}/approuver/").status_code == 201
    # Le jury ne peut pas rectifier : procédure attribuée au responsable.
    rectif = president.post(f"/api/assessments/{evaluation.pk}/rectifier/",
                            {"report_grade": "16", "oral_grade": "15", "motif": "x"},
                            format="json")
    assert rectif.status_code == 403


def test_le_jury_ne_voit_que_les_evaluations_de_ses_soutenances(evaluation_du_jury):
    defense, jury, _ = evaluation_du_jury
    autre = creer_defense(creer_dossier(), jury_complet(), "Salle 102", creneau(9, 0, 10, 0))
    Assessment.objects.create(defense=defense)
    Assessment.objects.create(defense=autre)
    liste = client_de(compte_membre(jury, "rapporteur")).get("/api/assessments/").json()
    assert [e["defense"] for e in liste] == [defense.pk]


def test_approbation_bloquee_si_jury_incomplet():
    defense = creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0))
    evaluation = Assessment.objects.create(defense=defense, report_grade=10, oral_grade=10)
    reponse = client_de(creer_compte("responsible")).post(
        f"/api/assessments/{evaluation.pk}/approuver/"
    )
    assert reponse.status_code == 409 and reponse.json()["regle"] == "F06"


# ---------------------------------------------------------------------------
# F05 : publication, convocations, report
# ---------------------------------------------------------------------------

@pytest.fixture
def planning_confirme():
    """Deux soutenances confirmées (dossiers recevables, jurys complets)."""
    responsable = client_de(creer_compte("responsible"))
    soutenances = []
    for heure, salle in ((9, "Salle 101"), (11, "Salle 102")):
        soutenance = creer_defense(creer_dossier(), jury_complet(), salle,
                                   creneau(heure, 0, heure + 1, 0))
        reponse = responsable.post(f"/api/soutenances/{soutenance.pk}/confirmer/")
        assert reponse.status_code == 200, reponse.content
        soutenances.append(soutenance)
    return responsable, soutenances


def test_f05_publication_figee_avec_convocations(planning_confirme):
    responsable, soutenances = planning_confirme
    reponse = responsable.post("/api/soutenances/publier/", {"commentaire": "Session de juillet"},
                               format="json")
    assert reponse.status_code == 201, reponse.content
    assert reponse.json()["numero"] == 1 and reponse.json()["nombre_soutenances"] == 2
    # 1 étudiant + 3 membres de jury par soutenance.
    assert Convocation.objects.filter(statut="active").count() == 8
    assert set(Defense.objects.values_list("status", flat=True)) == {"publie"}
    detail = responsable.get(f"/api/soutenances/{soutenances[0].pk}/").json()
    assert detail["version_publiee"] == 1
    # Rien d'autre à publier : refus explicite.
    assert responsable.post("/api/soutenances/publier/").status_code == 409


def test_f03_publication_refusee_si_un_dossier_n_est_plus_recevable(planning_confirme):
    """Toutes les règles sont revérifiées ; un refus n'écrit rien (pas de publication partielle)."""
    responsable, soutenances = planning_confirme
    InternshipFolder.objects.filter(pk=soutenances[1].folder_id).update(status="soumis")
    reponse = responsable.post("/api/soutenances/publier/")
    assert reponse.status_code == 409
    assert any(f"#{soutenances[1].pk}" in p for p in reponse.json()["details"]["problemes"])
    assert not VersionPlanning.objects.exists()
    assert not Convocation.objects.exists()
    assert set(Defense.objects.values_list("status", flat=True)) == {"confirme"}


def test_sta07_report_cree_une_version_et_remplace_les_convocations(planning_confirme):
    responsable, soutenances = planning_confirme
    responsable.post("/api/soutenances/publier/")
    soutenance = soutenances[0]
    etudiant = compte_etudiant(soutenance.folder)
    Convocation.objects.filter(soutenance=soutenance, role_destinataire="etudiant").update(
        compte=etudiant
    )

    reponse = responsable.post(f"/api/soutenances/{soutenance.pk}/reporter/", {
        "slot_start": "2026-07-10T14:00:00Z", "slot_end": "2026-07-10T15:00:00Z",
        "motif": "Indisponibilité du président",
    }, format="json")
    assert reponse.status_code == 201, reponse.content
    assert reponse.json()["numero"] == 2

    anciennes = Convocation.objects.filter(soutenance=soutenance, version__numero=1)
    assert set(anciennes.values_list("statut", flat=True)) == {"remplacee"}
    assert all(c.remplacee_par is not None for c in anciennes)
    # L'étudiant voit sa nouvelle convocation ET l'ancienne, marquée remplacée.
    Convocation.objects.filter(soutenance=soutenance, role_destinataire="etudiant",
                               version__numero=2).update(compte=etudiant)
    vues = client_de(etudiant).get("/api/convocations/").json()
    assert sorted((c["version"], c["statut"]) for c in vues) == [(1, "remplacee"), (2, "active")]
    assert [c["remplacee_par_version"] for c in vues if c["version"] == 1] == [2]


def test_sta07_modification_directe_d_une_soutenance_publiee_refusee(planning_confirme):
    responsable, soutenances = planning_confirme
    responsable.post("/api/soutenances/publier/")
    reponse = responsable.patch(f"/api/soutenances/{soutenances[0].pk}/",
                                {"room_name": "Salle 103"}, format="json")
    assert reponse.status_code == 409 and reponse.json()["regle"] == "STA07"
    suppression = responsable.delete(f"/api/soutenances/{soutenances[0].pk}/")
    assert suppression.status_code == 409  # historique protégé : on annule


def test_annulation_libere_le_creneau_et_annule_les_convocations(planning_confirme):
    responsable, soutenances = planning_confirme
    responsable.post("/api/soutenances/publier/")
    soutenance = soutenances[0]
    reponse = responsable.post(f"/api/soutenances/{soutenance.pk}/annuler/",
                               {"motif": "Stage interrompu"}, format="json")
    assert reponse.json()["status"] == "annule"
    assert set(soutenance.convocations.values_list("statut", flat=True)) == {"annulee"}
    # La salle est libre de nouveau sur ce créneau.
    conflicts.planifier_soutenance(creer_dossier().pk, jury_complet().pk, "Salle 101",
                                   t(9), t(10))


def test_idempotence_de_la_publication(planning_confirme):
    """Même clé + même contenu : même résultat ; contenu différent : refus."""
    responsable, _ = planning_confirme
    entete = {"HTTP_IDEMPOTENCY_KEY": "9df2-demo-operation-001"}
    premiere = responsable.post("/api/soutenances/publier/", {"commentaire": "v1"},
                                format="json", **entete)
    seconde = responsable.post("/api/soutenances/publier/", {"commentaire": "v1"},
                               format="json", **entete)
    assert premiere.status_code == seconde.status_code == 201
    assert premiere.json() == seconde.json()
    assert seconde["Idempotent-Replayed"] == "true"
    assert VersionPlanning.objects.count() == 1
    autre = responsable.post("/api/soutenances/publier/", {"commentaire": "autre"},
                             format="json", **entete)
    assert autre.status_code == 409 and autre.json()["regle"] == "IDEMPOTENCE"


def test_f04_jury_incomplet_ne_peut_pas_etre_confirme():
    soutenance = creer_defense(creer_dossier(), creer_jury(), "Salle 101", creneau(9, 0, 10, 0))
    reponse = client_de(creer_compte("responsible")).post(
        f"/api/soutenances/{soutenance.pk}/confirmer/"
    )
    assert reponse.status_code == 409 and reponse.json()["regle"] == "F04"


# ---------------------------------------------------------------------------
# F04 : composition des jurys et indisponibilités
# ---------------------------------------------------------------------------

def test_f04_regle_de_composition_des_jurys():
    responsable = client_de(creer_compte("responsible"))
    jury = creer_jury(noms=("Dr A", "Dr B"))  # président + rapporteur seulement
    refus = responsable.patch(f"/api/jurys/{jury.pk}/", {"is_complete": True}, format="json")
    assert refus.status_code == 400
    JuryMember.objects.create(jury=jury, member_name="Dr C", role_in_jury="examinateur")
    assert responsable.patch(f"/api/jurys/{jury.pk}/", {"is_complete": True},
                             format="json").status_code == 200
    # Une personne ne figure qu'une fois dans un jury.
    doublon = responsable.post("/api/jury-members/", {
        "jury": jury.pk, "member_name": "dr a", "role_in_jury": "examinateur",
    }, format="json")
    assert doublon.status_code == 400
    # Retirer un membre rend le jury incomplet.
    membre = jury.members.get(member_name="Dr C")
    assert responsable.delete(f"/api/jury-members/{membre.pk}/").status_code == 204
    jury.refresh_from_db()
    assert jury.is_complete is False


def test_sta09_indisponibilite_recurrente_avec_exception_et_fuseau():
    """
    « Chaque vendredi de 9 h à 12 h, heure de Lagos (UTC+1) » : 10 h-11 h UTC
    (11 h-12 h à Lagos) est refusé, 11 h-12 h UTC (12 h-13 h) est accepté ;
    une exception le 10/07/2026 libère ce jour-là.
    """
    jury = jury_complet(noms=("Pr Indispo", "Dr Rapporteur", "Dr Examinateur"))
    regle = Indisponibilite.objects.create(
        type_ressource="membre", ressource="Pr Indispo", jour_semaine=4,
        heure_debut="09:00", heure_fin="12:00", fuseau="Africa/Lagos",
        valide_du=date(2026, 7, 1), valide_au=date(2026, 7, 31),
    )
    with pytest.raises(ConflitMetier) as exc:
        conflicts.planifier_soutenance(creer_dossier().pk, jury.pk, "Salle 101", t(10), t(11))
    assert exc.value.regle == "F04" and "Pr Indispo" in str(exc.value.detail)
    conflicts.planifier_soutenance(creer_dossier().pk, jury.pk, "Salle 101", t(11), t(12))
    # Le vendredi suivant (17/07) reste indisponible…
    with pytest.raises(ConflitMetier):
        conflicts.planifier_soutenance(creer_dossier().pk, jury.pk, "Salle 102",
                                       t(9, jour=17), t(10, jour=17))
    # … mais l'exception du 10/07 libère ce jour-là.
    regle.exceptions.create(date=date(2026, 7, 10))
    conflicts.planifier_soutenance(creer_dossier().pk, jury.pk, "Salle 102", t(9), t(10))


def test_indisponibilite_ajoutee_apres_publication_donne_une_alerte(planning_confirme):
    """Une soutenance publiée n'est jamais déplacée automatiquement : alerte seulement."""
    responsable, soutenances = planning_confirme
    responsable.post("/api/soutenances/publier/")
    reponse = responsable.post("/api/indisponibilites/", {
        "type_ressource": "salle", "ressource": "Salle 101", "jour_semaine": 4,
        "heure_debut": "08:00", "heure_fin": "18:00",
        "valide_du": "2026-07-01", "valide_au": "2026-07-31",
        "exceptions": ["2026-07-24"],
    }, format="json")
    assert reponse.status_code == 201, reponse.content
    assert reponse.json()["fuseau"] == "Africa/Bamako"  # fuseau métier par défaut
    assert reponse.json()["exceptions"] == ["2026-07-24"]
    assert [a["soutenance"] for a in reponse.json()["alertes"]] == [soutenances[0].pk]
    soutenances[0].refresh_from_db()
    assert soutenances[0].status == "publie"


# ---------------------------------------------------------------------------
# F02 : confidentialité, embargo et habilitations (STA04, STA08)
# ---------------------------------------------------------------------------

@pytest.fixture
def rapport_depose(stockage):
    """Dossier avec une version PDF déposée par l'étudiant."""
    dossier = creer_dossier("soumis")
    etudiant = compte_etudiant(dossier)
    assert deposer(client_de(etudiant), dossier).status_code == 201
    return dossier, dossier.document_versions.get(), etudiant


def test_sta04_un_etudiant_n_ouvre_pas_le_rapport_d_un_autre(rapport_depose):
    dossier, version, _ = rapport_depose
    intrus = compte_etudiant(creer_dossier())
    reponse = client_de(intrus).get(f"/api/documents/download/{version.pk}/")
    assert reponse.status_code == 403
    assert JournalAccesDocument.objects.filter(autorise=False, utilisateur=intrus).exists()


def test_sta08_rapport_confidentiel_refuse_meme_apres_embargo(rapport_depose):
    dossier, version, etudiant = rapport_depose
    responsable_compte = creer_compte("responsible")
    responsable = client_de(responsable_compte)
    url = f"/api/documents/download/{version.pk}/"
    assert responsable.get(url).status_code == 200  # dossier standard

    reglage = responsable.put(f"/api/internship-folders/{dossier.pk}/confidentialite/", {
        "niveau": "confidentiel", "origine": "Clause de l'entreprise",
        "embargo_jusqu_au": "2026-01-01", "diffusion_autorisee": False,
    }, format="json")
    assert reglage.status_code == 200, reglage.content
    # Embargo terminé, mais aucune publication automatique : refus.
    assert responsable.get(url).status_code == 403
    assert client_de(etudiant).get(url).status_code == 200  # le titulaire garde l'accès

    habilitation = responsable.post("/api/habilitations/", {
        "dossier": dossier.pk, "beneficiaire": responsable_compte.pk,
    }, format="json")
    assert habilitation.status_code == 201, habilitation.content
    assert responsable.get(url).status_code == 200
    # Retrait de l'habilitation : l'accès cesse, même par la même URL.
    responsable.delete(f"/api/habilitations/{habilitation.json()['id']}/")
    assert responsable.get(url).status_code == 403
    decisions = list(JournalAccesDocument.objects.filter(utilisateur=responsable_compte)
                     .order_by("pk").values_list("autorise", flat=True))
    assert decisions == [True, False, True, False]


def test_le_jury_ne_consulte_que_les_rapports_de_ses_soutenances(rapport_depose):
    dossier, version, _ = rapport_depose
    jury = jury_complet()
    membre = compte_membre(jury, "rapporteur")
    url = f"/api/documents/download/{version.pk}/"
    assert client_de(membre).get(url).status_code == 403
    InternshipFolder.objects.filter(pk=dossier.pk).update(status="recevable")
    creer_defense(dossier, jury, "Salle 101", creneau(9, 0, 10, 0))
    assert client_de(membre).get(url).status_code == 200


def test_le_jury_liste_en_lecture_seule_les_dossiers_de_ses_soutenances(rapport_depose):
    """
    Écran « Rapports à lire » : le jury liste les dossiers (et leurs
    versions) des soutenances actives de SON jury, et rien d'autre ; il ne
    peut ni modifier un dossier ni déposer un rapport.
    """
    dossier, version, _ = rapport_depose
    jury = jury_complet()
    client = client_de(compte_membre(jury, "rapporteur"))

    # Avant toute soutenance : liste vide, fiche introuvable (404).
    assert client.get("/api/internship-folders/").json() == []
    assert client.get("/api/document-versions/").json() == []
    assert client.get(f"/api/internship-folders/{dossier.pk}/").status_code == 404

    InternshipFolder.objects.filter(pk=dossier.pk).update(status="recevable")
    soutenance = creer_defense(dossier, jury, "Salle 101", creneau(9, 0, 10, 0))
    assert [d["id"] for d in client.get("/api/internship-folders/").json()] == [dossier.pk]
    assert [v["id"] for v in client.get("/api/document-versions/").json()] == [version.pk]

    # Lecture seule : aucune écriture n'est permise au jury.
    assert client.patch(f"/api/internship-folders/{dossier.pk}/",
                        {"subject": "Autre"}, format="json").status_code == 403
    assert client.post(f"/api/internship-folders/{dossier.pk}/autoriser/").status_code == 403

    # Soutenance annulée : le dossier disparaît de sa liste.
    soutenance.status = "annule"
    soutenance.save(update_fields=["status"])
    assert client.get("/api/internship-folders/").json() == []


# ---------------------------------------------------------------------------
# F01 : import idempotent des étudiants
# ---------------------------------------------------------------------------

CSV = (
    "matricule;nom;email\n"
    "IMP-001;Awa Traoré;awa.traore@example.org\n"
    "IMP-002;Moussa Keita;moussa.keita@example.org\n"
    "IMP-003;Fanta Coulibaly;pas-un-email\n"
)


def test_f01_seconde_importation_ne_cree_pas_deux_dossiers():
    campagne = creer_dossier().campaign
    responsable = client_de(creer_compte("responsible"))

    apercu = responsable.post("/api/students/importer/",
                              {"campagne": campagne.pk, "csv": CSV, "simulation": True},
                              format="json").json()
    assert apercu["simulation"] is True and apercu["etudiants_crees"] == 2
    assert not Student.objects.filter(student_number__startswith="IMP-").exists()

    premier = responsable.post("/api/students/importer/",
                               {"campagne": campagne.pk, "csv": CSV}, format="json").json()
    assert (premier["etudiants_crees"], premier["dossiers_crees"]) == (2, 2)
    assert premier["erreurs"] == [{"ligne": 4, "erreur": "E-mail invalide : pas-un-email"}]

    second = responsable.post("/api/students/importer/",
                              {"campagne": campagne.pk, "csv": CSV}, format="json").json()
    assert (second["etudiants_crees"], second["dossiers_crees"]) == (0, 0)
    assert (second["etudiants_existants"], second["dossiers_existants"]) == (2, 2)
    assert InternshipFolder.objects.filter(campaign=campagne,
                                           student__student_number__startswith="IMP-").count() == 2


def test_f01_import_signale_un_matricule_existant_avec_un_autre_email():
    campagne = creer_dossier().campaign
    Student.objects.create(student_number="IMP-010", full_name="X", email="x@example.org")
    rapport = client_de(creer_compte("responsible")).post("/api/students/importer/", {
        "campagne": campagne.pk,
        "csv": "matricule,nom,email\nIMP-010,X,autre@example.org\n",
    }, format="json").json()
    assert rapport["etudiants_crees"] == 0 and len(rapport["erreurs"]) == 1
    assert Student.objects.get(student_number="IMP-010").email == "x@example.org"


# ---------------------------------------------------------------------------
# Exploitation : sondes, identifiant de requête, limitation des connexions
# ---------------------------------------------------------------------------

def test_sondes_de_sante_live_et_ready(client):
    live = client.get("/health/live")
    assert live.status_code == 200 and live.json() == {"status": "ok"}
    ready = client.get("/health/ready/")
    assert ready.status_code == 200 and ready.json()["database"] == "ok"


def test_identifiant_de_requete_renvoye(client):
    genere = client.get("/api/login/")
    assert len(genere["X-Request-ID"]) == 16
    fourni = client.get("/api/login/", HTTP_X_REQUEST_ID="req-demo-17")
    assert fourni["X-Request-ID"] == "req-demo-17"


def test_limitation_des_tentatives_de_connexion(client):
    with mock.patch.object(ScopedRateThrottle, "THROTTLE_RATES", {"connexion": "3/minute"}):
        codes = [
            client.post("/api/login/", {"username": "inconnu", "password": "faux"},
                        content_type="application/json").status_code
            for _ in range(4)
        ]
    assert codes[:3] == [401, 401, 401]
    assert codes[3] == 429


# ---------------------------------------------------------------------------
# Exploitation : notifications relançables et export de retrait (ch. 12, 23)
# ---------------------------------------------------------------------------

def test_echec_de_notification_n_efface_pas_le_planning(planning_confirme, settings):
    """Une convocation sans adresse passe en échec, relançable ; le planning reste publié."""
    from django.core.management import call_command

    settings.EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
    responsable, soutenances = planning_confirme
    responsable.post("/api/soutenances/publier/")
    convocation = Convocation.objects.filter(soutenance=soutenances[0]).first()
    compte = creer_compte("student")
    compte.email = "etudiant@example.org"
    compte.save()
    Convocation.objects.filter(pk=convocation.pk).update(compte=compte)

    call_command("envoyer_convocations")
    convocation.refresh_from_db()
    assert convocation.notification == "envoyee"
    assert Convocation.objects.filter(notification="echec").count() == 7
    assert set(Defense.objects.values_list("status", flat=True)) == {"publie"}
    call_command("envoyer_convocations")  # relance : les échecs sont retentés
    assert Convocation.objects.filter(notification="echec", tentatives_envoi=2).count() == 7


def test_export_documente_et_reutilisable(planning_confirme, tmp_path):
    """L'export contient chaque table, son dictionnaire et un manifeste cohérent."""
    import json

    from django.core.management import call_command

    call_command("exporter_donnees", sortie=str(tmp_path))
    manifeste = json.loads((tmp_path / "manifeste.json").read_text(encoding="utf-8"))
    dictionnaire = json.loads((tmp_path / "dictionnaire.json").read_text(encoding="utf-8"))
    soutenances = json.loads((tmp_path / "defense.json").read_text(encoding="utf-8"))
    assert manifeste["lignes_par_table"]["defense"] == len(soutenances) == 2
    assert dictionnaire["defense"]["champs"]["slot_range"]["format"] == "ISO 8601, UTC"
    assert "password" not in (tmp_path / "student.json").read_text(encoding="utf-8")
