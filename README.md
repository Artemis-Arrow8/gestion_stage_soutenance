# SGSUS

SGSUS est une application de gestion des stages et des soutenances universitaires, composée d'une API Django REST, d'une base PostgreSQL et d'un client Flutter (Web, Android, version PC hors ligne).

**Besoin.** Suivre les stages, les rapports et l'encadrement, puis organiser les soutenances : chaque dossier montre son avancement, et aucun planning publié ne peut affecter une salle ou un membre de jury à deux soutenances au même moment (règle **EXG01**). Le périmètre, les exigences (F01–F06, EXG01, NFR01–NFR05) et les hypothèses sont dans [docs/cahier-des-charges.md](docs/cahier-des-charges.md).

**Projet pédagogique** (Génie logiciel 2 — ALM, Groupe 4) : toutes les données sont fictives ; l'application n'est pas prête à recevoir des données réelles (voir les réserves du cahier des charges).

## Configuration locale

1. Créer `.env` s’il n’existe pas, puis remplacer les valeurs d’exemple, notamment le mot de passe PostgreSQL et la clé Django. Ne jamais publier `.env`. Le modèle de développement est [.env.example](./.env.example) ; pour un reverse proxy HTTPS, partir de [.env.production.example](./.env.production.example).

   ```powershell
   if (-not (Test-Path .env)) { Copy-Item .env.example .env }
   ```

   En local, garder `DJANGO_DEBUG=True`. Pour un serveur, configurer `DJANGO_DEBUG=False`, une clé aléatoire d’au moins 50 caractères, les hôtes autorisés et HTTPS.
2. Démarrer PostgreSQL et installer les dépendances backend :

   ```powershell
   cd backend
   pip install -r requirements-dev.txt
   python manage.py migrate
   python manage.py createsuperuser
   python manage.py runserver 127.0.0.1:8001
   ```

3. Dans un autre terminal, lancer Flutter :

   ```powershell
   cd frontend
   flutter pub get
   flutter run -d windows
   ```

   L'adresse API locale par défaut est `http://127.0.0.1:8001/api`. Pour utiliser Render, remplacer cette valeur au lancement avec `--dart-define=API_BASE_URL=https://NOM-DU-WEB-SERVICE.onrender.com/api`. Ne jamais mettre `DATABASE_URL` dans Flutter : cette variable est réservée à Django. Pour Flutter Web, autoriser l'origine exacte de l'application par CORS.

4. Pour publier Flutter Web sur Render, le fichier [`render.yaml`](./render.yaml) ajoute un site statique séparé. Créer/synchroniser ce Blueprint dans Render ; le build télécharge Flutter 3.47.6 et publie `frontend/build/web`. Après le premier déploiement, copier l’origine HTTPS exacte affichée pour le Static Site dans `DJANGO_CORS_ALLOWED_ORIGINS` du Web Service backend, puis redéployer le backend.

## Docker Compose

Après avoir configuré `.env`, valider et démarrer les services. Compose utilise le port PostgreSQL interne 5432 entre conteneurs, même si `DB_PORT` configure un autre port local.

```powershell
docker compose config --quiet
docker compose up --build -d
docker compose exec backend python manage.py createsuperuser
docker compose logs --tail 100 backend
```

Le conteneur backend attend PostgreSQL, applique les migrations et collecte les fichiers statiques à chaque démarrage (`backend/entrypoint.sh`), puis lance Gunicorn. `http://127.0.0.1:8001/` décrit l’API et `http://127.0.0.1:8001/health/` indique l’état du service et de la base.

Le backend utilise Gunicorn, tourne sous un compte non privilégié et se connecte à PostgreSQL avec le rôle `sgsus_app_user`, distinct du compte d'administration. Compose prépare ce rôle également sur un volume déjà initialisé. Pour une base déjà utilisée, sauvegarder et examiner l’état des migrations avant de les appliquer. Le guide de déploiement temporaire est dans [docs/guide-exploitation.md](docs/guide-exploitation.md).

Après migration, les données de présentation se créent avec `python manage.py seed_sgsus`. La commande requiert `SGSUS_DEMO_PASSWORD`, est idempotente et refuse par défaut `DJANGO_DEBUG=False`. Les identifiants de test et les consignes figurent dans [docs/guide-exploitation.md](docs/guide-exploitation.md).

## Comptes et rôles

Un administrateur crée les comptes depuis l’API de gestion des comptes. Un étudiant est associé à une fiche via `StudentAccount` ; un membre du jury est associé à une fiche via `JuryMemberAccount`. Django hache les mots de passe ; aucun mot de passe n’est stocké dans les tables métier.

