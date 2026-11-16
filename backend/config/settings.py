"""
Configuration Django du projet SGSUS (API de gestion des stages et soutenances).

Toute la configuration sensible provient des variables d'environnement :
    * en local : fichier `.env` à la racine du dépôt (chargé par python-dotenv) ;
    * avec Docker Compose : bloc `environment` du service `backend` ;
    * sur Render : variables du Web Service (+ variables injectées par Render
      comme `RENDER`, `RENDER_EXTERNAL_HOSTNAME`, `PORT`).

Principe de sécurité : en production (`DJANGO_DEBUG=False`), toute
configuration dangereuse ou incomplète fait échouer le démarrage avec une
`ImproperlyConfigured` explicite, plutôt que de démarrer dans un état fragile.

Documentation de référence : https://docs.djangoproject.com/en/stable/ref/settings/
"""

from datetime import timedelta
from pathlib import Path
import os
from urllib.parse import parse_qs, unquote, urlparse

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

# Dossier `backend/` (contient manage.py). Son parent est la racine du dépôt,
# où se trouve le fichier `.env` partagé avec docker-compose.yml.
BASE_DIR = Path(__file__).resolve().parent.parent
# `load_dotenv` ne remplace jamais une variable déjà définie dans le système :
# les variables de Docker/Render restent prioritaires sur le fichier `.env`.
load_dotenv(BASE_DIR.parent / ".env")


# =========================================================================
# 1. LECTURE TYPÉE DES VARIABLES D'ENVIRONNEMENT
# =========================================================================

def _env_bool(name, default):
    """
    Lit une variable booléenne et refuse les valeurs ambiguës.

    Paramètres :
        name (str) : nom de la variable d'environnement.
        default (bool) : valeur si la variable est absente.

    Retour :
        bool : valeur interprétée.

    Lève :
        ImproperlyConfigured : valeur non reconnue (ex. « peut-être »).
    """
    valeur = os.getenv(name)
    if valeur is None:
        return default
    normalisee = valeur.strip().lower()
    if normalisee in {"1", "true", "yes", "on", "oui"}:
        return True
    if normalisee in {"0", "false", "no", "off", "non"}:
        return False
    raise ImproperlyConfigured(
        f"{name} doit valoir true/false, yes/no, on/off ou 1/0."
    )


def _env_int(name, default, minimum=1):
    """
    Lit une variable entière et vérifie sa borne minimale.

    Paramètres :
        name (str) : nom de la variable d'environnement.
        default (int) : valeur si la variable est absente.
        minimum (int) : plus petite valeur acceptée.

    Retour :
        int : valeur interprétée.

    Lève :
        ImproperlyConfigured : valeur non entière ou inférieure au minimum.
    """
    valeur = os.getenv(name)
    try:
        resultat = default if valeur is None else int(valeur)
    except ValueError as error:
        raise ImproperlyConfigured(f"{name} doit être un nombre entier.") from error
    if resultat < minimum:
        raise ImproperlyConfigured(f"{name} doit être supérieur ou égal à {minimum}.")
    return resultat


def _env_list(name, default=""):
    """
    Lit une liste de valeurs séparées par des virgules.

    Paramètres :
        name (str) : nom de la variable d'environnement.
        default (str) : chaîne utilisée si la variable est absente.

    Retour :
        list[str] : éléments non vides, débarrassés de leurs espaces.
    """
    return [
        element.strip()
        for element in os.getenv(name, default).split(",")
        if element.strip()
    ]


def _normaliser_hote(valeur):
    """
    Réduit une saisie d'hôte à son seul nom DNS (sans schéma ni chemin).

    Erreur de configuration fréquente : coller une URL complète
    (« https://app.onrender.com/ ») dans DJANGO_ALLOWED_HOSTS. On en extrait
    donc le nom d'hôte pour éviter des erreurs 400 « DisallowedHost ».

    Paramètres :
        valeur (str) : hôte ou URL saisi(e) par l'exploitant.

    Retour :
        str : nom d'hôte seul (ex. « app.onrender.com »), ou « * » inchangé.
    """
    if "://" in valeur:
        return urlparse(valeur).netloc or valeur
    return valeur.split("/", 1)[0]


