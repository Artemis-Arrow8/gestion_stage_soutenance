#!/usr/bin/env bash
# =============================================================================
# Déploiement contrôlé d'un commit précis de l'API SGSUS sur Render
# (chapitres 18 et 19 du dossier, adaptés à l'hébergeur retenu : ADR 0003).
#
# Usage : bash scripts/deploy.sh <SHA du commit testé par la CI>
#
# Variables (secrets de l'environnement GitHub « render », jamais en clair) :
#   RENDER_API_KEY    : clé d'API Render du compte ;
#   RENDER_SERVICE_ID : identifiant du Web Service (srv-…) ;
#   URL_API           : adresse publique, ex. https://gestion-stage-soutenance.onrender.com
#
# Étapes :
#   1. valide le SHA reçu (40 caractères hexadécimaux) ;
#   2. demande à Render de déployer CE commit (et pas « le dernier ») ;
#   3. attend l'état « live » (échec explicite sinon) ; au démarrage, le
#      conteneur applique les migrations et collecte les statiques ;
#   4. contrôle /health/ready (base comprise) puis une lecture de l'API ;
#      le succès n'est annoncé qu'après ces contrôles.
#
# Retour arrière : depuis le tableau de bord Render (« Rollback » sur le
# déploiement précédent) ou en relançant ce script avec l'ancien SHA. Un
# retour d'image ne défait pas une migration : voir docs/guide-exploitation.md.
# =============================================================================
set -euo pipefail

sha="${1:?commit requis}"
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "SHA invalide : $sha" >&2; exit 2; }
: "${RENDER_API_KEY:?RENDER_API_KEY manquant}" "${RENDER_SERVICE_ID:?RENDER_SERVICE_ID manquant}"
: "${URL_API:?URL_API manquante}"

api="https://api.render.com/v1/services/${RENDER_SERVICE_ID}"
entetes=(-H "Authorization: Bearer ${RENDER_API_KEY}" -H "Accept: application/json")

# Lit un champ d'une réponse JSON (python est présent sur les exécuteurs CI).
champ() { python3 -c "import json, sys; print(json.load(sys.stdin)[\"$1\"])"; }

echo "== Déploiement du commit ${sha}"
deploiement=$(curl -fsS -X POST "${api}/deploys" "${entetes[@]}" \
  -H "Content-Type: application/json" -d "{\"commitId\": \"${sha}\"}" | champ id)
echo "Déploiement Render ${deploiement} demandé."

statut="inconnu"
for _ in $(seq 1 60); do          # 60 × 20 s = 20 minutes au plus
  statut=$(curl -fsS "${api}/deploys/${deploiement}" "${entetes[@]}" | champ status)
  case "$statut" in
    live) break ;;
    build_failed|update_failed|pre_deploy_failed|canceled|deactivated)
      echo "Échec du déploiement : ${statut}. Journaux : tableau de bord Render." >&2
      exit 1 ;;
  esac
  sleep 20
done
[[ "$statut" == "live" ]] || { echo "Délai dépassé (statut : ${statut})." >&2; exit 1; }

echo "== Contrôles après déploiement"
curl -fsS "${URL_API}/health/ready" | grep -q '"database": "ok"' \
  || { echo "La sonde /health/ready ne confirme pas la base." >&2; exit 1; }
# Lecture de l'API sans jeton : 401 prouve que Django répond et protège la route.
code=$(curl -s -o /dev/null -w '%{http_code}' "${URL_API}/api/soutenances/")
[[ "$code" == "401" ]] || { echo "Réponse inattendue de l'API : ${code}." >&2; exit 1; }

echo "Déploiement vérifié : le commit ${sha} est en ligne."
