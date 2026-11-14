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

Après avoir configuré `.env`, valider et démarrer les services. Compose utilise le port PostgreSQL interne 5432 entre conteneurs, même si `DB_PORT` configure un autre port local.

```powershell
docker compose config --quiet
docker compose up --build -d
docker compose exec backend python manage.py migrate --noinput
docker compose exec backend python manage.py createsuperuser
docker compose logs --tail 100 backend
```

Le backend utilise Gunicorn, tourne sous un compte non privilégié et sert les fichiers statiques préparés dans l’image. Pour une base déjà utilisée, sauvegarder et examiner l’état des migrations avant de les appliquer. Le guide de déploiement temporaire est dans [docs/guide-exploitation.md](docs/guide-exploitation.md).

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
