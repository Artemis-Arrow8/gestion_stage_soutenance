# Contrat de l'API SGSUS

API REST Django REST Framework, montée sous `/api/`. Toutes les réponses sont en JSON (UTF-8). Ce contrat est vérifié par les tests du dossier `backend/tests/`.

## 1. Conventions

| Sujet | Règle |
|---|---|
| Authentification | JWT : `POST /api/login/` renvoie `access` (5 min par défaut) et `refresh` (rotation, liste noire). En-tête `Authorization: Bearer <access>`. |
| Dates | ISO 8601, stockées en **UTC**. Un créneau est un intervalle `[début, fin)` (`slot_start`, `slot_end`). Affichage dans le fuseau métier (`Africa/Bamako`). |
| Notes | Décimal exact, texte à 2 décimales (`"15.20"`), bornes 0 à 20. |
| Identifiant de requête | Chaque réponse porte `X-Request-ID` (repris de la requête s'il est valide, sinon généré). Il figure dans les journaux du serveur et dans les erreurs 409. |
| Limitation | `POST /api/login/` : 10 tentatives par minute et par adresse (réglage `SGSUS_LIMITE_CONNEXION`), puis 429. |

## 2. Codes de réponse

| Code | Sens | Corps |
|---|---|---|
| 200 / 201 / 204 | Succès (201 pour une création, 204 pour une suppression) | Ressource ou rapport |
| 400 | Donnée mal formée ou invalide (format, bornes, champ manquant) | Format DRF par champ : `{"champ": ["message"]}` |
| 401 | Jeton absent ou expiré | `{"detail": "…"}` |
| 403 | Action interdite pour le rôle | `{"detail": "…"}` ou `{"error": "…"}` |
| 404 | Objet inexistant **ou hors du périmètre** de l'appelant : son existence n'est pas révélée | `{"detail": "…"}` |
| 409 | **Conflit métier** : demande bien formée, refusée par une règle dans l'état actuel | Enveloppe ci-dessous |
| 429 | Trop de tentatives de connexion | `{"detail": "…"}` |

Enveloppe d'un conflit métier (409) :

```json
{"code": "BUSINESS_CONFLICT", "regle": "EXG01",
 "message": "Conflit d'horaire (EXG01) : la salle « Salle 101 » est déjà réservée…",
 "request_id": "2f12800b28a6471d",
 "details": {"champ": "room_name", "soutenance": 12}}
```

`regle` relie le refus au cahier des charges :

| Valeur de `regle` | Cas |
|---|---|
| `EXG01` | Conflit de planning |
| `F01` | Doublon de dossier |
| `F02` | Rapport manquant |
| `F03` | Dossier non recevable |
| `F04` | Jury incomplet ou indisponibilité |
| `F05` | Publication |
| `F06` | Quorum |
| `STA05` | Avis sur une version périmée |
| `STA06` | Note approuvée |
| `STA07` | Soutenance publiée |
| `STA10` | Note manquante |
| `STA11` | Étape sautée |
| `STA12` | Rectification d'une note non approuvée |
| `IDEMPOTENCE` | Clé d'idempotence réutilisée |
| `HISTORIQUE` | Suppression d'une donnée validée |

## 3. Idempotence

Les opérations sensibles acceptent l'en-tête `Idempotency-Key: <clé>`. La clé désigne une **opération logique** et non une tentative réseau.

Opérations concernées :

- publication du planning ;
- report d'une soutenance ;
- approbation et rectification d'une note ;
- import d'étudiants.

Comportement :

| Cas | Résultat |
|---|---|
| Même clé, même contenu | La réponse mémorisée est rejouée (en-tête `Idempotent-Replayed: true`), sans second effet. |
| Même clé, contenu différent | 409 `IDEMPOTENCE`. |
| Pas de clé | L'opération s'exécute normalement. |

Le périmètre (opération et compte), l'empreinte SHA-256 de la demande et la réponse sont enregistrés dans la même transaction que l'opération.

## 4. Routes

Rôles : **A** administrateur, **R** responsable, **E** encadreur, **J** jury, **S** étudiant. Le périmètre est toujours filtré par le serveur (un étudiant ne voit que son dossier, un encadreur ses dossiers affectés, un juré ses soutenances).

### Session

| Méthode et route | Rôles | Effet |
|---|---|---|
| `POST /api/login/` | public | Jetons et profil (401 identifiants, 403 sans rôle, 429 limitation) |
| `POST /api/token/refresh/` | public | Nouveau jeton d'accès (rotation) |
| `POST /api/logout/` | tous | Révoque le jeton de renouvellement |
| `GET /api/profile/` | tous | Profil, dossier et soutenance de l'étudiant |
| `POST /api/profile/password/` | tous | Change son mot de passe |

### Campagnes, étudiants, dossiers (F01, F02, F03)

| Méthode et route | Rôles | Effet |
|---|---|---|
| `GET/POST/PATCH /api/campaigns/` | A R | Campagnes |
| `GET/POST /api/students/` | A R | Fiches étudiantes |
| `POST /api/students/importer/` | A R | Import CSV `{campagne, csv` ou fichier `fichier, simulation}` → rapport `{etudiants_crees, etudiants_existants, dossiers_crees, dossiers_existants, erreurs[]}` |
| `GET/POST/PATCH /api/internship-folders/` | A R S (E en lecture) | Dossiers ; `status` en **lecture seule** ; un seul dossier par étudiant et par campagne (409 F01) |
| `POST /api/internship-folders/{id}/soumettre/` | S | brouillon ou à corriger → soumis (exige un rapport) |
| `POST /api/internship-folders/{id}/autoriser/` | A R | validé → recevable (exige l'avis favorable sur la dernière version) |
| `POST /api/internship-folders/{id}/refuser/` | A R | `{motif}` → rejeté |
| `POST /api/internship-folders/{id}/rouvrir/` | A R | `{motif}` → soumis (aucune soutenance active) |
| `GET /api/internship-folders/{id}/historique/` | périmètre | Étapes, acteur, motif, version |
| `GET/PUT /api/internship-folders/{id}/confidentialite/` | lecture : périmètre ; écriture : A R | `{niveau, origine, embargo_jusqu_au, diffusion_autorisee}` |
| `GET/POST/DELETE /api/habilitations/` | A R | Habilitations nominatives ; DELETE **révoque** |
| `POST /api/documents/upload/` | A R S | Dépôt PDF (10 Mo, signature vérifiée) ; validé ou recevable → soumis |
| `GET /api/documents/download/{id}/` | selon la règle de confidentialité | Fichier ; chaque accès est journalisé |
| `GET /api/document-versions/` | périmètre | Versions |
| `GET/POST /api/reviews/` | E (A R) | Avis pédagogique sur la **dernière** version d'un dossier soumis : favorable → validé, défavorable → à corriger. Pas de modification ni de suppression. |

### Jurys, salles, indisponibilités (F04)

| Méthode et route | Rôles | Effet |
|---|---|---|
| `GET/POST/PATCH /api/jurys/` | A R (J en lecture) | `is_complete` exige au moins 3 membres dont un président et un rapporteur |
| `GET/POST/PATCH/DELETE /api/jury-members/` | A R | Une personne une seule fois par jury ; un retrait peut rendre le jury incomplet |
| `GET/POST/PATCH/DELETE /api/salles/` | A R | Salles ; `GET /api/salles/{id}/disponibilites/?date=` |
| `GET/POST/PATCH/DELETE /api/indisponibilites/` | A R | Règle hebdomadaire `{type_ressource, ressource, jour_semaine, heure_debut, heure_fin, fuseau, valide_du, valide_au, exceptions[]}` ; la création renvoie `alertes[]` (soutenances publiées concernées, jamais déplacées) |

### Soutenances et planning (F05, EXG01)

| Méthode et route | Rôles | Effet |
|---|---|---|
| `GET /api/soutenances/` et `/planning/?date=` ou `?date_debut=&date_fin=&salle=&statut=&jury=` | A R J | Planning filtré, avec `version_publiee` |
| `POST /api/soutenances/` | A R | Proposition `{folder, jury, room_name, slot_start, slot_end}` ; 409 si conflit (EXG01), dossier non recevable (F03) ou indisponibilité (F04) |
| `PATCH /api/soutenances/{id}/` | A R | Seulement si proposée ou confirmée (sinon 409 STA07) ; repasse à « proposée » |
| `POST /api/soutenances/{id}/confirmer/` | A R | Exige un dossier recevable et un jury complet |
| `POST /api/soutenances/publier/` | A R | `{commentaire}` → nouvelle `VersionPlanning` et convocations ; tout ou rien |
| `POST /api/soutenances/{id}/reporter/` | A R | `{slot_start, slot_end, room_name?, motif}` → nouvelle version, anciennes convocations « remplacées » |
| `POST /api/soutenances/{id}/annuler/` | A R | Libère salle et jury ; convocations annulées |
| `POST /api/soutenances/{id}/tenue/` | A R | publiée → tenue |
| `DELETE /api/soutenances/{id}/` | A R | Seulement si non publiée (sinon 409 HISTORIQUE : annuler) |
| `GET /api/versions-planning/` | tous | Versions publiées |
| `GET /api/convocations/?soutenance=` | tous (les siennes ; A R toutes) | Convocations avec `version`, `statut`, `remplacee_par_version`, `notification` |

### Notes et procès-verbaux (F06)

| Méthode et route | Rôles | Effet |
|---|---|---|
| `GET/POST/PATCH/DELETE /api/assessments/` | A R ; J pour son jury | `final_average` et `is_approved` en lecture seule ; moyenne serveur (`grille`) ; modification d'une note approuvée → 409 STA06 |
| `POST /api/assessments/{id}/approuver/` | A R, président du jury | Notes complètes (409 STA10) et jury complet (409 F06) → procès-verbal v1 |
| `POST /api/assessments/{id}/rectifier/` | A R | `{report_grade, oral_grade, motif}` → procès-verbal v n+1, l'ancien devient « remplacé » |
| `GET /api/assessments/{id}/proces-verbaux/` | périmètre | Toutes les versions du procès-verbal |

### Exploitation (hors `/api/`)

| Route | Effet |
|---|---|
| `GET /health/live` | Le processus répond (aucun accès à la base) |
| `GET /health/ready` (alias `/health/`) | Prêt, base comprise (200 ou 503) |
| `/admin/` | Administration Django ; traces validées en lecture seule |
