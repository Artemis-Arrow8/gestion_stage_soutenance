#!/bin/sh
# =============================================================================
# Script de démarrage du conteneur backend SGSUS (Render et Docker Compose).
#
# Rôle : préparer l'application AVANT de lancer Gunicorn, à chaque démarrage :
#   1. attendre que PostgreSQL accepte les connexions ;
#   2. appliquer les migrations (`migrate`, idempotent) ;
#   3. collecter les fichiers statiques (`collectstatic`, idempotent) ;
#   4. remplacer ce script par Gunicorn (`exec`), qui reçoit alors les
#      signaux d'arrêt de Docker/Render et s'arrête proprement.
#
# Variables d'environnement facultatives :
#   PORT                         port d'écoute (fourni par Render ; 8000 sinon)
#   WEB_CONCURRENCY              nombre de workers Gunicorn (2 par défaut)
#   GUNICORN_TIMEOUT             délai max d'une requête en secondes (60)
#   DB_WAIT_TIMEOUT              attente max de PostgreSQL en secondes (60)
#   DJANGO_MIGRATE_ON_START      "false" pour désactiver les migrations
#   DJANGO_COLLECTSTATIC_ON_START "false" pour désactiver collectstatic
#
# Si une autre commande est passée au conteneur (ex. `sh`, `python manage.py
# shell`), elle est exécutée telle quelle, sans étape de préparation.
# =============================================================================

# -e : arrêt à la première erreur ; -u : erreur sur variable non définie.
set -eu

# --- Commande personnalisée : on l'exécute sans préparation -------------------
# Seul le lancement par défaut (aucun argument, ou « gunicorn ») déclenche les
# migrations ; cela évite qu'un conteneur utilitaire (ex. `media-init` dans
# Compose) tente de se connecter à la base.
if [ "$#" -gt 0 ] && [ "$1" != "gunicorn" ]; then
    exec "$@"
fi

echo "==> Démarrage du backend SGSUS"
# Rappel utile en cas d'erreur CORS côté navigateur : les origines autorisées
# sont publiques (ce ne sont pas des secrets) et peuvent être affichées.
echo "    Origines CORS autorisées : ${DJANGO_CORS_ALLOWED_ORIGINS:-<aucune>}"

# --- 1. Attente de la base de données -----------------------------------------
echo "==> Attente de PostgreSQL (délai max : ${DB_WAIT_TIMEOUT:-60} s)"
python manage.py wait_for_db --timeout "${DB_WAIT_TIMEOUT:-60}"

# --- 2. Migrations ---------------------------------------------------------------
if [ "${DJANGO_MIGRATE_ON_START:-true}" = "true" ]; then
    echo "==> Application des migrations"
    python manage.py migrate --noinput
else
    echo "==> Migrations ignorées (DJANGO_MIGRATE_ON_START=${DJANGO_MIGRATE_ON_START})"
fi

# --- 3. Fichiers statiques -------------------------------------------------------
# Déjà collectés lors de la construction de l'image ; cette seconde passe
# garantit la cohérence avec la configuration d'exécution (fichiers inchangés
# ignorés, donc rapide).
if [ "${DJANGO_COLLECTSTATIC_ON_START:-true}" = "true" ]; then
    echo "==> Collecte des fichiers statiques"
    python manage.py collectstatic --noinput
else
    echo "==> collectstatic ignoré (DJANGO_COLLECTSTATIC_ON_START=${DJANGO_COLLECTSTATIC_ON_START})"
fi

# --- 4. Lancement de Gunicorn ----------------------------------------------------
# Si l'appelant a fourni sa propre ligne Gunicorn (« gunicorn … »), on la
# respecte ; sinon on applique la configuration par défaut ci-dessous.
if [ "$#" -gt 1 ]; then
    echo "==> Lancement : $*"
    exec "$@"
fi

echo "==> Lancement de Gunicorn sur le port ${PORT:-8000}"
# --access-logfile - / --error-logfile - : journaux sur la sortie standard,
# collectés par Render et `docker compose logs`.
exec gunicorn config.wsgi:application \
    --bind "0.0.0.0:${PORT:-8000}" \
    --workers "${WEB_CONCURRENCY:-2}" \
    --timeout "${GUNICORN_TIMEOUT:-60}" \
    --access-logfile - \
    --error-logfile -
