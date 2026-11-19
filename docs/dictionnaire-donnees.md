# Dictionnaire de données — SGSUS

Généré à partir des modèles Django (`backend/api/models.py`) le 19/11/2026 ; la description
reprend le commentaire du champ dans le code. **Source** : *client* = saisi par un utilisateur
(contrôlé par le serveur), *serveur* = calculé ou imposé par le serveur. Dates stockées en UTC,
affichées dans le fuseau métier (Africa/Bamako). Notes sur 20, décimal exact.

## Campaign — table `campaign`

Campagne académique (une année universitaire de stages). *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `academic_year` | texte (50) | oui | — | client | Année universitaire, ex. « 2026-2027 ». |  |
| `is_active` | booléen | oui | `True` | client | Campagne en cours (les nouveaux dossiers s'y rattachent). |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | Date de création, renseignée automatiquement. |  |

## Student — table `student`

Fiche d'un étudiant inscrit (distincte de son compte de connexion). *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `student_number` | texte (100) | oui | — | client | Matricule unique, ex. « ETU-2026-001 ». | unique |
| `full_name` | texte (255) | oui | — | client | Prénom et nom. |  |
| `email` | texte (254) | oui | — | client | Adresse e-mail unique. | unique |

## StudentAccount — table `student_account`

Lie un compte de connexion Django à une fiche étudiante (relation 1:1). *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `user_id` | référence → `auth_user` | oui | — | client | Compte de connexion (un compte ne peut être lié qu'à une fiche). | unique |
| `student_id` | référence → `student` | oui | — | client | Fiche étudiante (une fiche ne peut être liée qu'à un compte). | unique |

## FolderSupervisor — table `folder_supervisor`

Affecte un encadreur à un dossier de stage précis. *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `user_id` | référence → `auth_user` | oui | — | client | Compte de l'encadreur. |  |
| `folder_id` | référence → `internship_folder` | oui | — | client | Dossier suivi. |  |

## InternshipFolder — table `internship_folder`

Dossier de stage d'un étudiant pour une campagne. *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `student_id` | référence → `student` | oui | — | client | Étudiant propriétaire du dossier. | Unique avec campaign (un dossier par étudiant et par campagne) |
| `campaign_id` | référence → `campaign` | oui | — | client | Campagne de rattachement. |  |
| `company_name` | texte (255) | oui | — | client | Entreprise d'accueil. |  |
| `subject` | texte long | oui | — | client | Sujet du stage. |  |
| `status` | texte (50) | oui | `brouillon` | serveur | Statut du dossier (voir le cycle de vie ci-dessus). | Change seulement par les transitions (api/services/dossiers.py) |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | Date de création, renseignée automatiquement. |  |

## DocumentVersion — table `document_version`

Version déposée d'un rapport de stage (PDF). *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `folder_id` | référence → `internship_folder` | oui | — | client | Dossier auquel appartient la version. |  |
| `version_number` | entier | oui | — | serveur | Numéro de version, croissant pour un même dossier. |  |
| `file_path` | texte (255) | oui | — | client | Chemin du fichier dans le stockage (MEDIA_ROOT). |  |
| `uploaded_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | Date de dépôt, renseignée automatiquement. |  |

## Review — table `review`

Avis d'un encadreur sur une version de document. *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `document_version_id` | référence → `document_version` | oui | — | client | Version de document évaluée. |  |
| `author_id` | référence → `auth_user` | non | — | client | Auteur de l'avis (conservé à NULL si son compte est supprimé). |  |
| `author_role` | texte (50) | oui | — | client | Rôle de l'auteur au moment de l'avis (ex. « encadreur »). |  |
| `decision` | texte (50) | oui | — | client | Décision : « favorable » ou « defavorable ». |  |
| `comments` | texte long | non | — | client | Commentaire libre facultatif. |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | Date de l'avis, renseignée automatiquement. |  |

## Room — table `room`

Salle pouvant accueillir des soutenances. *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `name` | texte (100) | oui | — | client | Nom unique de la salle (référencé par Defense.room_name). | unique |
| `capacity` | entier | oui | — | client | Nombre de places. |  |
| `is_active` | booléen | oui | `True` | client | Une salle inactive n'est plus proposée à la planification. |  |

## Jury — table `jury`

Jury de soutenance, composé de plusieurs membres. *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `name` | texte (100) | oui | — | client | Nom du jury, ex. « Jury Informatique A ». |  |
| `is_complete` | booléen | oui | `False` | client | Vrai lorsque la composition est déclarée complète. |  |

## JuryMember — table `jury_member`

Membre d'un jury (président, rapporteur ou examinateur). *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `jury_id` | référence → `jury` | oui | — | client | Jury d'appartenance. |  |
| `member_name` | texte (255) | oui | — | client | Nom du membre (sert aussi à détecter qu'un membre siège deux fois). |  |
| `role_in_jury` | texte (100) | oui | — | client | Rôle : « president », « rapporteur » ou « examinateur ». |  |

## JuryMemberAccount — table `jury_member_account`

Lie un compte de connexion Django à un membre de jury (relation 1:1). *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `user_id` | référence → `auth_user` | oui | — | client | Compte de connexion. | unique |
| `jury_member_id` | référence → `jury_member` | oui | — | client | Membre de jury représenté par ce compte. | unique |

## Defense — table `defense`

Soutenance planifiée : un dossier, un jury, une salle et un créneau. *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `folder_id` | référence → `internship_folder` | oui | — | client | Dossier soutenu. |  |
| `jury_id` | référence → `jury` | non | — | client | Jury (conservé à NULL si le jury est supprimé). |  |
| `room_name` | texte (100) | oui | — | client | Nom de la salle (correspond à Room.name). |  |
| `slot_range` | tstzrange UTC | oui | — | client | — | Intervalle [début, fin) UTC ; EXG01 : exclusion par salle et par jury (hors annulées) |
| `status` | texte (50) | oui | `planifie` | serveur | Statut de la soutenance. | Change seulement par les actions confirmer / publier / reporter / annuler / tenue |

## Assessment — table `assessment`

Évaluation d'une soutenance : notes sur 20 et validation finale. *Gestion : schéma historique (database/schema.sql).*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `defense_id` | référence → `defense` | oui | — | client | Soutenance évaluée. |  |
| `report_grade` | décimal (5,2) | non | — | client | Note du rapport écrit (0 à 20). | 0 ≤ note ≤ 20 (contrainte CHECK) ; absente = NULL, jamais 0 |
| `oral_grade` | décimal (5,2) | non | — | client | Note de l'oral (0 à 20). | 0 ≤ note ≤ 20 (contrainte CHECK) ; absente = NULL, jamais 0 |
| `final_average` | décimal (5,2) | non | — | serveur | Moyenne finale (0 à 20), calculée par l'API si non saisie. | Calculée par le serveur : poids_rapport × rapport + poids_oral × oral, arrondi au centième |
| `is_approved` | booléen | oui | `False` | serveur | Validation de la note par le personnel. |  |

## HistoriqueDossier — table `historique_dossier`

Trace d'une transition de dossier (« la preuve conservée », chapitre 4). *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `dossier_id` | référence → `internship_folder` | oui | — | client | Dossier concerné ; PROTECT : un historique validé ne disparaît pas par une suppression en cascade (chapitre 4). |  |
| `evenement` | texte (50) | oui | — | serveur | Nom stable de l'événement (voir api/services/dossiers.py). |  |
| `statut_avant` | texte (50) | oui | — | serveur | Statut avant et après la transition. |  |
| `statut_apres` | texte (50) | oui | — | serveur | — |  |
| `acteur_id` | référence → `auth_user` | non | — | client | Auteur de la transition (conservé à NULL si son compte disparaît). |  |
| `motif` | texte long | non | `` | client | Motif (obligatoire pour une demande de correction ou un refus). |  |
| `version_document_id` | référence → `document_version` | non | — | client | Version du rapport sur laquelle porte la décision. |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## ConfidentialiteDossier — table `confidentialite_dossier`

Niveau de confidentialité des rapports d'un dossier (complément F02). *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `dossier_id` | référence → `internship_folder` | oui | — | client | — | unique |
| `niveau` | texte (20) | oui | `standard` | client | — |  |
| `origine` | texte (255) | non | `` | client | Origine de la restriction (ex. « clause de l'entreprise d'accueil »). |  |
| `embargo_jusqu_au` | date (AAAA-MM-JJ) | non | — | client | Fin de l'embargo de diffusion (aucun effet automatique). |  |
| `diffusion_autorisee` | booléen | oui | `False` | client | Décision explicite de diffusion, prise par une personne habilitée. |  |
| `decide_par_id` | référence → `auth_user` | non | — | client | — |  |
| `updated_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## HabilitationDossier — table `habilitation_dossier`

Autorisation nominative de consulter les rapports d'un dossier *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `dossier_id` | référence → `internship_folder` | oui | — | client | — |  |
| `beneficiaire_id` | référence → `auth_user` | oui | — | client | — |  |
| `valide_du` | date-heure UTC (ISO 8601) | oui | — | client | — |  |
| `valide_au` | date-heure UTC (ISO 8601) | non | — | client | Fin de validité (NULL : jusqu'au retrait). |  |
| `revoquee` | booléen | oui | `False` | client | — |  |
| `accordee_par_id` | référence → `auth_user` | non | — | client | — |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## JournalAccesDocument — table `journal_acces_document`

Journal d'audit des accès aux rapports (autorisés ou refusés). *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `version_document_id` | entier | oui | — | client | — |  |
| `utilisateur_id` | référence → `auth_user` | non | — | client | — |  |
| `action` | texte (30) | oui | `telechargement` | client | — |  |
| `autorise` | booléen | oui | — | client | — |  |
| `motif` | texte (255) | non | `` | client | Raison d'un refus (aucune donnée confidentielle). |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## GrilleEvaluation — table `grille_evaluation`

Grille de notation d'une campagne, versionnée et figée une fois utilisée. *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `campagne_id` | référence → `campaign` | oui | — | client | — |  |
| `version` | entier ≥ 0 | oui | `1` | serveur | — |  |
| `poids_rapport` | décimal (4,3) | oui | `0.400` | client | Coefficients exacts (type décimal), dont la somme doit valoir 1. | poids_rapport + poids_oral = 1 (contrainte CHECK) |
| `poids_oral` | décimal (4,3) | oui | `0.600` | client | — |  |
| `note_maximale` | décimal (5,2) | oui | `20` | client | Borne supérieure de chaque note (la borne inférieure est 0). |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## ProcesVerbal — table `proces_verbal`

Version d'un procès-verbal de soutenance (approbation ou rectification). *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `evaluation_id` | référence → `assessment` | oui | — | client | PROTECT : un PV validé ne disparaît pas avec l'évaluation. |  |
| `version` | entier ≥ 0 | oui | — | serveur | — | Unique avec evaluation ; une rectification crée la version suivante |
| `grille_id` | référence → `grille_evaluation` | oui | — | client | — |  |
| `note_rapport` | décimal (5,2) | oui | — | client | — |  |
| `note_oral` | décimal (5,2) | oui | — | client | — |  |
| `moyenne` | décimal (5,2) | oui | — | serveur | — |  |
| `membres_jury` | JSON | oui | — | client | Composition du jury au moment de l'approbation : [{"nom", "role"}]. |  |
| `statut` | texte (20) | oui | `approuve` | client | — |  |
| `motif` | texte long | non | `` | client | Motif de la rectification (vide pour la première approbation). |  |
| `approuve_par_id` | référence → `auth_user` | non | — | client | — |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## VersionPlanning — table `version_planning`

Version figée du planning, créée à chaque publication. *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `numero` | entier ≥ 0 | oui | — | serveur | — | unique |
| `publiee_par_id` | référence → `auth_user` | non | — | client | — |  |
| `publiee_le` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |
| `commentaire` | texte long | non | `` | client | — |  |
| `nombre_soutenances` | entier ≥ 0 | oui | `0` | client | Nombre de soutenances publiées ou republiées dans cette version. |  |

## Convocation — table `convocation`

Convocation d'un participant (étudiant ou membre du jury) à une *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `version_id` | référence → `version_planning` | oui | — | serveur | — |  |
| `soutenance_id` | référence → `defense` | oui | — | client | PROTECT : une soutenance publiée ne se supprime pas (on l'annule). |  |
| `destinataire` | texte (255) | oui | — | client | — |  |
| `role_destinataire` | texte (50) | oui | — | client | etudiant, president, rapporteur, examinateur… |  |
| `compte_id` | référence → `auth_user` | non | — | client | — |  |
| `debut` | date-heure UTC (ISO 8601) | oui | — | client | — |  |
| `fin` | date-heure UTC (ISO 8601) | oui | — | client | — |  |
| `salle` | texte (100) | oui | — | client | — |  |
| `jury` | texte (100) | non | `` | client | — |  |
| `statut` | texte (20) | oui | `active` | client | — |  |
| `remplacee_par_id` | référence → `convocation` | non | — | client | — |  |
| `notification` | texte (20) | oui | `en_attente` | client | — |  |
| `tentatives_envoi` | entier ≥ 0 | oui | `0` | client | — |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## Indisponibilite — table `indisponibilite`

Indisponibilité hebdomadaire d'un membre de jury ou d'une salle sur une *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `type_ressource` | texte (10) | oui | — | client | — |  |
| `ressource` | texte (255) | oui | — | client | Nom du membre de jury ou de la salle. |  |
| `jour_semaine` | entier ≥ 0 | oui | — | client | — |  |
| `heure_debut` | heure (fuseau de la règle) | oui | — | client | — |  |
| `heure_fin` | heure (fuseau de la règle) | oui | — | client | — | heure_fin > heure_debut (CHECK) |
| `fuseau` | texte (64) | oui | — | client | — |  |
| `valide_du` | date (AAAA-MM-JJ) | oui | — | client | — |  |
| `valide_au` | date (AAAA-MM-JJ) | oui | — | client | — | valide_au ≥ valide_du (CHECK) |
| `motif` | texte (255) | non | `` | client | — |  |
| `cree_par_id` | référence → `auth_user` | non | — | client | — |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

## ExceptionIndisponibilite — table `indisponibilite_exception`

Date où une indisponibilité récurrente ne s'applique pas. *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `regle_id` | référence → `indisponibilite` | oui | — | client | — |  |
| `date` | date (AAAA-MM-JJ) | oui | — | client | — |  |

## CleIdempotence — table `cle_idempotence`

Résultat mémorisé d'une opération logique identifiée par l'en-tête *Gestion : migrations Django.*

| Champ | Type / format | Obligatoire | Défaut | Source | Description | Règle de contrôle |
|---|---|---|---|---|---|---|
| `id` | entier (clé primaire) | non | — | serveur | Clé primaire |  |
| `cle` | texte (100) | oui | — | client | — | Unique avec perimetre |
| `perimetre` | texte (150) | oui | — | client | Périmètre : opération + compte (une clé n'a de sens que pour eux). |  |
| `empreinte` | texte (64) | oui | — | serveur | Empreinte SHA-256 du contenu de la demande. |  |
| `code_http` | entier ≥ 0 | oui | — | client | — |  |
| `reponse` | JSON | oui | — | client | — |  |
| `created_at` | date-heure UTC (ISO 8601) | non | date du serveur | serveur | — |  |

