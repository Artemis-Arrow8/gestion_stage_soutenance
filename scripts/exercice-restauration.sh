#!/usr/bin/env bash
# Exercice de sauvegarde / restauration sur DONNÉES FICTIVES (chapitre 20 du
# dossier ALM : « la restauration doit être réellement exercée sur les
# données fictives »). Le script mesure aussi les durées (RTO observé).
#
# Déroulé, dans deux bases ISOLÉES du conteneur PostgreSQL local :
#   1. base source neuve : migrations + jeu de démonstration `seed_demo` ;
#   2. sauvegarde au format personnalisé (pg_dump -Fc) + empreinte ;
#   3. restauration dans une seconde base (pg_restore --exit-on-error) ;
#   4. vérifications : mêmes totaux métier, contraintes d'exclusion EXG01
#      présentes ET actives, schéma à jour, connexion d'un compte ;
#   5. suppression des deux bases d'exercice.
# Aucune base existante n'est modifiée.
#
# Usage   : bash scripts/exercice-restauration.sh <dossier media temporaire>
# Prérequis : `docker compose up -d db` et le fichier .env local.
#             Sous Linux, définir PYTHON=venv/bin/python.
set -euo pipefail
# Sortie UTF-8 (la console Windows ne sait pas écrire « → » sinon).
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
cd "$(dirname "$0")/.."
set -a; . ./.env >/dev/null 2>&1; set +a

SRC=sgsus_exercice_src
DST=sgsus_exercice_restauree
MEDIA="${1:?Usage : bash scripts/exercice-restauration.sh <dossier media temporaire>}"
# Interpréteur Python du backend (venv Windows par défaut).
PY="${PYTHON:-./venv/Scripts/python.exe}"

# Requête SQL dans une base du conteneur (résultat brut, sans en-tête).
psql_c() { docker compose exec -T db sh -c "psql -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d \"$1\" -tAc \"$2\""; }
# Horodatage en secondes (pour mesurer les durées).
maintenant() { date +%s.%N; }
# Variables du backend : base locale du conteneur, JAMAIS DATABASE_URL.
backend_env() {
  export DATABASE_URL= DB_HOST=127.0.0.1 DB_PORT="${DB_PORT:-5433}" \
         DB_USER="$POSTGRES_USER" DB_PASSWORD="$POSTGRES_PASSWORD" POSTGRES_DB="$1"
}

echo "== Préparation de la base source fictive"
docker compose exec -T db sh -c "dropdb -U \"\$POSTGRES_USER\" --if-exists $SRC; dropdb -U \"\$POSTGRES_USER\" --if-exists $DST; createdb -U \"\$POSTGRES_USER\" $SRC"
(
  cd backend
  backend_env "$SRC"
  export DJANGO_MEDIA_ROOT="$MEDIA" SGSUS_DEMO_PASSWORD="Exercice-Restauration-2026"
  "$PY" manage.py migrate --noinput >/dev/null
  "$PY" manage.py seed_demo 2>/dev/null | grep -v '^{'
)

COMPTE="select (select count(*) from internship_folder)||' dossiers, '||(select count(*) from document_version)||' versions, '||(select count(*) from review)||' avis, '||(select count(*) from defense)||' soutenances, '||(select count(*) from historique_dossier)||' étapes'"

echo "== Sauvegarde (pg_dump -Fc)"
t0=$(maintenant)
docker compose exec -T db sh -c "pg_dump -Fc -U \"\$POSTGRES_USER\" -d $SRC -f /tmp/exercice.dump"
t1=$(maintenant)
docker compose exec -T db sh -c "ls -l /tmp/exercice.dump | awk '{print \"taille : \" \$5 \" octets\"}'; sha256sum /tmp/exercice.dump | cut -c1-16"

echo "== Restauration dans une base isolée (pg_restore)"
t2=$(maintenant)
docker compose exec -T db sh -c "createdb -U \"\$POSTGRES_USER\" $DST && pg_restore --exit-on-error --no-owner -U \"\$POSTGRES_USER\" -d $DST /tmp/exercice.dump"
t3=$(maintenant)

echo "== Vérifications"
echo "source    : $(psql_c $SRC "$COMPTE")"
echo "restaurée : $(psql_c $DST "$COMPTE")"
echo "contraintes d'exclusion restaurées : $(psql_c $DST "select string_agg(conname, ', ' order by conname) from pg_constraint where contype='x'")"
# La règle EXG01 doit encore être appliquée par la base restaurée : on tente
# de recopier une soutenance sur le même créneau (doit être refusé).
REFUS=$(docker compose exec -T db sh -c "psql -U \"\$POSTGRES_USER\" -d $DST -tAc \"insert into defense (folder_id, jury_id, room_name, slot_range, status) select folder_id, jury_id, room_name, slot_range, status from defense limit 1\"" 2>&1 || true)
echo "tentative de double réservation : $(echo "$REFUS" | grep -o 'violates exclusion constraint "[a-z_]*"' | head -1)"
(
  cd backend
  backend_env "$DST"
  "$PY" manage.py migrate --check >/dev/null && echo "migrations : schéma à jour (migrate --check OK)"
  "$PY" manage.py shell -c "from django.contrib.auth import get_user_model as g; u=g().objects.get(username='demo5.etu07'); print('connexion du compte demo5.etu07 :', 'OK' if u.check_password('Exercice-Restauration-2026') else 'ÉCHEC')" 2>/dev/null | grep connexion
)
t4=$(maintenant)

awk -v a="$t0" -v b="$t1" -v c="$t2" -v d="$t3" -v e="$t4" 'BEGIN {
  printf "durée sauvegarde : %.1f s ; durée restauration : %.1f s ; restauration + vérifications : %.1f s\n", b-a, d-c, e-c }'

echo "== Nettoyage"
docker compose exec -T db sh -c "dropdb -U \"\$POSTGRES_USER\" $SRC; dropdb -U \"\$POSTGRES_USER\" $DST; rm -f /tmp/exercice.dump"
echo "bases d'exercice supprimées"
