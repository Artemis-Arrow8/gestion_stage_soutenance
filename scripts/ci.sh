#!/usr/bin/env bash
# =============================================================================
# Contrat de construction commun du backend SGSUS (chapitre 15 du dossier).
#
# Les MÊMES commandes tournent sur un poste de développement et dans la CI
# GitHub (.github/workflows/ci.yml) : un échec local annonce un échec en CI.
#
# Prérequis : un PostgreSQL 17 joignable avec les variables DB_HOST, DB_PORT,
# POSTGRES_DB, DB_USER et DB_PASSWORD (compte autorisé à créer la base de
# test), et DJANGO_SECRET_KEY (valeur fictive en test).
#
# Étapes (le script s'arrête à la première erreur) :
#   1. dépendances verrouillées (sauf SGSUS_SANS_INSTALLATION=1) ;
#   2. analyse statique (ruff) ;
#   3. contrôles Django, dont `check --deploy` avec une configuration de
#      production fictive (échec sur tout avertissement non justifié) ;
#   4. aucune migration manquante ;
#   5. tests sur PostgreSQL avec rapport JUnit (report.xml) et couverture ;
#      un fichier de test non collecté fait échouer pytest (aucun test = échec) ;
#   6. collecte des fichiers statiques (comme au déploiement).
# =============================================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../backend"

if [[ "${SGSUS_SANS_INSTALLATION:-0}" != "1" ]]; then
  python -m pip install -r requirements-dev.txt
fi

echo "== 1. Analyse statique (ruff)"
python -m ruff check .

echo "== 2. Contrôles Django"
python manage.py check
# Configuration de production FICTIVE : seuls les contrôles de sécurité de
# déploiement sont évalués, aucune connexion n'est ouverte.
DJANGO_DEBUG=False \
DJANGO_SECRET_KEY="ci-cle-fictive-de-verification-du-deploiement-0123456789abcdef" \
DJANGO_ALLOWED_HOSTS=api.example.org \
DB_USER=sgsus_app_user DB_PASSWORD="mot-de-passe-fictif-de-32-caracteres-minimum" \
DJANGO_SECURE_SSL_REDIRECT=True DJANGO_SECURE_COOKIES=True \
DJANGO_SECURE_HSTS_SECONDS=31536000 DJANGO_BEHIND_HTTPS_PROXY=True \
  python manage.py check --deploy --fail-level WARNING

echo "== 3. Migrations à jour"
python manage.py makemigrations --check --dry-run

echo "== 4. Tests (PostgreSQL) avec rapport JUnit et couverture"
python -m coverage run -m pytest --junitxml=report.xml -q
python -m coverage report

echo "== 5. Fichiers statiques"
python manage.py collectstatic --noinput > /dev/null

echo "Contrat de construction respecté."
