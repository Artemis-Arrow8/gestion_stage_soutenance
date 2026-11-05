# SGSUS

SGSUS est une application de gestion des stages et des soutenances universitaires, composée d'une API Django REST, d'une base PostgreSQL et d'un client Flutter.

## Configuration locale

1. Copier `.env.example` vers `.env`, puis définir un mot de passe PostgreSQL local et une clé Django privée. Ne jamais publier `.env`.
2. Démarrer PostgreSQL et installer les dépendances backend :

   ```powershell
   cd backend
   pip install -r requirements.txt
   python manage.py migrate
   python manage.py createsuperuser
   python manage.py runserver 127.0.0.1:8000
   ```

3. Dans un autre terminal, lancer Flutter :

   ```powershell
   cd frontend
   flutter pub get
   flutter run -d windows
   ```

   L'adresse API par défaut est `http://127.0.0.1:8000/api`. Elle peut être remplacée avec `--dart-define=API_BASE_URL=<URL>`. Pour Flutter Web, l'API doit autoriser l'origine locale par CORS.

## Docker Compose

Après avoir configuré `.env`, démarrer les services avec `docker compose up --build`, puis appliquer les migrations dans le conteneur backend :

```powershell
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py createsuperuser
```

Le backend utilise le service PostgreSQL `db`. Pour une base déjà utilisée, sauvegarder et examiner l'état des migrations avant de les appliquer.

## Comptes étudiants

Un administrateur crée un utilisateur dans l'administration Django puis l'associe à une fiche existante au moyen de `StudentAccount`. L'étudiant se connecte avec les identifiants fournis par l'établissement. Django hache le mot de passe ; aucun mot de passe n'est stocké dans la table `student`.

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
