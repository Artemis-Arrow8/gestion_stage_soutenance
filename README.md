# SGSUS

SGSUS est une application de gestion des stages et des soutenances universitaires, composée d'une API Django REST, d'une base PostgreSQL et d'un client Flutter.

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

```powershell
cd backend
python manage.py check
python manage.py test
python manage.py makemigrations --check --dry-run
```

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
| `api/models.py` | Modèles métier (schéma historique PostgreSQL) |
| `api/serializers/` | Sérialiseurs par domaine : `accounts`, `academic`, `planning`, `fields` |
| `api/views/` | Vues par domaine : `auth`, `accounts`, `academic`, `planning`, `system` |
| `api/services/` | Logique métier : `conflicts` (règles EXG01), `sante` (sonde `/health/`) |
| `api/documents/` | Dépôt et téléchargement des rapports PDF |
| `api/middleware.py` | Sonde de santé traitée avant le contrôle d’hôte et la redirection HTTPS |
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
| Tableau de bord | tous | Indicateurs, prochaines soutenances, charge de la semaine ; pour l'étudiant : son dossier et sa soutenance |
| Campagnes | admin, responsable | Années académiques, campagne active |
| Comptes | admin | Comptes, rôles, liaison aux fiches étudiant / jury |
| Planning | admin, responsable, jury | Calendrier jour / semaine / mois, création, statut et suppression des soutenances |
| Salles | admin, responsable | Catalogue des salles, occupation du jour |
| Jurys | admin, responsable | Composition des jurys, membres |
| Conflits | admin, responsable | Doubles réservations de salle ou de jury |
| Évaluations | admin, responsable | Notes du rapport et de l'oral, moyenne automatique, validation |
| Documents | tous sauf jury | Dossiers de stage (création par l'étudiant, statut par le personnel), versions PDF, avis |
| Mon profil | tous | Informations personnelles, soutenance et note (étudiant), changement de mot de passe |
