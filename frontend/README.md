# Client Flutter SGSUS

Application Flutter (Web, Android, Windows…) de gestion des stages et des
soutenances. Elle consomme exclusivement l’API REST Django ; elle ne se
connecte jamais directement à PostgreSQL.

## Lancer l’application

```powershell
flutter pub get
# Backend local (Docker Compose publie l’API sur le port 8001)
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8001/api
# Backend Render
flutter run -d chrome --dart-define=API_BASE_URL=https://gestion-stage-soutenance.onrender.com/api
```

`API_BASE_URL` est fixée à la compilation (`--dart-define`) ; elle doit se
terminer par `/api`. En Web, l’origine de l’application doit figurer dans
`DJANGO_CORS_ALLOWED_ORIGINS` côté backend (en mode `DEBUG`, `localhost` est
autorisé automatiquement, quel que soit le port).

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

Charte graphique : **noir, blanc et or** (couleurs de l'université), définie
dans `lib/core/theme/app_theme.dart`.

## Architecture

```
lib/
├── main.dart                 Point d’entrée
├── app.dart                  Racine : fournisseurs, thème, aiguillage de session
├── core/                     Briques transverses, sans logique métier
│   ├── config/app_config.dart     URL de l’API, délais (dart-define)
│   ├── network/api_service.dart   Client HTTP unique : JWT, renouvellement, erreurs
│   ├── storage/auth_storage.dart  Stockage sécurisé des jetons
│   ├── theme/app_theme.dart       Couleurs, ombres, points de rupture, thème M3
│   └── utils/dates.dart           Formatage des dates en français
├── models/                   Modèles typés (soutenance, salle, jury, comptes…)
├── services/                 Accès aux routes de l’API (un service par domaine)
├── providers/                État partagé (session, planning)
├── screens/                  Écrans (connexion, tableau de bord, planning…)
└── widgets/                  Composants réutilisables (coque, ui_kit, cartes)
```

Principes :

* **Un seul client HTTP** (`ApiService`), fourni par `AuthProvider.api` : le
  jeton courant est injecté automatiquement et renouvelé une fois après une
  réponse 401 (les renouvellements simultanés sont mutualisés).
* **Services sans état** : ils décrivent les routes et convertissent le JSON
  en modèles ; les écrans n’utilisent jamais `http` directement.
* **Interface adaptative** : barre latérale (≥ 1100 px), rail d’icônes
  (≥ 840 px) ou menu en tiroir (mobile), via `SgPage`.
* **États unifiés** : `SgLoading`, `SgErrorState`, `SgEmpty` et `SgBanner`
  garantissent des messages de chargement et d’erreur cohérents.

## Vérifications

```powershell
flutter analyze
flutter test
```