def _normaliser_origine(name, valeur):
    """
    Valide et normalise une origine Web (schéma + hôte [+ port]).

    Paramètres :
        name (str) : variable d'où provient la valeur (pour le message d'erreur).
        valeur (str) : origine saisie, ex. « https://app.onrender.com/ ».

    Retour :
        str : origine normalisée sans barre oblique finale.

    Lève :
        ImproperlyConfigured : origine sans schéma HTTP(S), sans hôte ou
        contenant un chemin (une origine ne contient jamais de chemin).
    """
    analyse = urlparse(valeur.strip())
    if (
        analyse.scheme not in {"http", "https"}
        or not analyse.netloc
        or analyse.path not in {"", "/"}
        or analyse.query
        or analyse.fragment
    ):
        raise ImproperlyConfigured(
            f"{name} contient une origine invalide « {valeur} » : utiliser "
            "uniquement schéma et hôte, par exemple https://app.example.org"
        )
    return f"{analyse.scheme}://{analyse.netloc}"


# =========================================================================
# 2. MODE DE FONCTIONNEMENT ET DÉTECTION DE RENDER
# =========================================================================

# DJANGO_DEBUG est désactivé par défaut : un environnement mal configuré
# n'expose donc pas accidentellement le mode de développement.
DEBUG = _env_bool("DJANGO_DEBUG", False)

# Render injecte automatiquement `RENDER=true` dans chaque service, ainsi que
# `RENDER_EXTERNAL_HOSTNAME` (ex. gestion-stage-soutenance.onrender.com).
SUR_RENDER = _env_bool("RENDER", False)
RENDER_EXTERNAL_HOSTNAME = os.getenv("RENDER_EXTERNAL_HOSTNAME", "").strip()


# =========================================================================
# 3. CLÉ SECRÈTE
# =========================================================================

# DJANGO_SECRET_KEY doit être une clé aléatoire privée, différente par instance.
SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "").strip()
if not DEBUG and (
    len(SECRET_KEY) < 50
    or SECRET_KEY.startswith("replace-with-")
    or SECRET_KEY.startswith("dev-only-")
):
    raise ImproperlyConfigured(
        "DJANGO_SECRET_KEY doit être une clé aléatoire d'au moins 50 caractères en production."
    )
if not SECRET_KEY or SECRET_KEY.startswith("replace-with-"):
    # Cette valeur de secours n'est admise qu'en développement local ;
    # les contrôles ci-dessus interdisent son utilisation en déploiement.
    SECRET_KEY = "dev-only-key-not-for-production-use"


# =========================================================================
# 4. HÔTES AUTORISÉS
# =========================================================================

# DJANGO_ALLOWED_HOSTS : noms d'hôtes séparés par des virgules, sans schéma.
# En développement, localhost est autorisé par défaut.
ALLOWED_HOSTS = [
    _normaliser_hote(hote)
    for hote in _env_list(
        "DJANGO_ALLOWED_HOSTS",
        "localhost,127.0.0.1" if DEBUG else "",
    )
]

# Sur Render, le domaine public du service est ajouté automatiquement :
# plus besoin de le recopier à la main dans DJANGO_ALLOWED_HOSTS.
if RENDER_EXTERNAL_HOSTNAME and RENDER_EXTERNAL_HOSTNAME not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(RENDER_EXTERNAL_HOSTNAME)

if not DEBUG and not ALLOWED_HOSTS:
    raise ImproperlyConfigured(
        "DJANGO_ALLOWED_HOSTS doit contenir au moins un hôte en production."
    )
if not DEBUG and "*" in ALLOWED_HOSTS:
    raise ImproperlyConfigured(
        "DJANGO_ALLOWED_HOSTS ne peut pas contenir '*' en production."
    )


# =========================================================================
# 5. APPLICATIONS ET MIDDLEWARES
# =========================================================================

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.postgres',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # En-têtes CORS : déclarer l'application active aussi ses contrôles
    # de configuration (`manage.py check`).
    'corsheaders',
    'rest_framework',
    'rest_framework_simplejwt.token_blacklist',
    'api',
]

