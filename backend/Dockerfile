# =============================================================================
# Image Docker du backend Django SGSUS (Render et Docker Compose).
#
# Contexte de construction : RACINE du dépôt (et non `backend/`), car l'image
# embarque aussi `database/schema.sql` utilisé par le banc de tests.
#   docker build -f backend/Dockerfile -t sgsus-backend .
#
# Au démarrage, `entrypoint.sh` attend PostgreSQL, applique les migrations,
# collecte les fichiers statiques puis lance Gunicorn sur $PORT.
# =============================================================================

FROM python:3.13-slim

# PYTHONDONTWRITEBYTECODE : pas de fichiers .pyc dans l'image.
# PYTHONUNBUFFERED : journaux Python affichés immédiatement (Render/Docker).
# PIP_* : installation plus rapide et image plus légère.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dépendances Python installées AVANT de copier le code : cette couche reste
# en cache tant que requirements.txt ne change pas (builds plus rapides).
# psycopg2-binary embarque libpq : aucun paquet système n'est nécessaire.
COPY backend/requirements.txt .
RUN pip install -r requirements.txt

# Code de l'application, puis schéma SQL historique lu par le runner de tests.
COPY backend/ .
COPY database/schema.sql /database/schema.sql

# Préparation de l'image :
#   * suppression d'éventuels retours chariot Windows (CRLF) dans le script
#     de démarrage, qui empêcheraient son exécution sous Linux ;
#   * première collecte des fichiers statiques (DEBUG=True n'est utilisé que
#     pour cette commande : il évite d'exiger les secrets de production au
#     moment du build) ;
#   * création d'un utilisateur système non privilégié propriétaire de /app.
RUN sed -i 's/\r$//' /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh && \
    mkdir -p /app/media /app/staticfiles && \
    DJANGO_DEBUG=True python manage.py collectstatic --noinput && \
    addgroup --system app && \
    adduser --system --ingroup app --home /app app && \
    chown -R app:app /app

# Le serveur ne tourne jamais en root.
USER app

# Port par défaut (Render fournit sa propre valeur via $PORT).
EXPOSE 8000

# Sonde utilisée par Docker/Compose : la route /health/ vérifie aussi la base.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health/' % os.environ.get('PORT', '8000'), timeout=4)" || exit 1

# Préparation (attente BD, migrations, statiques) puis Gunicorn.
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["gunicorn"]
