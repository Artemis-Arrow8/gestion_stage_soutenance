# Diagrammes de conception — SGSUS

Ce document décrit **tous les diagrammes** du projet SGSUS (gestion des stages
et des soutenances). Ils sont fidèles au code réel de l'application
(`backend/api/models.py`, `backend/api/views/`, `frontend/lib/`) et aux
exigences du cahier des charges (F01 à F06, EXG01, NFR01 à NFR05).

Pour chaque diagramme : son **objectif**, ses **éléments**, puis un **code
PlantUML** prêt à l'emploi.

> **Comment générer les images.** Copier un bloc de code PlantUML
> (de `@startuml` à `@enduml`) dans l'un de ces outils :
> - en ligne : <https://www.planttext.com> ou <https://www.plantuml.com/plantuml> ;
> - dans VS Code : extension « PlantUML » (aperçu avec `Alt+D`) ;
> - StarUML / draw.io : s'appuyer sur les descriptions pour redessiner.

## Sommaire

1. [Diagramme de cas d'utilisation](#1-diagramme-de-cas-dutilisation)
2. [Diagramme de classes](#2-diagramme-de-classes)
3. [Modèle relationnel (MLD)](#3-modèle-relationnel-mld)
4. [Diagrammes de séquence](#4-diagrammes-de-séquence)
5. [Diagrammes d'activité](#5-diagrammes-dactivité)
6. [Diagrammes d'états-transitions](#6-diagrammes-détats-transitions)
7. [Diagramme de composants (architecture logicielle)](#7-diagramme-de-composants-architecture-logicielle)
8. [Diagramme de déploiement](#8-diagramme-de-déploiement)
9. [Diagramme de paquetages](#9-diagramme-de-paquetages)

---

## 1. Diagramme de cas d'utilisation

**Objectif :** montrer *qui* fait *quoi* dans le système.

**Acteurs** (rôles réels de l'application, voir `backend/api/roles.py`) :

| Acteur | Description |
|---|---|
| Étudiant | Possède une fiche étudiante et un dossier de stage |
| Encadreur | Suit uniquement les dossiers qui lui sont affectés |
| Membre du jury | Consulte les soutenances de son jury |
| Responsable pédagogique | Gère campagnes, planning, salles, jurys, évaluations |
| Administrateur | Tous les droits du responsable + gestion des comptes |

**Généralisation :** l'*Administrateur* hérite du *Responsable pédagogique*
(il peut tout ce que fait le responsable, plus la gestion des comptes).

**Cas d'utilisation par acteur :**

- **Tous** : *S'authentifier*, *Consulter son profil*, *Changer son mot de passe*.
- **Étudiant** : *Créer / modifier son dossier de stage* (F02), *Déposer une
  version du rapport PDF* (F02), *Consulter les avis*, *Consulter sa
  soutenance et sa note validée*.
- **Encadreur** : *Consulter les dossiers affectés*, *Télécharger un rapport*,
  *Donner un avis de recevabilité* (F03).
- **Membre du jury** : *Consulter son planning de soutenances*.
- **Responsable pédagogique** : *Gérer les campagnes* (F01), *Changer le
  statut d'un dossier* (F03), *Gérer les salles* (F04), *Constituer les
  jurys* (F04), *Planifier une soutenance* (F05), *Changer le statut d'une
  soutenance*, *Consulter les conflits*, *Saisir et valider les notes* (F06).
- **Administrateur** : *Gérer les comptes et les rôles*, *Créer une fiche
  étudiant*.

**Relations :**
- *Planifier une soutenance* **«include»** *Vérifier les conflits (EXG01)* et
  *Vérifier la recevabilité du dossier (F03)*.
- *Déposer une version du rapport* **«include»** *Contrôler le fichier PDF*
  (taille ≤ 10 Mo, signature `%PDF-`).
- *Valider la note* **«extend»** *Saisir les notes*.

```plantuml
@startuml cas_utilisation
left to right direction
skinparam packageStyle rectangle
skinparam actorStyle awesome

actor "Étudiant" as ETU
actor "Encadreur" as ENC
actor "Membre du jury" as JUR
actor "Responsable\npédagogique" as RESP
actor "Administrateur" as ADM
ADM -|> RESP

rectangle "SGSUS" {
  usecase "S'authentifier" as UC_AUTH
  usecase "Consulter son profil" as UC_PROFIL
  usecase "Changer son mot de passe" as UC_MDP

  usecase "Créer / modifier\nson dossier de stage" as UC_DOSSIER
  usecase "Déposer une version\ndu rapport PDF" as UC_DEPOT
  usecase "Contrôler le fichier PDF" as UC_PDF
  usecase "Consulter les avis" as UC_AVIS_LIRE
  usecase "Consulter sa soutenance\net sa note validée" as UC_MA_SOUT

  usecase "Consulter les dossiers\naffectés" as UC_DOSS_AFF
  usecase "Télécharger un rapport" as UC_TELECH
  usecase "Donner un avis\nde recevabilité" as UC_AVIS

  usecase "Consulter son planning\nde jury" as UC_PLAN_JURY

  usecase "Gérer les campagnes" as UC_CAMP
  usecase "Changer le statut\nd'un dossier" as UC_STATUT_DOSS
  usecase "Gérer les salles" as UC_SALLES
  usecase "Constituer les jurys" as UC_JURYS
  usecase "Planifier une soutenance" as UC_PLANIF
  usecase "Vérifier les conflits\n(EXG01)" as UC_CONFLITS
  usecase "Vérifier la recevabilité\n(F03)" as UC_RECEV
  usecase "Changer le statut\nd'une soutenance" as UC_STATUT_SOUT
  usecase "Consulter les conflits" as UC_VOIR_CONFLITS
  usecase "Saisir les notes" as UC_NOTES
  usecase "Valider la note" as UC_VALIDER

  usecase "Gérer les comptes\net les rôles" as UC_COMPTES
  usecase "Créer une fiche étudiant" as UC_FICHE
}

ETU --> UC_DOSSIER
ETU --> UC_DEPOT
ETU --> UC_AVIS_LIRE
ETU --> UC_MA_SOUT
ENC --> UC_DOSS_AFF
ENC --> UC_TELECH
ENC --> UC_AVIS
JUR --> UC_PLAN_JURY
RESP --> UC_CAMP
RESP --> UC_STATUT_DOSS
RESP --> UC_SALLES
RESP --> UC_JURYS
RESP --> UC_PLANIF
RESP --> UC_STATUT_SOUT
RESP --> UC_VOIR_CONFLITS
RESP --> UC_NOTES
ADM --> UC_COMPTES
ADM --> UC_FICHE

ETU --> UC_AUTH
ENC --> UC_AUTH
JUR --> UC_AUTH
RESP --> UC_AUTH
ETU --> UC_PROFIL
ENC --> UC_PROFIL
JUR --> UC_PROFIL
RESP --> UC_PROFIL
UC_PROFIL <.. UC_MDP : <<extend>>

UC_DEPOT ..> UC_PDF : <<include>>
UC_PLANIF ..> UC_CONFLITS : <<include>>
UC_PLANIF ..> UC_RECEV : <<include>>
UC_VALIDER .> UC_NOTES : <<extend>>
@enduml
```

---

## 2. Diagramme de classes

**Objectif :** représenter les données métier et leurs relations (fichier
`backend/api/models.py`).

**Classes et attributs :**

| Classe | Attributs principaux |
|---|---|
| **User** (Django) | id, username, first_name, last_name, email, password (haché), is_active, is_staff, is_superuser |
| **Group** (Django) | id, name ∈ {admin, responsible, supervisor, student, jury} — représente le rôle |
| **Campaign** | id, academic_year : String, is_active : Boolean, created_at : DateTime |
| **Student** | id, student_number : String {unique}, full_name : String, email : String {unique} |
| **StudentAccount** | id — liaison 1:1 User ↔ Student |
| **InternshipFolder** | id, company_name : String, subject : Text, status : String, created_at : DateTime |
| **FolderSupervisor** | id — classe d'association Encadreur ↔ Dossier {unique (user, folder)} |
| **DocumentVersion** | id, version_number : Integer, file_path : String, uploaded_at : DateTime |
| **Review** | id, author_role : String, decision : String, comments : Text, created_at : DateTime |
| **Room** | id, name : String {unique}, capacity : Integer {> 0}, is_active : Boolean |
| **Jury** | id, name : String, is_complete : Boolean |
| **JuryMember** | id, member_name : String, role_in_jury ∈ {president, rapporteur, examinateur} |
| **JuryMemberAccount** | id — liaison 1:1 User ↔ JuryMember |
| **Defense** | id, room_name : String, slot_range : Intervalle[DateTime UTC], status : String |
| **Assessment** | id, report_grade : Decimal(5,2), oral_grade : Decimal(5,2), final_average : Decimal(5,2), is_approved : Boolean |

**Associations et multiplicités :**

- Campaign **1** —— **0..*** InternshipFolder
- Student **1** —— **0..*** InternshipFolder
- User **1** —— **0..1** StudentAccount **0..1** —— **1** Student
- InternshipFolder **1** —— **0..*** DocumentVersion (composition)
- DocumentVersion **1** —— **0..*** Review (composition)
- Review **0..*** —— **0..1** User (auteur)
- User (encadreur) **0..*** —— **0..*** InternshipFolder, via **FolderSupervisor**
- Jury **1** —— **0..*** JuryMember (composition)
- User **1** —— **0..1** JuryMemberAccount **0..1** —— **1** JuryMember
- InternshipFolder **1** —— **0..*** Defense
- Jury **0..1** —— **0..*** Defense
- Room **1** —— **0..*** Defense (lien logique par `room_name`)
- Defense **1** —— **0..1** Assessment (une seule évaluation par soutenance, règle de l'API)
- User **0..*** —— **0..*** Group (rôle)

**Contraintes à noter sur le diagramme :**
- {EXG01} une salle et un jury ne peuvent avoir deux soutenances dont les créneaux se chevauchent ;
- {0 ≤ note ≤ 20} sur les trois notes d'Assessment ;
- {un dossier n'est planifiable que s'il est « recevable » ou a un avis favorable} (F03).

```plantuml
@startuml classes
hide circle
skinparam classAttributeIconSize 0

class User <<Django>> {
  id : Integer
  username : String {unique}
  first_name : String
  last_name : String
  email : String
  password : String (haché)
  is_active : Boolean
  is_superuser : Boolean
}
class Group <<Django>> {
  id : Integer
  name : String (admin, responsible, supervisor, student, jury)
}
class Campaign {
  id : Integer
  academic_year : String
  is_active : Boolean
  created_at : DateTime
}
class Student {
  id : Integer
  student_number : String {unique}
  full_name : String
  email : String {unique}
}
class StudentAccount
class InternshipFolder {
  id : Integer
  company_name : String
  subject : Text
  status : String
  created_at : DateTime
}
class FolderSupervisor
class DocumentVersion {
  id : Integer
  version_number : Integer
  file_path : String
  uploaded_at : DateTime
}
class Review {
  id : Integer
  author_role : String
  decision : String
  comments : Text
  created_at : DateTime
}
class Room {
  id : Integer
  name : String {unique}
  capacity : Integer {> 0}
  is_active : Boolean
}
class Jury {
  id : Integer
  name : String
  is_complete : Boolean
}
class JuryMember {
  id : Integer
  member_name : String
  role_in_jury : String
}
class JuryMemberAccount
class Defense {
  id : Integer
  room_name : String
  slot_range : Intervalle[DateTime UTC]
  status : String
}
class Assessment {
  id : Integer
  report_grade : Decimal(5,2)
  oral_grade : Decimal(5,2)
  final_average : Decimal(5,2)
  is_approved : Boolean
}

User "0..*" -- "0..*" Group : rôle >
User "1" -- "0..1" StudentAccount
StudentAccount "0..1" -- "1" Student
Campaign "1" -- "0..*" InternshipFolder
Student "1" -- "0..*" InternshipFolder
InternshipFolder "1" *-- "0..*" DocumentVersion
DocumentVersion "1" *-- "0..*" Review
Review "0..*" -- "0..1" User : auteur >
(User, InternshipFolder) .. FolderSupervisor
Jury "1" *-- "0..*" JuryMember
User "1" -- "0..1" JuryMemberAccount
JuryMemberAccount "0..1" -- "1" JuryMember
InternshipFolder "1" -- "0..*" Defense
Jury "0..1" -- "0..*" Defense
Room "1" -- "0..*" Defense : par room_name >
Defense "1" -- "0..1" Assessment

note bottom of Defense
  {EXG01} pas de chevauchement de
  créneau pour une même salle
  ni pour un même jury
end note
note right of Assessment
  {0 ≤ note ≤ 20}
  final_average = (rapport + oral) / 2
end note
@enduml
```

---

### 2.2 Classes ajoutées pour le socle du dossier ALM

```plantuml
@startuml classes_socle
class InternshipFolder
class DocumentVersion
class Defense
class Assessment
class Campaign
class "User (compte)" as User
class HistoriqueDossier {
  evenement
  statut_avant / statut_apres
  motif
  created_at
}
class ConfidentialiteDossier {
  niveau : standard | confidentiel
  origine
  embargo_jusqu_au
  diffusion_autorisee
}
class HabilitationDossier {
  valide_du / valide_au
  revoquee
}
class JournalAccesDocument {
  version_document_id
  autorise
  motif
}
class GrilleEvaluation {
  version
  poids_rapport (0,400)
  poids_oral (0,600)
  note_maximale (20)
}
class ProcesVerbal {
  version
  note_rapport / note_oral / moyenne
  membres_jury (copie)
  statut : approuve | remplace
  motif
}
class VersionPlanning {
  numero
  publiee_le
}
class Convocation {
  destinataire / role
  debut / fin / salle (copie)
  statut : active | remplacee | annulee
  notification
}
class Indisponibilite {
  type_ressource / ressource
  jour_semaine / heures
  fuseau / période
}
class ExceptionIndisponibilite {
  date
}
class CleIdempotence {
  cle / perimetre
  empreinte SHA-256
  reponse
}
InternshipFolder "1" -- "0..*" HistoriqueDossier
HistoriqueDossier "0..*" --> "0..1" DocumentVersion : version examinée
InternshipFolder "1" -- "0..1" ConfidentialiteDossier
InternshipFolder "1" -- "0..*" HabilitationDossier
HabilitationDossier "0..*" --> "1" User : bénéficiaire
Campaign "1" -- "1..*" GrilleEvaluation
Assessment "1" -- "0..*" ProcesVerbal
ProcesVerbal "0..*" --> "1" GrilleEvaluation : version figée
VersionPlanning "1" -- "1..*" Convocation
Defense "1" -- "0..*" Convocation
Convocation "0..1" --> "0..1" Convocation : remplacee_par
Indisponibilite "1" -- "0..*" ExceptionIndisponibilite
@enduml
```

## 3. Modèle relationnel (MLD)

**Objectif :** traduire le diagramme de classes en tables PostgreSQL
(clés primaires soulignées, clés étrangères précédées de #).

```
campaign (id, academic_year, is_active, created_at)
student (id, student_number UNIQUE, full_name, email UNIQUE)
student_account (id, #user_id UNIQUE, #student_id UNIQUE)
internship_folder (id, #student_id, #campaign_id, company_name, subject, status, created_at)
folder_supervisor (id, #user_id, #folder_id)  UNIQUE(user_id, folder_id)
document_version (id, #folder_id, version_number, file_path, uploaded_at)
review (id, #document_version_id, #author_id, author_role, decision, comments, created_at)
room (id, name UNIQUE, capacity CHECK > 0, is_active)
jury (id, name, is_complete)
jury_member (id, #jury_id, member_name, role_in_jury)
jury_member_account (id, #user_id UNIQUE, #jury_member_id UNIQUE)
defense (id, #folder_id, #jury_id, room_name, slot_range TSTZRANGE, status)
    EXCLUDE (room_name WITH =, slot_range WITH &&)   -- EXG01 salle
    EXCLUDE (jury_id   WITH =, slot_range WITH &&)   -- EXG01 jury
assessment (id, #defense_id, report_grade, oral_grade, final_average, is_approved)
    CHECK 0 ≤ notes ≤ 20
auth_user, auth_group, auth_user_groups  -- tables Django des comptes et rôles
```

```plantuml
@startuml mld
hide circle
skinparam linetype ortho

entity campaign {
  * id : serial <<PK>>
  --
  academic_year : varchar
  is_active : boolean
  created_at : timestamptz
}
entity student {
  * id : serial <<PK>>
  --
  student_number : varchar <<UNIQUE>>
  full_name : varchar
  email : varchar <<UNIQUE>>
}
entity auth_user {
  * id : serial <<PK>>
  --
  username : varchar <<UNIQUE>>
  password : varchar
  is_active : boolean
}
entity student_account {
  * id : bigserial <<PK>>
  --
  user_id : int <<FK, UNIQUE>>
  student_id : int <<FK, UNIQUE>>
}
entity internship_folder {
  * id : serial <<PK>>
  --
  student_id : int <<FK>>
  campaign_id : int <<FK>>
  company_name : varchar
  subject : text
  status : varchar
}
entity folder_supervisor {
  * id : bigserial <<PK>>
  --
  user_id : int <<FK>>
  folder_id : int <<FK>>
}
entity document_version {
  * id : serial <<PK>>
  --
  folder_id : int <<FK>>
  version_number : int
  file_path : varchar
}
entity review {
  * id : serial <<PK>>
  --
  document_version_id : int <<FK>>
  author_id : int <<FK>>
  decision : varchar
  comments : text
}
entity room {
  * id : serial <<PK>>
  --
  name : varchar <<UNIQUE>>
  capacity : int
  is_active : boolean
}
entity jury {
  * id : serial <<PK>>
  --
  name : varchar
  is_complete : boolean
}
entity jury_member {
  * id : serial <<PK>>
  --
  jury_id : int <<FK>>
  member_name : varchar
  role_in_jury : varchar
}
entity jury_member_account {
  * id : bigserial <<PK>>
  --
  user_id : int <<FK, UNIQUE>>
  jury_member_id : int <<FK, UNIQUE>>
}
entity defense {
  * id : serial <<PK>>
  --
  folder_id : int <<FK>>
  jury_id : int <<FK>>
  room_name : varchar
  slot_range : tstzrange
  status : varchar
}
entity assessment {
  * id : serial <<PK>>
  --
  defense_id : int <<FK>>
  report_grade : numeric(5,2)
  oral_grade : numeric(5,2)
  final_average : numeric(5,2)
  is_approved : boolean
}

auth_user ||--o| student_account
student ||--o| student_account
campaign ||--o{ internship_folder
student ||--o{ internship_folder
internship_folder ||--o{ folder_supervisor
auth_user ||--o{ folder_supervisor
internship_folder ||--o{ document_version
document_version ||--o{ review
auth_user |o--o{ review
jury ||--o{ jury_member
jury_member ||--o| jury_member_account
auth_user ||--o| jury_member_account
internship_folder ||--o{ defense
jury |o--o{ defense
defense ||--o| assessment
room ||..o{ defense : room_name
@enduml
```

---

## 4. Diagrammes de séquence

### 4.1 Authentification (connexion JWT et renouvellement)

**Objectif :** montrer la connexion puis le renouvellement automatique du
jeton quand il expire (NFR02, NFR03).

**Participants :** Utilisateur, Application Flutter (`LoginScreen`,
`AuthProvider`, `ApiService`), API Django (`LoginView`, `TokenRefreshView`),
Base PostgreSQL.

**Scénario :**
1. L'utilisateur saisit identifiant et mot de passe.
2. Flutter envoie `POST /api/login/`.
3. Django vérifie le mot de passe (haché) et le rôle.
   - **alt** identifiants faux → `401` « Identifiant ou mot de passe incorrect » ;
   - **alt** aucun rôle → `403` ;
   - **sinon** → `200` avec `access`, `refresh` et le profil.
4. Flutter stocke les jetons (stockage sécurisé) et affiche le tableau de bord.
5. Plus tard, une requête reçoit `401` (jeton expiré) : `ApiService` appelle
   `POST /api/token/refresh/`, enregistre le nouveau jeton et **rejoue** la
   requête une seule fois.

```plantuml
@startuml sequence_authentification
autonumber
actor Utilisateur
participant "LoginScreen" as UI
participant "AuthProvider" as AP
participant "ApiService" as API
participant "API Django" as DJ
database PostgreSQL as DB

Utilisateur -> UI : saisit identifiant + mot de passe
UI -> AP : login(identifiant, mot de passe)
AP -> API : POST /api/login/
API -> DJ : requête HTTPS (JSON)
DJ -> DB : lecture du compte et de ses rôles
DB --> DJ : compte
alt identifiants incorrects
  DJ --> API : 401 { error }
  API --> AP : ApiException
  AP --> UI : message d'erreur
else compte sans rôle SGSUS
  DJ --> API : 403 { error }
  API --> AP : ApiException
  AP --> UI : message d'erreur
else succès
  DJ --> API : 200 { access, refresh, user }
  API --> AP : réponse
  AP -> AP : enregistrer les jetons\n(stockage sécurisé)
  AP --> UI : session ouverte → tableau de bord
end

== Plus tard : jeton d'accès expiré ==
AP -> API : GET /api/soutenances/planning/
API -> DJ : Authorization: Bearer <access expiré>
DJ --> API : 401
API -> AP : refreshAccessToken()
AP -> DJ : POST /api/token/refresh/ { refresh }
DJ --> AP : 200 { access, refresh }
API -> DJ : requête rejouée avec le nouveau jeton
DJ --> API : 200 { soutenances }
@enduml
```

### 4.2 Planification d'une soutenance (contrôle EXG01)

**Objectif :** montrer la double protection contre les conflits : contrôle
applicatif (message lisible) puis contrainte PostgreSQL (concurrence).

**Participants :** Responsable, `DefenseFormScreen`, `PlanningService`,
API Django (`DefenseViewSet`, `DefenseSerializer`), service `conflicts`,
PostgreSQL.

**Scénario :**
1. Le responsable choisit dossier, jury, salle, date et horaires.
2. Flutter affiche les conflits *probables* détectés localement (aide).
3. `POST /api/soutenances/` est envoyé.
4. Le sérialiseur appelle `conflicts.verifier_toutes_regles` : dossier
   recevable (F03), salle active, jury non vide, pas de chevauchement (EXG01).
   - **alt** règle violée → `400` avec un message explicite.
5. Insertion en base ; si une autre requête a réservé le même créneau entre-temps,
   la **contrainte d'exclusion** PostgreSQL rejette l'insertion → `400` « Conflit
   de réservation (EXG01) ».
6. Sinon → `201`, le planning partagé est rechargé.

```plantuml
@startuml sequence_planification
autonumber
actor Responsable
participant "DefenseFormScreen" as UI
participant "PlanningService" as PS
participant "DefenseViewSet\n+ DefenseSerializer" as V
participant "service conflicts" as C
database PostgreSQL as DB

Responsable -> UI : choisit dossier, jury, salle, créneau
UI -> UI : signaler les conflits probables (aide locale)
Responsable -> UI : Enregistrer
UI -> PS : createDefense(...)
PS -> V : POST /api/soutenances/
V -> C : verifier_toutes_regles(dossier, jury, salle, créneau)
C -> DB : dossier recevable ? salle active ?\nchevauchement salle / jury ?
DB --> C : résultats
alt une règle est violée
  C --> V : ValidationError
  V --> PS : 400 { message explicite }
  PS --> UI : afficher l'erreur
else règles respectées
  V -> DB : INSERT INTO defense
  alt conflit concurrent (contrainte d'exclusion)
    DB --> V : IntegrityError (prevent_*_double_booking)
    V --> PS : 400 « Conflit de réservation (EXG01) »
    PS --> UI : afficher l'erreur
  else insertion réussie
    DB --> V : soutenance créée
    V --> PS : 201 { soutenance }
    PS --> UI : succès
    UI -> PS : recharger le planning partagé
  end
end
@enduml
```

### 4.3 Dépôt d'un rapport PDF

**Objectif :** montrer la validation du fichier et le versionnement
transactionnel (F02, NFR03).

**Scénario :**
1. L'étudiant choisit un fichier PDF ; Flutter vérifie la taille (≤ 10 Mo).
2. `POST /api/documents/upload/` (multipart : `folder_id`, `file`).
3. Django vérifie le rôle et que le dossier appartient à l'étudiant (sinon `403`).
4. `validate_pdf_file` : taille, extension `.pdf`, signature `%PDF-` (sinon `400`).
5. Transaction : verrou du dossier (`SELECT … FOR UPDATE`), calcul du numéro
   de version suivant, enregistrement du fichier sous un nom aléatoire,
   création de la ligne `document_version` → `201`.

```plantuml
@startuml sequence_depot
autonumber
actor "Étudiant" as ETU
participant "DocumentsScreen" as UI
participant "DocumentService" as DS
participant "DocumentUploadView" as V
participant "validate_pdf_file" as VAL
participant "upload_document\n(transaction)" as S
database PostgreSQL as DB
collections "Stockage fichiers" as FS

ETU -> UI : choisit un PDF
UI -> UI : taille ≤ 10 Mo ?
UI -> DS : uploadDocument(dossier, fichier)
DS -> V : POST /api/documents/upload/ (multipart)
V -> DB : le dossier appartient-il à l'étudiant ?
alt dossier d'un autre étudiant
  V --> DS : 403
else dossier autorisé
  V -> VAL : contrôler le fichier
  alt fichier invalide (taille, extension, signature)
    VAL --> V : ValidationError
    V --> DS : 400 { file: [message] }
  else fichier valide
    V -> S : upload_document(dossier, fichier)
    S -> DB : SELECT ... FOR UPDATE (verrou du dossier)
    S -> DB : dernière version ?
    S -> FS : enregistrer documents/folder_X/<uuid>.pdf
    S -> DB : INSERT document_version (n + 1)
    S --> V : version créée
    V --> DS : 201 { version }
    DS --> UI : « Document envoyé »
  end
end
@enduml
```

### 4.4 Évaluation d'une soutenance

**Objectif :** montrer la saisie des notes, le calcul de la moyenne en
Decimal (F06, NFR04) et la consultation de la note validée par l'étudiant.

```plantuml
@startuml sequence_evaluation
autonumber
actor Responsable
actor "Étudiant" as ETU
participant "EvaluationsScreen" as UI
participant "API Django\n(AssessmentViewSet)" as V
database PostgreSQL as DB
participant "ProfileScreen" as PR

Responsable -> UI : saisit note rapport + note oral
UI -> UI : afficher la moyenne en direct
Responsable -> UI : coche « Valider la note » puis Enregistrer
UI -> V : POST /api/assessments/ { defense, notes, is_approved }
V -> V : une seule évaluation par soutenance ?\nmoyenne = (rapport + oral) / 2 (Decimal)
alt soutenance déjà évaluée
  V --> UI : 400 « déjà une évaluation »
else création
  V -> DB : INSERT assessment
  V --> UI : 201 { évaluation }
end

== Plus tard ==
ETU -> PR : ouvre « Mon profil »
PR -> V : GET /api/profile/
V -> DB : soutenance du dossier + évaluation validée ?
V --> PR : { defense: { ..., final_average } }
PR --> ETU : affiche la note finale validée
@enduml
```

---

### 4.5 Publication du planning (F05, EXG01, idempotence)

```plantuml
@startuml sequence_publication
actor "Planificateur" as P
participant "Application Flutter" as UI
participant "API Django" as API
participant "Service publication" as S
database "PostgreSQL" as DB
P -> UI : Publier le planning
UI -> API : POST /api/soutenances/publier/\nIdempotency-Key: K
API -> DB : clé K déjà connue ?
alt clé connue, même contenu
  API --> UI : 201 (réponse rejouée)
else nouvelle clé
  API -> S : publier()
  S -> DB : BEGIN ; pg_advisory_xact_lock
  S -> DB : soutenances confirmées (SELECT … FOR UPDATE)
  loop chaque soutenance
    S -> S : recevable ? jury complet ?\nconflits EXG01 ? indisponibilités ?
  end
  alt au moins un problème
    S -> DB : ROLLBACK (rien n'est écrit)
    API --> UI : 409 {code, regle: F05, details.problemes}
  else tout est conforme
    S -> DB : INSERT VersionPlanning n+1
    S -> DB : INSERT convocations ; anciennes → « remplacee »
    S -> DB : soutenances → « publie » ; clé K mémorisée
    S -> DB : COMMIT
    API --> UI : 201 {numero, nombre_soutenances}
  end
end
note over S, DB : Un arrêt du serveur avant COMMIT annule\ntout : aucune publication partielle.
@enduml
```

## 5. Diagrammes d'activité

### 5.1 Parcours complet d'un stage (de la création du dossier à la note)

**Objectif :** vue d'ensemble du processus métier, avec les couloirs
(« swimlanes ») des acteurs.

```plantuml
@startuml activite_parcours
|Étudiant|
start
:Créer son dossier de stage
(entreprise, sujet) — statut « brouillon »;
:Déposer une version du rapport PDF;
|Encadreur|
:Consulter le rapport;
:Donner un avis;
if (Avis favorable ?) then (non)
  |Étudiant|
  :Corriger et déposer une nouvelle version;
  note right: retour à l'avis de l'encadreur
  detach
else (oui)
endif
|Responsable pédagogique|
:Déclarer le dossier « recevable »;
:Planifier la soutenance
(jury, salle, créneau);
if (Conflit de salle ou de jury ? (EXG01)) then (oui)
  :Choisir un autre créneau ou une autre salle;
  detach
else (non)
endif
:Confirmer la soutenance;
|Membre du jury|
:Consulter son planning;
:Participer à la soutenance;
|Responsable pédagogique|
:Marquer la soutenance « terminée »;
:Saisir les notes (rapport, oral);
:Valider la note;
|Étudiant|
:Consulter sa note finale dans son profil;
stop
@enduml
```

### 5.2 Algorithme de vérification d'une réservation (EXG01 et F03)

```plantuml
@startuml activite_conflits
start
:Recevoir dossier, jury, salle, début, fin;
if (fin > début et durée ≤ 8 h ?) then (non)
  :Refuser : créneau invalide (400);
  stop
endif
if (Dossier recevable ou avis favorable ? (F03)) then (non)
  :Refuser : dossier non recevable (400);
  stop
endif
if (Salle existante et active ?) then (non)
  :Refuser : salle indisponible (400);
  stop
endif
if (Jury existant avec au moins un membre ?) then (non)
  :Refuser : jury incomplet (400);
  stop
endif
if (Salle déjà occupée sur ce créneau ?) then (oui)
  :Refuser : conflit de salle (400);
  stop
endif
if (Un membre du jury siège déjà sur ce créneau ?) then (oui)
  :Refuser : conflit de jury (400);
  stop
endif
:Insérer la soutenance;
if (Contrainte d'exclusion PostgreSQL violée ?\n(requête concurrente)) then (oui)
  :Refuser : conflit de réservation EXG01 (400);
  stop
endif
:Soutenance créée (201);
stop
@enduml
```

---

## 6. Diagrammes d'états-transitions

### 6.1 Dossier de stage (`InternshipFolder.status`)

Le statut ne change QUE par ces événements (`backend/api/services/dossiers.py`) ; l'API refuse une
étape sautée (409 STA11) et chaque transition est enregistrée dans `HistoriqueDossier`.

| Événement | Acteur | Départ → arrivée | Précondition |
|---|---|---|---|
| soumettre | Étudiant propriétaire | brouillon, a_corriger → soumis | ≥ 1 version du rapport |
| avis pédagogique | Encadreur affecté | soumis → valide (favorable) / a_corriger (défavorable) | avis sur la dernière version |
| autoriser la soutenance | Responsable | valide → recevable | avis favorable sur la dernière version |
| refuser | Responsable | soumis, a_corriger, valide → rejete | motif |
| rouvrir | Responsable | rejete, recevable → soumis | motif, aucune soutenance active |
| nouvelle version | Étudiant (dépôt) | valide, recevable → soumis | recevabilité réexaminée (STA05) |

```plantuml
@startuml etats_dossier
[*] --> brouillon : création (étudiant)
brouillon --> soumis : soumettre [≥ 1 version]
a_corriger --> soumis : soumettre [nouvelle version]
soumis --> valide : avis favorable (encadreur)
soumis --> a_corriger : avis défavorable (encadreur)
valide --> recevable : autoriser la soutenance (responsable)
soumis --> rejete : refuser [motif]
a_corriger --> rejete : refuser [motif]
valide --> rejete : refuser [motif]
rejete --> soumis : rouvrir [motif]
recevable --> soumis : rouvrir [motif, aucune soutenance active]
valide --> soumis : nouvelle version déposée
recevable --> soumis : nouvelle version déposée
recevable : planifiable (F03)
@enduml
```

### 6.2 Soutenance (`Defense.status`)

```plantuml
@startuml etats_soutenance
[*] --> planifie : proposer (sans conflit EXG01,\ndossier recevable, disponibilités)
planifie --> confirme : confirmer [jury complet] (F04)
confirme --> planifie : modification du créneau
confirme --> publie : publier (VersionPlanning + convocations)
publie --> publie : reporter [motif]\n(nouvelle version, anciennes convocations remplacées)
publie --> termine : marquer comme tenue
planifie --> annule : annuler
confirme --> annule : annuler
publie --> annule : annuler (convocations annulées)
annule : ne réserve plus salle ni jury
termine : notes saisissables (F06)
@enduml
```

### 6.3 Résultat (`Assessment` et `ProcesVerbal`)

```plantuml
@startuml etats_resultat
[*] --> brouillon : saisie (jury ou personnel)
brouillon --> brouillon : modification des notes
brouillon --> approuve : approuver [notes complètes, jury complet]\n→ PV v1
approuve --> approuve : rectifier [responsable, motif]\n→ PV v(n+1), PV précédent « remplacé »
approuve : modification directe refusée (STA06)
@enduml
```

---

## 7. Diagramme de composants (architecture logicielle)

**Objectif :** montrer les grandes briques logicielles et leurs dépendances.

- **Client Flutter** : `screens` (écrans) → `widgets` (composants réutilisables)
  → `providers` (état : session, planning) → `services` (un par domaine) →
  `core/network/ApiService` (client HTTP unique : JWT, renouvellement, erreurs).
- **API Django REST** : `middleware` (sonde /health/, CORS, sécurité) →
  `urls` → `views` (par domaine) → `serializers` → `services` (règles métier
  `conflicts`, `sante`) → `models` (ORM).
- **PostgreSQL 17** : tables, contraintes d'exclusion EXG01, contraintes CHECK.
- **Interface fournie** par l'API : *API REST JSON + JWT* ; **interface requise**
  par Flutter : la même.

```plantuml
@startuml composants
skinparam componentStyle rectangle

package "Client Flutter (Web / mobile)" {
  [Écrans (screens)] as SCR
  [Composants UI (widgets, ui_kit)] as WID
  [État partagé (providers)\nAuthProvider, PlanningStore] as PROV
  [Services métier\nPlanning, Documents,\nAdministration, Évaluations] as SERV
  [ApiService\n(client HTTP unique)] as API
  SCR --> WID
  SCR --> PROV
  SCR --> SERV
  PROV --> API
  SERV --> API
}

interface "API REST JSON\n(JWT)" as REST

package "Backend Django" {
  [Middlewares\n(santé, CORS, sécurité)] as MW
  [Routes (urls)] as URLS
  [Vues (views)\nauth, academic,\nplanning, accounts] as VIEWS
  [Sérialiseurs] as SER
  [Services métier\nconflicts, sante] as SRV
  [Modèles (ORM)] as MOD
  [Administration Django\n(/admin/)] as ADMIN
  MW --> URLS
  URLS --> VIEWS
  VIEWS --> SER
  SER --> SRV
  VIEWS --> MOD
  SRV --> MOD
  ADMIN --> MOD
}

database "PostgreSQL 17\n(contraintes EXG01)" as DB
folder "Stockage des PDF\n(MEDIA_ROOT)" as FS

API --> REST
REST - MW
MOD --> DB
VIEWS --> FS
@enduml
```

---

## 8. Diagramme de déploiement

**Objectif :** montrer où s'exécute chaque partie en production (Render).

- **Poste utilisateur** : navigateur web (ou mobile) qui charge l'application
  Flutter.
- **Render — Static Site** `gestion-stage-soutenance-frontend` : fichiers
  Flutter Web compilés (HTML, JS, polices).
- **Render — Web Service** `gestion-stage-soutenance` : conteneur Docker
  (`backend/Dockerfile`) ; au démarrage, `entrypoint.sh` attend la base,
  applique les migrations, collecte les statiques puis lance **Gunicorn**
  (Django + WhiteNoise). Sonde de santé : `/health/`.
- **Render — PostgreSQL 17** : base de données (accès interne depuis le
  Web Service, accès externe pour pgAdmin).
- **GitHub** : dépôt du code ; **GitHub Actions** (CI) teste Flutter et Django
  et construit l'image Docker ; chaque push sur `main` déclenche le
  redéploiement automatique sur Render.
- **Protocoles** : HTTPS entre navigateur, site et API ; TLS PostgreSQL
  (sslmode=require) entre l'API et la base.

```plantuml
@startuml deploiement
node "Poste utilisateur" {
  node "Navigateur web" as NAV {
    artifact "Application Flutter Web" as APP
  }
}

cloud "Render" {
  node "Static Site\ngestion-stage-soutenance-frontend" as SS {
    artifact "build/web\n(HTML, JS, polices)" as WEB
  }
  node "Web Service (Docker)\ngestion-stage-soutenance" as WS {
    node "Conteneur python:3.13" {
      artifact "entrypoint.sh" as EP
      component "Gunicorn" as GU
      component "Django + DRF\n+ WhiteNoise" as DJ
    }
  }
  database "PostgreSQL 17" as PG
}

node "GitHub" as GH {
  artifact "Dépôt du code" as REPO
  component "GitHub Actions (CI)" as CI
}

NAV --> SS : HTTPS (chargement de l'application)
APP --> WS : HTTPS / JSON + JWT (/api/)
EP --> GU : lance après migrate\net collectstatic
GU --> DJ
DJ --> PG : TCP 5432 / TLS
REPO --> CI : à chaque push
REPO --> SS : déploiement automatique
REPO --> WS : déploiement automatique
@enduml
```

---

## 9. Diagramme de paquetages

**Objectif :** montrer l'organisation des dossiers du code et leurs
dépendances (couches).

```plantuml
@startuml paquetages
package "frontend/lib" {
  package "screens" as F_SCR
  package "widgets" as F_WID
  package "providers" as F_PROV
  package "services" as F_SERV
  package "models" as F_MOD
  package "core" {
    package "network" as F_NET
    package "theme" as F_THEME
    package "storage" as F_STO
    package "config" as F_CONF
  }
  F_SCR ..> F_WID
  F_SCR ..> F_PROV
  F_SCR ..> F_SERV
  F_WID ..> F_THEME
  F_PROV ..> F_NET
  F_PROV ..> F_STO
  F_SERV ..> F_NET
  F_SERV ..> F_MOD
  F_NET ..> F_CONF
}

package "backend" {
  package "config\n(settings, urls)" as B_CONF
  package "api" {
    package "views" as B_VIEWS
    package "serializers" as B_SER
    package "services" as B_SERV
    package "documents" as B_DOC
    package "models" as B_MOD
    package "permissions / roles" as B_PERM
  }
  B_CONF ..> B_VIEWS
  B_VIEWS ..> B_SER
  B_VIEWS ..> B_PERM
  B_VIEWS ..> B_MOD
  B_SER ..> B_SERV
  B_SERV ..> B_MOD
  B_DOC ..> B_MOD
}

F_NET ..> B_VIEWS : HTTP / JSON
@enduml
```

---

## Récapitulatif

| N° | Diagramme | Type UML | Montre |
|---|---|---|---|
| 1 | Cas d'utilisation | Comportement | Acteurs et fonctionnalités (F01–F06) |
| 2 | Classes | Structure | Données métier, relations, contraintes |
| 3 | Modèle relationnel | Données | Tables PostgreSQL, clés, contraintes EXG01 |
| 4.1 | Séquence — authentification | Interaction | Connexion JWT et renouvellement |
| 4.2 | Séquence — planification | Interaction | Double contrôle des conflits EXG01 |
| 4.3 | Séquence — dépôt PDF | Interaction | Validation et versionnement |
| 4.4 | Séquence — évaluation | Interaction | Notes, moyenne Decimal, consultation |
| 5.1 | Activité — parcours | Comportement | Processus complet du stage |
| 5.2 | Activité — vérification | Comportement | Algorithme des règles de planification |
| 6.1 | États — dossier | Comportement | Cycle de vie du dossier |
| 6.2 | États — soutenance | Comportement | Cycle de vie de la soutenance |
| 7 | Composants | Structure | Architecture logicielle Flutter / Django |
| 8 | Déploiement | Structure | Infrastructure Render et GitHub |
| 9 | Paquetages | Structure | Organisation du code en couches |