MIDDLEWARE = [
    # Sonde /health/ traitée en premier : ni contrôle d'hôte ni redirection
    # HTTPS ne doivent bloquer les vérifications internes de Render/Docker.
    'api.middleware.HealthCheckMiddleware',
    # CORS le plus haut possible, pour répondre aussi aux requêtes préalables
    # (OPTIONS) émises par le navigateur avant chaque appel de Flutter Web.
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    # WhiteNoise sert les fichiers statiques (admin, DRF) sans serveur Nginx.
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'


# =========================================================================
# 6. CORS ET CSRF (communication avec le frontend Flutter Web)
# =========================================================================

# Adresse publique du site Flutter Web publié sur Render (Static Site créé
# par le Blueprint `render.yaml`).
FRONTEND_RENDER_ORIGIN = "https://gestion-stage-soutenance-frontend.onrender.com"

# DJANGO_CORS_ALLOWED_ORIGINS : origines exactes du frontend, séparées par des
# virgules. Si la variable est absente sur Render, le site Flutter ci-dessus
# est autorisé par défaut ; une valeur définie dans le tableau de bord Render
# reste toujours prioritaire. Flutter mobile/desktop n'est pas soumis au
# CORS ; seul le Web l'est.
CORS_ALLOWED_ORIGINS = [
    _normaliser_origine("DJANGO_CORS_ALLOWED_ORIGINS", origine)
    for origine in _env_list(
        "DJANGO_CORS_ALLOWED_ORIGINS",
        FRONTEND_RENDER_ORIGIN if SUR_RENDER else "",
    )
]

# En développement, `flutter run -d chrome` utilise un port aléatoire sur
# localhost : on autorise donc tout port local, uniquement si DEBUG est actif.
CORS_ALLOWED_ORIGIN_REGEXES = [
    r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
] if DEBUG else []

# Le CORS ne concerne que l'API ; l'administration Django reste même-origine.
CORS_URLS_REGEX = r"^/api/.*$"

# Origines de confiance pour les formulaires POST protégés par CSRF (site
# d'administration servi en HTTPS derrière le proxy de Render).
CSRF_TRUSTED_ORIGINS = [
    _normaliser_origine("DJANGO_CSRF_TRUSTED_ORIGINS", origine)
    for origine in _env_list("DJANGO_CSRF_TRUSTED_ORIGINS")
]
if RENDER_EXTERNAL_HOSTNAME:
    CSRF_TRUSTED_ORIGINS.append(f"https://{RENDER_EXTERNAL_HOSTNAME}")


# =========================================================================
# 7. HTTPS ET COOKIES
# =========================================================================

# Ces paramètres protègent l'application derrière HTTPS ; HSTS reste à zéro
# tant que le domaine et ses sous-domaines ne sont pas confirmés en HTTPS.
SECURE_SSL_REDIRECT = _env_bool("DJANGO_SECURE_SSL_REDIRECT", not DEBUG)
SECURE_COOKIES = _env_bool("DJANGO_SECURE_COOKIES", not DEBUG)
SECURE_HSTS_SECONDS = _env_int("DJANGO_SECURE_HSTS_SECONDS", 0, minimum=0)
SECURE_HSTS_INCLUDE_SUBDOMAINS = _env_bool(
    "DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS", False
)
SECURE_HSTS_PRELOAD = _env_bool("DJANGO_SECURE_HSTS_PRELOAD", False)
SESSION_COOKIE_SECURE = SECURE_COOKIES
CSRF_COOKIE_SECURE = SECURE_COOKIES

if not DEBUG and not SECURE_SSL_REDIRECT:
    raise ImproperlyConfigured(
        "DJANGO_SECURE_SSL_REDIRECT doit être activé en production."
    )
if not DEBUG and not SECURE_COOKIES:
    raise ImproperlyConfigured(
        "DJANGO_SECURE_COOKIES doit être activé en production."
    )

# Derrière un proxy TLS (Render, Nginx…), Django reçoit du HTTP simple : il
# doit lire l'en-tête X-Forwarded-Proto pour savoir que le client est en HTTPS.
# Sans cela, SECURE_SSL_REDIRECT provoquerait une boucle de redirections.
# Toujours actif sur Render (son proxy écrase systématiquement cet en-tête,
# et le désactiver y provoquerait la boucle) ; ailleurs, ne l'activer que si
# le proxy maîtrisé écrase réellement l'en-tête (DJANGO_BEHIND_HTTPS_PROXY).
SECURE_PROXY_SSL_HEADER = (
    ("HTTP_X_FORWARDED_PROTO", "https")
    if SUR_RENDER or _env_bool("DJANGO_BEHIND_HTTPS_PROXY", False)
    else None
)


# =========================================================================
# 8. BASE DE DONNÉES POSTGRESQL
# =========================================================================

# Délai maximal d'ouverture d'une connexion, pour ne pas bloquer un worker.
DB_CONNECT_TIMEOUT = _env_int("DB_CONNECT_TIMEOUT", 10)

# Render fournit DATABASE_URL ; Compose conserve ses variables DB_* séparées.
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if DATABASE_URL:
    try:
        database_url = urlparse(DATABASE_URL)
        # `.port` lève ValueError si le port n'est pas numérique.
        database_port = database_url.port or 5432
    except ValueError as error:
        raise ImproperlyConfigured("DATABASE_URL est invalide.") from error

    if (
        database_url.scheme not in {"postgres", "postgresql"}
        or not database_url.hostname
        or not database_url.username
        or database_url.password is None
        or not database_url.path.strip("/")
    ):
        raise ImproperlyConfigured(
            "DATABASE_URL doit être une URL PostgreSQL complète."
        )

    # Les identifiants peuvent être encodés en pourcentage dans l'URL.
    DB_USER = unquote(database_url.username).strip()
    DB_PASSWORD = unquote(database_url.password)
    database_query = parse_qs(database_url.query)
    # TLS exigé par défaut ; `?sslmode=` dans l'URL permet de l'ajuster.
    sslmode = database_query.get("sslmode", ["require"])[-1]

    if not DEBUG and sslmode == "disable":
        raise ImproperlyConfigured(
            "DATABASE_URL doit utiliser TLS en production."
        )

    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": unquote(database_url.path.lstrip("/")),
            "USER": DB_USER,
            "PASSWORD": DB_PASSWORD,
            "HOST": database_url.hostname,
            "PORT": database_port,
            # Connexions persistantes (10 min) : évite une poignée de main TLS
            # à chaque requête, tout en vérifiant leur état avant réutilisation.
            "CONN_MAX_AGE": 600,
            "CONN_HEALTH_CHECKS": True,
            "OPTIONS": {
                "sslmode": sslmode,
                "connect_timeout": DB_CONNECT_TIMEOUT,
            },
        }
    }
