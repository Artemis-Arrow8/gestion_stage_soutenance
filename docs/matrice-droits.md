# Matrice des droits (chapitre 13 du dossier ALM)

Les droits sont contrôlés **côté serveur**, pour chaque objet, fichier et export ; masquer un bouton ne suffit jamais. Pour chaque accès accepté, au moins un essai refusé (autre utilisateur ou autre périmètre) est testé en appelant directement la route.

Légende :

- **✔** : autorisé ;
- **périm.** : seulement dans son périmètre ;
- **—** : refusé (403, ou 404 si l'objet est hors périmètre) ;
- **H** : seulement avec une habilitation nominative valide.

## Objets et actions

| Objet / action | Admin | Responsable | Encadreur | Jury | Étudiant | Test de refus |
|---|---|---|---|---|---|---|
| Comptes et rôles | ✔ | — | — | — | — | `test_auth.py` (comptes) |
| Campagnes, import d'étudiants | ✔ | ✔ | — | — | — | `test_auth.py`, `test_socle_alm.py::test_f01_…` |
| Dossier : lecture | ✔ | ✔ | périm. (affectés) | lecture seule, soutenances actives de son jury | périm. (le sien) | `test_auth.py::test_supervisor_ne_voit_que_…`, `test_socle_alm.py::test_le_jury_liste_en_lecture_seule_les_dossiers_de_ses_soutenances` |
| Dossier : création, modification descriptive | ✔ | ✔ | — | — | périm. (le sien) | `test_sgsus.py::test_student_cannot_create_a_folder_for_another_student` |
| Dossier : modifier le statut directement | — | — | — | — | — | `test_sta11_statut_non_modifiable_…` |
| Soumettre | ✔ | — | — | — | périm. | `test_f02_soumission_sans_rapport_refusee` |
| Avis pédagogique | ✔ | ✔ | périm. (dossier affecté, dernière version) | — | — | `test_auth.py::test_supervisor_can_only_read_and_create_their_own_reviews` |
| Autoriser, refuser, rouvrir | ✔ | ✔ | — | — | — | `test_sta11_…` |
| Confidentialité, habilitations | ✔ | ✔ | — | — | — | `test_sta08_…` |
| Jurys, salles, indisponibilités | ✔ | ✔ | — | lecture de son jury | — | `test_api_planning.py` |
| Soutenances : proposer, confirmer, publier, reporter, annuler | ✔ | ✔ | — | lecture (ses soutenances) | — | `test_api_soutenances.py` (rôles) |
| Convocations | toutes | toutes | — | les siennes | les siennes | `test_sta07_…` (visibilité étudiant) |
| Notes : saisie | ✔ | ✔ | — | périm. (son jury) | — | `test_le_jury_ne_voit_que_les_evaluations_de_ses_soutenances` |
| Notes : approbation | ✔ | ✔ | — | président de son jury | — | `test_president_du_jury_approuve_…` |
| Notes : rectification | ✔ | ✔ | — | — | — | idem (jury : 403) |
| Note approuvée : modification directe | — | — | — | — | — | `test_sta06_…` |
| Sa propre note approuvée (profil) | — | — | — | — | ✔ | `test_nouveaux_modules.py::ProfilEtudiantTests` |

## Pièces jointes (rapports PDF)

Les mêmes droits s'appliquent au fichier, à **toutes ses versions** et aux exports.

| Rapport | Admin | Responsable | Encadreur | Jury | Étudiant | Test |
|---|---|---|---|---|---|---|
| Standard | ✔ | ✔ | périm. | soutenance active de son jury | le sien | `test_sta04_…`, `test_le_jury_ne_consulte_que_les_rapports_de_ses_soutenances` |
| Confidentiel (embargo terminé ou non) | H | H | périm. | H | le sien | `test_sta08_…` |
| Habilitation révoquée ou expirée | — (même par l'ancienne URL) | — | — | — | — | `test_sta08_…` |

Chaque téléchargement, autorisé ou refusé, est inscrit dans `journal_acces_document` (compte, version, décision, motif), sans le contenu du document.

## Exports

L'export de retrait (`python manage.py exporter_donnees`) est une commande d'exploitation, sans route HTTP : seuls les administrateurs du serveur peuvent la lancer. Les comptes de connexion et les secrets n'y figurent jamais (`test_export_documente_et_reutilisable`).
