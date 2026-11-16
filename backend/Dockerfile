
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libpq-dev \
    gcc && \
    rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Le runner de tests charge le schéma historique depuis ce fichier racine.
COPY backend/ .
COPY database/schema.sql /database/schema.sql

# Le mode développement est limité à la collecte des fichiers statiques lors
# du build ; le conteneur lancé reçoit ensuite ses propres réglages sécurisés.
RUN mkdir -p /app/media /app/staticfiles && \
    DJANGO_DEBUG=True python manage.py collectstatic --noinput && \
    addgroup --system app && \
    adduser --system --ingroup app --home /app app && \
    chown -R app:app /app

USER app

EXPOSE 8000

# Render fournit PORT ; Compose utilise 8000 par défaut. Les migrations sont
# idempotentes et s'exécutent avant Gunicorn au démarrage du service.
CMD ["sh", "-c", "python manage.py migrate --noinput && exec gunicorn config.wsgi:application --bind 0.0.0.0:${PORT:-8000} --workers 2 --access-logfile - --error-logfile -"]

