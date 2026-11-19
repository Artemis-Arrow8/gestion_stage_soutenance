# ADR 0003 : Stratégie d'hébergement et de livraison

**Date :** 19 novembre 2026 — **Statut :** accepté (à confirmer par l'enseignant)
**Exigences liées :** chapitres 14 (serveur), 16 à 19 (CI/CD, livraison, retour arrière) du dossier ALM

## 1. Contexte

Le dossier propose un serveur Linux dédié ou une VM : 2 vCPU, 4 Go, accès SSH par clé, reverse proxy, déploiement par `scripts/deploy.sh` en SSH, et `install-release` sur le serveur.

L'équipe ne dispose pas d'une machine Linux exposée sur Internet. Elle doit pourtant montrer l'application en ligne pendant la démonstration, puis disposer d'une version qui fonctionne sans Internet le jour de la soutenance.

## 2. Options étudiées

| Option | Avantages | Inconvénients |
|---|---|---|
| **A. VM Linux auto-administrée** (exemple du dossier) | Contrôle total (flock, sauvegardes, Compose, reverse proxy) ; correspond mot pour mot aux chapitres 14 et 19 | Pas de machine disponible ; coût et temps d'administration (SSH, mises à jour, certificats) ; risque d'exposition mal sécurisée |
| **B. PaaS Render** : Web Service Docker, PostgreSQL géré, site statique | HTTPS et certificats fournis ; construction depuis le même Dockerfile ; sondes de santé ; retour arrière en un clic ; offre gratuite ou peu coûteuse | Le serveur reconstruit l'image depuis le commit (pas l'archive de la CI) ; base gratuite limitée dans le temps ; mise en veille de l'offre gratuite ; disque éphémère pour les fichiers déposés |

## 3. Décision

**Option B (Render)**, complétée de trois dispositifs.

1. **Déploiement d'un SHA précis.** Le job `deploy` de la CI (`scripts/deploy.sh`) :
   - demande à Render de déployer le commit **exact** testé par la CI ;
   - attend l'état `live` ;
   - n'annonce le succès qu'après les contrôles `/health/ready` et une lecture de l'API.

   Le déploiement automatique de Render doit alors être désactivé (Settings → Auto-Deploy : Off). Il ne s'active que si la configuration GitHub est faite : variables de dépôt `RENDER_SERVICE_ID` et `URL_API`, et secret `RENDER_API_KEY` dans l'environnement `render`.
2. **Traçabilité de l'artefact.** La CI construit l'image `sgsus-api:<SHA>` et conserve `image.tar.gz` avec son empreinte SHA-256 (artefact de 30 jours). Render reconstruit depuis le même commit et le même Dockerfile, dont l'image de base est verrouillée par digest et les dépendances par version exacte. L'écart avec « promouvoir la même archive » est donc limité et documenté.
3. **Version PC hors ligne** (`scripts/demarrer-pc.ps1`, profil Compose `pc`). C'est une solution de secours pour la soutenance et une démonstration de l'installation reproductible.

## 4. Conséquences

- **Retour arrière :** bouton « Rollback » de Render sur le déploiement précédent, ou `scripts/deploy.sh <ancien SHA>`. Un retour d'image **ne défait pas une migration** : les migrations du projet sont additives (0012, 0013) et l'ancienne version reste compatible avec le schéma enrichi. Sinon, il faut restaurer la sauvegarde (voir le guide d'exploitation).
- **Migrations :** appliquées au démarrage du conteneur (`entrypoint.sh`). Une sauvegarde manuelle est recommandée avant chaque déploiement qui touche le schéma.
- **Limites acceptées :**
  - fichiers déposés perdus à un redéploiement sur le disque éphémère ;
  - expiration de la base gratuite ;
  - temps de réveil de l'offre gratuite.

  Elles sont acceptables pour une démonstration, **pas pour une production réelle**.
- **Secrets :** uniquement dans Render, dans l'environnement GitHub `render`, ou dans le fichier `.env` local (exclu de Git). Une pull request ne reçoit jamais de secret de déploiement.

## 5. Condition de révision

Revenir à l'option A, ou à une autre plateforme avec disque persistant, si l'une de ces conditions est remplie :

- un établissement réel adopte l'outil, avec des données réelles ;
- la conservation des fichiers déposés devient obligatoire ;
- l'enseignant exige la livraison par archive promue et `install-release` sur un serveur.
