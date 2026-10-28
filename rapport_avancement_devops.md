# Rapport d’avancement DevOps
## Projet : Gestion des stages et des soutenances universitaires

**Réalisé par : Mariam Diarra**  
**Dépôt GitHub :** `Artemis-Arrow8/gestion_stage_soutenance`  
**Branche :** `main`  
**Date de mise à jour :** 28 octobre 2026

---

## 1. Objectif de ma mission

Dans le cadre du projet *Gestion des stages et des soutenances universitaires*, je suis chargée de la partie **DevOps**. Mon objectif est de préparer l’environnement technique, d’automatiser les vérifications et de préparer le déploiement de l’application complète sur Internet.

Les travaux réalisés jusqu’à présent concernent Docker, GitHub Actions, PostgreSQL et les sauvegardes. Le déploiement public et la configuration HTTPS restent à réaliser.

## 2. Travaux réalisés

### 2.1. Conteneurisation avec Docker

J’ai préparé les fichiers nécessaires pour exécuter le backend Django et PostgreSQL dans des conteneurs :

- `backend/Dockerfile` : décrit la construction de l’image du backend Django.
- `docker-compose.yml` : définit les services du backend et de PostgreSQL.
- Le volume Docker nommé `postgres_data` permet de conserver les données PostgreSQL lorsque le conteneur est redémarré.
- Un contrôle de santé (`healthcheck`) vérifie que PostgreSQL est prêt.
- J’ai lancé les conteneurs localement et vérifié leur état.

**Résultat :** les services backend et PostgreSQL démarrent dans l’environnement local.

### 2.2. Configuration Django et protection des fichiers sensibles

J’ai modifié `backend/config/settings.py` pour lire la configuration depuis les variables d’environnement, notamment la clé secrète Django, le mode debug, les hôtes autorisés et les paramètres de connexion à PostgreSQL.

J’ai également créé :
- `.gitignore`, pour exclure notamment `.env`, les fichiers temporaires Python et certains fichiers générés par Flutter ;
- `.dockerignore`, pour exclure certains fichiers qui ne doivent pas être copiés dans l’image Docker.

Le fichier `.env` local n’a pas été inclus dans le commit réalisé pendant cette étape.

**À faire avant la production :** utiliser des secrets robustes, définir `DJANGO_DEBUG=False`, configurer les hôtes autorisés et vérifier la gestion des secrets.

### 2.3. Intégration continue avec GitHub Actions

J’ai créé le workflow `.github/workflows/ci.yml`. Il se déclenche lors d’un `push` sur `main`, d’une pull request vers `main` ou manuellement.

Le workflow :
1. récupère le code du dépôt ;
2. installe Python 3.13 ;
3. installe les dépendances du backend ;
4. exécute `python manage.py check` ;
5. construit l’image Docker du backend.

J’ai créé le commit `5cd4209` avec le message `Configurer Docker et le pipeline CI GitHub Actions`, puis envoyé les changements sur GitHub.

**Résultat :** l’exécution du workflow GitHub Actions a affiché un statut vert.

**Limite actuelle :** le workflow vérifie le projet et construit une image Docker, mais il ne déploie pas encore automatiquement l’application sur un serveur distant.

### 2.4. Initialisation de PostgreSQL

J’ai vérifié que PostgreSQL fonctionnait dans Docker. Au départ, la base était accessible, mais elle ne contenait aucune table applicative.

Après avoir examiné `database/schema.sql`, j’ai exécuté le schéma dans la base de développement. PostgreSQL a créé les neuf tables suivantes :

- `campaign`
- `student`
- `internship_folder`
- `document_version`
- `review`
- `jury`
- `jury_member`
- `defense`
- `assessment`

Le schéma contient aussi des contraintes destinées à empêcher deux soutenances d’utiliser la même salle ou le même jury pendant des créneaux qui se chevauchent.

### 2.5. Sauvegarde et test de restauration

J’ai créé le script PowerShell `scripts/backup.ps1`. Ce script vérifie que PostgreSQL est disponible, crée une sauvegarde SQL horodatée dans `backups/` et signale une erreur si la sauvegarde échoue.

J’ai exécuté le script avec succès. Après la création des tables, j’ai vérifié que la sauvegarde contenait des instructions `CREATE TABLE` correspondant aux tables de la base.