Les routes d’authentification, de gestion des comptes et les permissions par rôle sont détaillées dans [docs/authentification.md](docs/authentification.md).

## Vérifications

Le **contrat de construction** commun au poste et à la CI (chapitre 15) : analyse ruff, contrôles Django (`check --deploy` compris), migrations à jour, tests PostgreSQL avec rapport JUnit et couverture, fichiers statiques.

```bash
# PostgreSQL démarré ; DB_USER doit pouvoir créer la base de test.
bash scripts/ci.sh
```

Ou, étape par étape :

```powershell
cd backend
python -m ruff check .
python manage.py check
python manage.py makemigrations --check --dry-run
python -m pytest            # tous les tests (backend/tests), sur PostgreSQL
```

Les tests de concurrence (STA03) ouvrent deux connexions réelles : ils exigent PostgreSQL, jamais SQLite. Les cas de recette du chapitre 5 sont nommés `test_sta01_…` à `test_sta12_…` (voir [docs/recette.md](docs/recette.md)).

```powershell
cd frontend
flutter analyze
flutter test
```

`database/schema.sql` contient des commandes `DROP TABLE` : ne pas l'exécuter sur une base qui contient des données. Utiliser les migrations pour gérer le schéma.

## Architecture du code

**Backend (`backend/`)**

| Dossier / fichier | Rôle |
|---|---|
| `config/settings.py` | Configuration par variables d’environnement (détection automatique de Render) |
| `config/urls.py` | Routes racines : `/` (accueil JSON), `/admin/`, `/api/` |
| `api/models.py` | Modèles métier (schéma historique PostgreSQL + tables du socle ALM) |
| `api/serializers/` | Sérialiseurs par domaine : `accounts`, `academic`, `planning`, `socle`, `fields` |
| `api/views/` | Vues par domaine : `auth`, `accounts`, `academic`, `planning`, `socle`, `system` |
| `api/services/` | Règles métier côté serveur : `conflicts` (EXG01, marge), `dossiers` (machine à états), `publication` (versions du planning, convocations), `notes` (grille, procès-verbaux), `disponibilites`, `acces_documents` (confidentialité), `import_etudiants`, `idempotence`, `jurys`, `sante` |
| `api/exceptions.py` | Conflits métier en HTTP 409 `{code, regle, message, request_id}` |
| `api/journalisation.py` | Identifiant de requête et journaux JSON (technique / métier) |
| `api/documents/` | Dépôt et téléchargement des rapports PDF |
| `api/middleware.py` | Sondes `/health/live` et `/health/ready`, avant le contrôle d’hôte et la redirection HTTPS |
| `api/management/commands/` | `seed_sgsus`, `envoyer_convocations`, `exporter_donnees`, `wait_for_db` |
| `tests/` | Tous les tests (unitaires, PostgreSQL, permissions, concurrence, parcours) |
| `entrypoint.sh` | Démarrage du conteneur : attente BD, migrations, statiques, Gunicorn |

**Frontend (`frontend/`)**

```
frontend/lib/
├── main.dart          Point d’entrée
├── app.dart           Racine : fournisseurs, thème, aiguillage de session
├── core/              Config (URL de l’API), client HTTP unique, stockage des jetons, thème, dates
├── models/            Modèles typés (soutenance, salle, jury, évaluation, comptes…)
├── services/          Accès aux routes de l’API (un service par domaine)
├── providers/         État partagé (session, planning)
├── screens/           Écrans (connexion, tableau de bord, planning, évaluations, profil…)
└── widgets/           Composants réutilisables (coque de navigation, ui_kit, cartes)
```

Un seul client HTTP (`ApiService`, fourni par `AuthProvider.api`) injecte le jeton et le renouvelle automatiquement ; les écrans n’appellent jamais `http` directement. Charte graphique **noir, blanc et or** dans `lib/core/theme/app_theme.dart`.

## Modules de l'application

