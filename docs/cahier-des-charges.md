# Cahier des charges — SGSUS

**Projet :** Système de gestion des stages et soutenances universitaires (SGSUS)
**Établissement (cas d'étude) :** Institut privé africain de technologies et de management (ITMA)
**Équipe (Groupe 4) :** Kadiatou Hélène GUINDO (auteure principale, lot 1), Mariam DIARRA, Kadidia DIARRA, Nahawa SANOGO
**Version initiale :** 23 octobre 2026 — **mise à jour :** 19 novembre 2026 (alignement sur le dossier ALM du 16 octobre 2026)
**Statut :** à faire relire par l'équipe et accepter par l'enseignant (commanditaire). Les modifications restent visibles dans l'historique Git.

> Les règles marquées **[hypothèse]** sont des choix de démonstration à confirmer avec l'enseignant ; elles ne sont pas des règles officielles de l'établissement (voir § 8, registre des ambiguïtés).

---

## 1. Contexte et objectifs

**Situation actuelle (à confirmer par l'entretien de cadrage, voir `cadrage.md`).** Le suivi des stages et l'organisation des soutenances reposent sur des documents papier, des courriels dispersés et des tableaux tenus à la main. Les risques observés sont la perte de dossiers, les relances manuelles et les conflits de planning : une salle réservée deux fois, ou un membre de jury convoqué à deux soutenances au même moment.

**Personnes concernées :** étudiants, encadreurs pédagogiques, responsable des stages, planificateur, membres de jury, scolarité.

**Objectifs et indicateurs de réussite :**

| Objectif | Indicateur mesurable |
|---|---|
| Aucun conflit de planning publié | 0 publication acceptée avec une salle ou un juré en double (test de concurrence STA03 réussi) |
| Avancement visible de chaque dossier | 100 % des transitions de dossier tracées (historique horodaté, acteur, motif) |
| Résultats fiables | Moyenne calculée côté serveur en décimal exact ; 0 note approuvée modifiée hors rectification |
| Moins de relances manuelles | Convocations produites automatiquement à chaque publication, avec suivi d'envoi |

## 2. Périmètre

**Socle (obligatoire) :**
- une campagne ;
- des dossiers individuels ;
- des encadreurs affectés ;
- des pièces versionnées ;
- des jurys et des salles ;
- un planning manuel avec détection des conflits, publication versionnée et convocations ;
- la saisie, l'approbation et la rectification des résultats selon une grille fictive.

**Réalisé en plus du socle :**
- mode hors ligne en consultation ;
- application Android (APK) ;
- version PC sans Internet ;
- import CSV des étudiants ;
- indisponibilités récurrentes.

**Exclusions explicites :**
- signature électronique qualifiée ;
- placement automatique en entreprise ;
- jugement automatique des rapports ;
- optimisation globale du planning ;
- import ICS et proposition automatique de créneaux : extensions non réalisées, voir STA13 ;
- envoi réel de courriels : un courriel est simulé par le backend console.

**Acteurs et interfaces externes simulées :**
- l'application Flutter (Web, Android, PC) ;
- l'API REST Django ;
- PostgreSQL 17 ;
- un service de courriel simulé.

## 3. Exigences

Format : identifiant, formulation observable, priorité (I = indispensable, S = souhaitable), source, critère de réception et preuve. La traçabilité complète (issue, modèle, PR, test, recette, version) est tenue dans `tracabilite.csv`.

### 3.1 Exigences fonctionnelles

| Id | Formulation observable | Prio. | Source | Critère de réception | Preuve |
|---|---|---|---|---|---|
| F01 | Le personnel ouvre une campagne et importe les étudiants (CSV) avec aperçu, rapport d'erreurs et contrôle des doublons. | I | Dossier ALM ch. 3 | Une seconde importation ne crée ni étudiant ni dossier en double. | `test_f01_seconde_importation_ne_cree_pas_deux_dossiers` |
| F02 | L'étudiant enregistre entreprise, sujet et versions PDF de son rapport ; chaque avis reste lié à la version examinée ; le rapport peut être déclaré confidentiel. | I | ch. 3 | L'ancienne version reste liée à la décision qui l'a examinée. | `test_sta05_avis_sur_v1_ne_couvre_pas_une_v2`, `test_sta08_…` |
| F03 | L'encadreur affecté donne un avis pédagogique ; le responsable autorise la soutenance. | I | ch. 3, ch. 4 | Un étudiant non recevable ne peut pas être publié au planning. | `test_f03_publication_refusee_si_un_dossier_n_est_plus_recevable` |
| F04 | Le personnel définit les jurys (membres, fonctions), les règles de composition et les indisponibilités récurrentes. | I | ch. 3 | Un jury incomplet ne peut pas être confirmé. | `test_f04_jury_incomplet_ne_peut_pas_etre_confirme`, `test_sta09_…` |
| F05 | Le planificateur choisit salle et intervalle, voit les conflits, publie une version figée et produit les convocations. | I | ch. 3 | Une modification publiée crée une nouvelle version identifiable. | `test_sta07_report_cree_une_version_et_remplace_les_convocations` |
| F06 | Le jury saisit les notes ; le président ou le responsable approuve ; seule une rectification motivée corrige une note approuvée. | I | ch. 3 | Une note approuvée n'est corrigée que par une procédure attribuée. | `test_sta06_…`, `test_sta12_…` |

### 3.2 Exigence critique et exigences non fonctionnelles

| Id | Formulation observable | Prio. | Critère / mesure | Preuve |
|---|---|---|---|---|
| EXG01 | Aucune publication ne réserve la même salle ou le même membre de jury sur deux intervalles qui se chevauchent. | I | Refus 409 identifiant la ressource ; une seule réservation retenue en cas de publications simultanées. | Contraintes d'exclusion PostgreSQL + verrou transactionnel ; `test_concurrence_exg01.py` (2 connexions réelles) |
| NFR01 | L'interface fonctionne sur un écran de 360 px de large ; les champs ont des libellés et les erreurs sont lisibles. | I | Aucun débordement à 360 px pour les 5 rôles. | Tests Flutter `accueil … lisible sur un téléphone de 360 px` |
| NFR02 | Les droits sont contrôlés côté serveur pour chaque objet, téléchargement et export. | I | Accès direct par URL refusé hors périmètre. | `test_sta04_…`, `test_sta08_…`, matrice des droits |
| NFR03 | Une coupure réseau produit un état compréhensible ; une opération non confirmée n'est jamais présentée comme réussie. | I | Bandeau « Mode hors ligne », écritures refusées avec message ; clé d'idempotence sur les opérations sensibles. | `test/hors_ligne_test.dart`, `test_idempotence_de_la_publication` |
| NFR04 | Dates stockées en UTC et affichées dans le fuseau métier (Africa/Bamako) ; notes en décimal exact, bornées de 0 à 20, arrondies au centième (demi supérieur). | I | 14 et 16 donnent 15,20 avec la grille 40/60. | `test_sta10_ponderation_40_60_et_note_absente` |
| NFR05 | Lectures courantes : p95 inférieur à 2 s avec 20 utilisateurs simulés sur le serveur décrit. | S | **À mesurer** : cible pédagogique, pas encore mesurée (voir réserves § 7). | — |

## 4. Règles métier

1. **Cycle du dossier.** Brouillon → soumis → à corriger ou validé → recevable ; refus motivé → rejeté ; réouverture motivée → soumis. Seuls les événements autorisés font changer le statut, et l'API refuse toute étape sautée (409). Un nouveau dépôt fait repasser un dossier validé ou recevable à « soumis » : sa recevabilité est réexaminée. Détail des acteurs et préconditions : `backend/api/services/dossiers.py`.
2. **Avis.** L'avis pédagogique de l'encadreur affecté porte sur la dernière version et reste attaché à la version examinée. **[hypothèse]** L'avis du tuteur en entreprise n'est pas une étape obligatoire pour la campagne de démonstration.
3. **Cycle de la soutenance.** Proposée → confirmée → publiée → tenue ; elle peut aussi être reportée ou annulée. La confirmation exige un dossier recevable et un jury complet. Une soutenance publiée ne se modifie plus directement : un report publie une nouvelle version et remplace les convocations. Une soutenance annulée libère sa salle et son jury.
4. **EXG01.** Intervalles fermés à gauche et ouverts à droite (`[début, fin)`). Deux créneaux jointifs sont acceptés avec une marge nulle. **[hypothèse]** La marge de déplacement vaut 0 par défaut et se règle par `SGSUS_MARGE_MINUTES`. Les indisponibilités récurrentes de la salle et des membres sont respectées.
5. **Composition du jury.** **[hypothèse]** Un jury est complet avec au moins 3 membres, dont un président et un rapporteur. Une personne ne figure qu'une fois dans un jury. Un jury dont la composition ne respecte plus la règle repasse à « incomplet ».
6. **Notes.** **[hypothèse]** La grille fictive pèse le rapport à 40 % et l'oral à 60 %, notes sur 20.
   - Le calcul est fait côté serveur en décimal exact. Une note absente reste absente et bloque l'approbation.
   - L'approbation exige un jury complet (quorum fictif) ; elle revient au président du jury ou au responsable.
   - La rectification est réservée au responsable, avec motif. Elle crée une nouvelle version du procès-verbal ; l'ancienne reste consultable.
   - La version de grille est figée dans chaque procès-verbal.
7. **Confidentialité.** Un rapport confidentiel n'est consultable que par :
   - l'étudiant ;
   - ses encadreurs ;
   - les titulaires d'une habilitation nominative valide.

   L'embargo limite la diffusion dans le temps ; sa fin ne rend rien public automatiquement. Chaque accès, autorisé ou refusé, est journalisé.
8. **Publication et notifications.** La publication vérifie toutes les règles dans une seule transaction : en cas de refus, rien n'est écrit. Les convocations sont mises « en attente d'envoi ». Un échec d'envoi peut être relancé et n'annule jamais le planning.

## 5. Données

### 5.1 Inventaire

| Information | Utilité | Origine | Personnes autorisées | Conservation | Suppression / archivage |
|---|---|---|---|---|---|
| Identité étudiant (matricule, nom, courriel) | Rattacher le dossier, convoquer | Import CSV ou saisie scolarité | Personnel ; l'étudiant pour lui-même | **À définir** avec le responsable métier | Export puis anonymisation en fin de cycle (à décider) |
| Dossier (entreprise, sujet, statut, historique) | Suivi du stage | Étudiant, encadreur, responsable | Étudiant, encadreurs affectés, personnel | À définir | Archivage avec le procès-verbal |
| Rapports PDF (versions) | Évaluation | Étudiant | Voir règle de confidentialité § 4.7 | À définir | Suppression des fichiers après la durée retenue |
| Avis, procès-verbaux, notes | Décisions et résultats | Encadreur, jury, responsable | Personnel ; l'étudiant voit sa note approuvée | Durée légale à vérifier | Jamais modifiés ; version nouvelle en cas de rectification |
| Planning, convocations | Organisation | Planificateur | Personnel ; chacun ses convocations | Durée de la campagne | Archivage |
| Journal d'accès aux rapports | Audit | Serveur | Administrateur | À définir | Purge périodique à décider |
| Comptes de connexion | Authentification | Administrateur | Administrateur | Durée d'activité | Désactivation puis suppression |

### 5.2 Fichiers, copies locales et sauvegardes

- **Fichiers téléversés :**
  - PDF uniquement (vérification de la signature), 10 Mo au plus ;
  - nom généré par le serveur ;
  - stockés hors du répertoire public et servis uniquement après contrôle des droits.
- **Copies locales :**
  - le mode hors ligne mémorise sur l'appareil les dernières données consultées (`SharedPreferences` / `localStorage`) ;
  - ces données sont effacées à la déconnexion ;
  - les jetons de session sont dans le stockage sécurisé.
- **Sauvegardes :**
  - `scripts/backup.ps1` réalise un dump PostgreSQL vers `backups/`, exclu de Git ;
  - la procédure de restauration est décrite dans `guide-exploitation.md`.
- **Export de retrait :** `python manage.py exporter_donnees` produit des fichiers JSON/CSV accompagnés d'un dictionnaire et d'un manifeste ; les comptes et les secrets sont exclus.

**Projet pédagogique : toutes les données sont fictives.** Pour un usage réel, il faudra identifier le responsable du traitement et faire vérifier les obligations applicables. La mention d'un règlement ne démontre pas une conformité.

## 6. Qualité attendue

- **Sécurité** :
  - JWT à durée courte, avec rotation et liste noire des jetons ;
  - limitation des tentatives de connexion (10 par minute et par adresse) ;
  - CORS limité aux origines connues ;
  - HTTPS et HSTS en production ;
  - rôle PostgreSQL applicatif à privilèges minimaux, vérifié par la CI ;
  - aucun mot de passe, jeton ni contenu de document dans les journaux.
- **Ergonomie** :
  - utilisable à partir de 360 px de large, à une main sur téléphone (navigation en bas) ;
  - messages d'erreur en français, accompagnés de la référence de la requête.
- **Disponibilité** :
  - sondes `/health/live` et `/health/ready` ;
  - journaux JSON avec `request_id` ;
  - version PC de secours sans Internet.
- **Performances** : NFR05, à mesurer (réserve).

## 7. Livraison et acceptation

- **Environnements :**
  - développement (Docker Compose local) ;
  - démonstration Render (API, site statique, PostgreSQL) ;
  - version PC hors ligne (profil `pc`) ;
  - APK Android.
- **Preuves attendues** :
  - rapport CI (JUnit et couverture) ;
  - image identifiée par le SHA du commit, avec son empreinte SHA-256 ;
  - recette (`recette.md`) ;
  - traçabilité (`tracabilite.csv`) ;
  - ADR ;
  - modèles (`docs/modeles`).
- **Réserves connues** :
  - NFR05 n'est pas encore mesurée ;
  - entretien utilisateur de cadrage à réaliser ou à documenter (voir `cadrage.md`) ;
  - issues et PR à créer et à relier dans `tracabilite.csv` ;
  - la recette doit être rejouée par une personne autre que l'auteur ;
  - le stockage des fichiers sur Render gratuit est éphémère.
- **Transmission** : installation reproductible, documentée dans le README et le guide d'exploitation, à refaire par une autre personne du groupe.

## 8. Registre des ambiguïtés

| # | Question | Propriétaire | Hypothèse retenue | Impact si elle change | Décision |
|---|---|---|---|---|---|
| A1 | Quelles pièces rendent un stage recevable et qui les valide ? | Référent métier | Un rapport PDF, l'avis favorable de l'encadreur, puis l'autorisation du responsable | Ajout de pièces obligatoires au contrôle de soumission | À valider avec l'enseignant |
| A2 | L'avis du tuteur en entreprise est-il obligatoire ? | Référent métier | Non pour la campagne de démonstration | Ajouter un événement « avis entreprise » et un rôle tuteur | À valider |
| A3 | Règle de composition du jury ? | Référent conception | ≥ 3 membres dont un président et un rapporteur | Modifier `api/services/jurys.py` | À valider |
| A4 | Grille de notation et arrondi ? | Référent métier | Rapport 40 %, oral 60 %, au centième, demi supérieur | Nouvelle version de grille (les procès-verbaux existants gardent l'ancienne) | Règle fictive, à valider |
| A5 | Qui approuve les résultats ? | Référent métier | Président du jury ou responsable ; rectification par le responsable seul | Modifier `api/services/notes.py` | À valider |
| A6 | Marge de déplacement entre deux soutenances ? | Planificateur | 0 minute (jointif accepté) | Régler `SGSUS_MARGE_MINUTES` | À valider |
| A7 | Fuseau métier ? | Référent métier | Africa/Bamako (UTC+0) | Régler `SGSUS_FUSEAU_METIER` | À valider |
| A8 | Qui publie le planning et autorise un report ? | Référent métier | Le personnel (administrateur, responsable) | Ajouter un rôle « planificateur » ou « scolarité » distinct | À valider |
| A9 | Durées de conservation des données ? | Responsable métier | Non définies (données fictives) | Politique de purge et d'archivage | À définir avant tout usage réel |