else:
    # Compatibilité locale : Compose transmet un rôle applicatif dédié.
    DB_USER = os.getenv("DB_USER", "").strip()
    DB_PASSWORD = os.getenv("DB_PASSWORD", "")
    if DEBUG:
        # Compatibilité avec les installations locales historiques hors Compose.
        DB_USER = DB_USER or os.getenv("POSTGRES_USER", "gestion_user")
        DB_PASSWORD = DB_PASSWORD or os.getenv("POSTGRES_PASSWORD", "")

    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": os.getenv("POSTGRES_DB", "gestion_stage_soutenance"),
            "USER": DB_USER,
            "PASSWORD": DB_PASSWORD,
            "HOST": os.getenv("DB_HOST", "localhost"),
            "PORT": os.getenv("DB_PORT", "5432"),
            "OPTIONS": {"connect_timeout": DB_CONNECT_TIMEOUT},
        }
    }

# En production, le compte applicatif doit avoir un secret robuste…
if not DEBUG and (
    len(DATABASES["default"]["PASSWORD"]) < 32
    or DATABASES["default"]["PASSWORD"].startswith(("replace-with-", "dev-only-"))
    or not DATABASES["default"]["USER"]
):
    raise ImproperlyConfigured(
        "DB_USER doit être défini et DB_PASSWORD doit être un secret personnalisé d'au moins 32 caractères en production."
    )
# … et ne jamais être le compte administrateur PostgreSQL (moindre privilège).
if not DEBUG and (
    DATABASES["default"]["USER"] == os.getenv("DB_ADMIN_USER", "").strip()
):
    raise ImproperlyConfigured(
        "DB_USER doit être distinct du compte administrateur PostgreSQL."
    )


# =========================================================================
# 9. AUTHENTIFICATION, LANGUE ET API REST
# =========================================================================

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# Messages d'erreur Django/DRF en français, dates stockées en UTC (NFR04).
LANGUAGE_CODE = 'fr-fr'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

REST_FRAMEWORK = {
    # Toutes les routes exigent un JWT, sauf exceptions explicites (login…).
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    # En production, l'API ne répond qu'en JSON ; l'interface HTML navigable
    # de DRF reste disponible en développement pour explorer les routes.
    'DEFAULT_RENDERER_CLASSES': (
        ('rest_framework.renderers.JSONRenderer',)
        + (('rest_framework.renderers.BrowsableAPIRenderer',) if DEBUG else ())
    ),
}