J’ai également lancé un test de restauration dans une base temporaire nommée `gestion_stages_test`, afin de ne pas remplacer la base principale.

**Améliorations à prévoir :** automatiser les sauvegardes, définir une politique de conservation et conserver une copie sur un stockage distant distinct du serveur de production.

## 3. Fichiers concernés

| Fichier ou dossier | Rôle |
|---|---|
| `backend/Dockerfile` | Construction de l’image Docker du backend |
| `docker-compose.yml` | Démarrage des services Django et PostgreSQL |
| `backend/config/settings.py` | Configuration Django à partir des variables d’environnement |
| `backend/requirements.txt` | Dépendances Python du backend |
| `.gitignore` | Exclusion des secrets et fichiers temporaires de Git |
| `.dockerignore` | Exclusion de fichiers inutiles de l’image Docker |
| `.github/workflows/ci.yml` | Pipeline d’intégration continue |
| `database/schema.sql` | Création des tables et contraintes SQL |
| `scripts/backup.ps1` | Sauvegarde SQL de PostgreSQL |
| `backups/` | Dossier local contenant les sauvegardes générées |

**Sécurité :** les sauvegardes peuvent contenir des données confidentielles et ne doivent pas être publiées dans le dépôt GitHub. Le fichier `.env` ne doit pas non plus être commité. Je dois vérifier que le dossier `backups/` est exclu du suivi Git avant de partager des sauvegardes ou de pousser d’autres changements.

## 4. Point technique à résoudre

Les modèles de `backend/api/models.py` ne correspondent pas entièrement aux tables et aux colonnes de `database/schema.sql`. Par exemple, le modèle Django `Campaign` utilise le nom de table `campaigns`, alors que le schéma SQL crée `campaign`. D’autres noms de champs et certaines relations diffèrent également.

Le démarrage des conteneurs et la réussite de `manage.py check` ne suffisent donc pas à confirmer que toutes les requêtes de l’application fonctionneront avec PostgreSQL.

**Action restante :** harmoniser les modèles Django et le schéma SQL, puis exécuter des tests fonctionnels avant la mise en production. Il faudra aussi vérifier que les contraintes de planification sont conservées.

## 5. État d’avancement

| Élément | État |
|---|---|
| Docker en environnement local | Réalisé et vérifié |
| Configuration Django par variables d’environnement | Réalisée pour le développement |
| Protection des fichiers avec `.gitignore` et `.dockerignore` | Réalisée |
| Pipeline CI GitHub Actions | Publié et exécuté avec succès |
| Création des neuf tables PostgreSQL | Réalisée |
| Script local de sauvegarde PostgreSQL | Créé et testé |
| Test de restauration dans une base temporaire | Effectué |
| Harmonisation des modèles Django et du schéma SQL | À faire |
| Configuration de production sécurisée | À faire |
| Déploiement sur un VPS ou un autre hébergement | À faire |
| Nginx et HTTPS | À faire |
| Déploiement continu (CD) via GitHub Actions | À faire |
| Sauvegardes automatiques vers un stockage distant | À faire |
| Documentation d’exploitation et version `v1.0.0` | À faire |

## 6. Prochaines étapes

1. Harmoniser les modèles Django avec le schéma PostgreSQL.
2. Préparer la configuration de production : serveur d’application, variables secrètes et `DEBUG=False`.
3. Choisir et préparer un serveur VPS.
4. Déployer l’application complète avec Docker.
5. Configurer Nginx et HTTPS.
6. Mettre en place le déploiement continu avec GitHub Actions.
7. Automatiser les sauvegardes et tester régulièrement la restauration.
8. Compléter la documentation d’exploitation et préparer la version `v1.0.0`.

## 7. Conclusion

J’ai mis en place une première base DevOps pour le projet : conteneurisation locale, intégration continue sur GitHub, initialisation de PostgreSQL et script de sauvegarde avec test de restauration.

Le pipeline CI est passé au vert et les services fonctionnent en local. Le projet n’est toutefois **pas encore déployé en production**. L’alignement entre les modèles Django et le schéma SQL, la sécurisation de la configuration de production, l’hébergement, HTTPS et le déploiement continu restent à accomplir.

Ce rapport permet à l’équipe de connaître l’avancement de ma partie et les tâches qui restent à réaliser.