| Module | Rôles | Contenu |
|---|---|---|
| Tableau de bord | tous | Carte « À la une » (prochaine soutenance ; pour l'étudiant : son dossier et sa note) et une carte par module, avec une information en direct |
| Campagnes | admin, responsable | Années académiques, campagne active |
| Comptes | admin | Comptes, rôles, liaison aux fiches étudiant / jury |
| Planning | admin, responsable, jury | Calendrier jour / semaine / mois, création, statut et suppression des soutenances |
| Salles | admin, responsable | Catalogue des salles, occupation du jour |
| Jurys | admin, responsable | Composition des jurys, membres |
| Conflits | admin, responsable | Doubles réservations de salle ou de jury |
| Évaluations | admin, responsable | Notes du rapport et de l'oral, moyenne automatique, validation |
| Documents | tous sauf jury | Dossiers de stage (création par l'étudiant, statut par le personnel), versions PDF, avis |
| Mon profil | tous | Informations personnelles, soutenance et note (étudiant), changement de mot de passe |

Sur téléphone, la navigation est en bas de l'écran (usage à une main). Le geste « retour » ferme l'écran ouvert sans quitter l'application ; sur l'accueil, il faut le refaire pour sortir. Un formulaire en cours de saisie demande confirmation avant d'être fermé (`SgFormulaire`).

## Versions hors ligne

| Version | Pour qui | Fonctionnement |
|---|---|---|
| **Mode hors ligne** (Web et Android) | tout utilisateur | Les dernières données consultées sont mémorisées sur l'appareil (`lib/core/network/hors_ligne.dart`). Sans réseau, l'application s'ouvre, affiche ces données et le bandeau « Mode hors ligne » ; les modifications attendent la connexion. Sur le Web, `web/sw_hors_ligne.js` conserve les fichiers du site. Tout est effacé à la déconnexion. |
| **Application Android** (APK) | téléphone | `.\scripts\construire-apk.ps1` produit `frontend/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, signé avec `frontend/android/key.properties` (local). Reliée à l'API Render, avec le mode hors ligne. |
| **Version PC** | démonstration sans Internet | Base, API et site sur le PC avec Docker (profil `pc`) : `.\scripts\demarrer-pc.ps1` puis `http://localhost:8080` (option `-Reseau` pour les téléphones du même Wi-Fi, `-Arreter` pour arrêter). `.\scripts\copier-render-vers-pc.ps1` copie une fois les données de Render (base locale sauvegardée avant, dans `backups/`). |

La première préparation de la version PC (images Docker, compilation Flutter) demande Internet ; ensuite, aucune connexion n'est nécessaire. Le site n'utilise plus le CDN de Google : moteur de rendu et police Roboto (sous-ensemble latin, licence Apache 2.0) sont servis par l'application elle-même.

## Documents ALM

| Document | Contenu |
|---|---|
| [docs/cadrage.md](docs/cadrage.md) | Contexte, rôles, entretien utilisateur (à compléter), comparaison, budget |
| [docs/cahier-des-charges.md](docs/cahier-des-charges.md) | Exigences vérifiables, règles métier, inventaire des données, registre des ambiguïtés |
| [docs/api.md](docs/api.md) | Contrat de l'API : codes, erreurs 409, idempotence, routes par rôle |
| [docs/matrice-droits.md](docs/matrice-droits.md) | Rôles × actions, pièces jointes et exports, avec le test de refus associé |
| [docs/dictionnaire-donnees.md](docs/dictionnaire-donnees.md) | Chaque champ : type, obligatoire, défaut, source, règle |
| [docs/modeles/](docs/modeles/) | Diagrammes (cas d'utilisation, classes, MLD, séquences, activités, états, déploiement) et leurs sources PlantUML |
| [docs/adr/](docs/adr/) | Décisions : pile technique (0001), concurrence (0002), hébergement (0003) |
| [docs/recette.md](docs/recette.md) | Cas STA01–STA13 : données, acteur, étapes, attendu, observé, version |
| [docs/tracabilite.csv](docs/tracabilite.csv) | Exigence → issue → modèle → PR → test → recette → version |
| [docs/incidents/](docs/incidents/) | Incident du chapitre 20 (juré sur deux soutenances) et retour d'expérience |
| [docs/guide-exploitation.md](docs/guide-exploitation.md) | Déploiement, sauvegarde, restauration, retour arrière, exploitation |
| [docs/authentification.md](docs/authentification.md) | Routes d'authentification et permissions |

## Limites connues

* La performance (NFR05, p95 < 2 s avec 20 utilisateurs) n'est pas encore mesurée.
* Sur Render gratuit, les fichiers déposés sont perdus à chaque redéploiement (disque éphémère) et la base gratuite expire.
* Hors ligne, l'application permet la consultation ; les modifications exigent une connexion.
* Les rôles « planificateur » et « scolarité » du dossier sont couverts par les rôles responsable et administrateur (voir le registre des ambiguïtés).
