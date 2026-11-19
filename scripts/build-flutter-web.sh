#!/usr/bin/env bash
set -euo pipefail

# La compilation Flutter doit intégrer l'URL publique du backend dans l'application.
: "${API_BASE_URL:?Définir API_BASE_URL avec une adresse HTTPS Django terminée par /api}"
if [[ "$API_BASE_URL" != https://* || "$API_BASE_URL" != */api ]]; then
  echo "Erreur : API_BASE_URL doit commencer par https:// et se terminer par /api." >&2
  exit 1
fi

# La version épinglée garde le SDK de compilation cohérent avec le projet local.
FLUTTER_VERSION="3.47.6"
FLUTTER_HOME="$HOME/flutter-$FLUTTER_VERSION"
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Render ne fournit pas le SDK Flutter : cloner uniquement la version épinglée.
if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
FLUTTER_COMMAND="$FLUTTER_HOME/bin/flutter"

# Préparer les outils Web, récupérer les dépendances puis produire le site statique.
"$FLUTTER_COMMAND" config --no-analytics --enable-web
"$FLUTTER_COMMAND" precache --web
cd "$REPOSITORY_ROOT/frontend"
"$FLUTTER_COMMAND" pub get
# --no-web-resources-cdn : le moteur de rendu (CanvasKit) est servi par le
# site lui-même et non par le CDN de Google, pour pouvoir être conservé par
# le service worker (sw_hors_ligne.js) et ouvrir le site hors ligne.
"$FLUTTER_COMMAND" build web --release --no-web-resources-cdn   --dart-define="API_BASE_URL=$API_BASE_URL"