SIMPLE_JWT = {
    # JWT_ACCESS_TOKEN_MINUTES limite la durée du jeton utilisé sur l'API.
    'ACCESS_TOKEN_LIFETIME': timedelta(
        minutes=_env_int("JWT_ACCESS_TOKEN_MINUTES", 5)
    ),
    # JWT_REFRESH_TOKEN_DAYS fixe la durée maximale de renouvellement.
    'REFRESH_TOKEN_LIFETIME': timedelta(
        days=_env_int("JWT_REFRESH_TOKEN_DAYS", 1)
    ),
    # La rotation réduit la durée d'utilisation d'un jeton de renouvellement volé.
    'ROTATE_REFRESH_TOKENS': _env_bool("JWT_ROTATE_REFRESH_TOKENS", True),
    # La liste noire invalide l'ancien jeton dès qu'il a été renouvelé.
    'BLACKLIST_AFTER_ROTATION': _env_bool(
        "JWT_BLACKLIST_AFTER_ROTATION", True
    ),
}


# =========================================================================
# 10. TESTS
# =========================================================================

# Exécuteur personnalisé : charge le schéma SQL historique et ses contraintes
# dans la base de test après les migrations.
TEST_RUNNER = 'config.test_runner.SchemaTestRunner'


# =========================================================================
# 11. FICHIERS STATIQUES ET MÉDIAS
# =========================================================================

# Fichiers statiques (admin Django, DRF) collectés par `collectstatic` dans
# STATIC_ROOT puis servis par WhiteNoise, compressés et versionnés.
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# Documents déposés par les utilisateurs. Sur Render gratuit, ce dossier est
# éphémère : prévoir un disque persistant ou un stockage objet pour la prod.
MEDIA_URL = '/media/'
MEDIA_ROOT = Path(
    os.getenv('DJANGO_MEDIA_ROOT', '').strip() or str(BASE_DIR / 'media')
)

STORAGES = {
    'default': {
        'BACKEND': 'django.core.files.storage.FileSystemStorage',
    },
    'staticfiles': {
        # Nom de fichier haché (cache long côté navigateur) + gzip/brotli.
        'BACKEND': 'whitenoise.storage.CompressedManifestStaticFilesStorage',
    },
}


# =========================================================================
# 12. E-MAILS
# =========================================================================

EMAIL_BACKEND = os.getenv(
    'DJANGO_EMAIL_BACKEND',
    'django.core.mail.backends.console.EmailBackend',
)
EMAIL_HOST = os.getenv('DJANGO_EMAIL_HOST', '').strip()
EMAIL_PORT = _env_int('DJANGO_EMAIL_PORT', 587)
EMAIL_HOST_USER = os.getenv('DJANGO_EMAIL_HOST_USER', '').strip()
EMAIL_HOST_PASSWORD = os.getenv('DJANGO_EMAIL_HOST_PASSWORD', '')
EMAIL_USE_TLS = _env_bool('DJANGO_EMAIL_USE_TLS', True)
EMAIL_USE_SSL = _env_bool('DJANGO_EMAIL_USE_SSL', False)
DEFAULT_FROM_EMAIL = os.getenv(
    'DJANGO_DEFAULT_FROM_EMAIL',
    'noreply@localhost',
).strip()

if EMAIL_USE_TLS and EMAIL_USE_SSL:
    raise ImproperlyConfigured(
        "DJANGO_EMAIL_USE_TLS et DJANGO_EMAIL_USE_SSL ne peuvent pas être activés ensemble."
    )
if (
    not DEBUG
    and EMAIL_BACKEND == 'django.core.mail.backends.smtp.EmailBackend'
    and not EMAIL_HOST
):
    raise ImproperlyConfigured(
        "DJANGO_EMAIL_HOST est obligatoire lorsque le relais SMTP est activé en production."
    )


# =========================================================================
# 13. JOURNALISATION
# =========================================================================

# Tous les journaux partent sur la sortie standard, que Render et Docker
# collectent. Sans cette configuration, les erreurs 500 de production
# (DEBUG=False) n'apparaîtraient pas dans les journaux du service.
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'simple': {
            'format': '[{asctime}] {levelname} {name} : {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'simple',
        },
    },
    'root': {
        'handlers': ['console'],
        # DJANGO_LOG_LEVEL : DEBUG, INFO, WARNING, ERROR (INFO par défaut).
        'level': os.getenv('DJANGO_LOG_LEVEL', 'INFO').strip().upper() or 'INFO',
    },
    'loggers': {
        # Journaux du framework sur la console unique (sans doublon via root).
        'django': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        # Seules les erreurs serveur (5xx) sont tracées : les 4xx attendues
        # (jeton expiré, validation) ne doivent pas noyer les journaux.
        'django.request': {
            'handlers': ['console'],
            'level': 'ERROR',
            'propagate': False,
        },
    },
}
