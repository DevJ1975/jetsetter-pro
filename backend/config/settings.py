"""JetSetter Pro API settings.

Everything deployment-specific comes from environment variables so the same
image runs locally, in tests and on Railway. See backend/README.md for the full
list.
"""
import os
import sys
from decimal import Decimal
from pathlib import Path

import dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent


def env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.environ.get(name, default).split(",") if item.strip()]


DEBUG = env_bool("DJANGO_DEBUG", False)
TESTING = env_bool("DJANGO_TESTING", False) or sys.argv[1:2] == ["test"]

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if not SECRET_KEY:
    if DEBUG or TESTING:
        SECRET_KEY = "insecure-dev-key-not-for-production"
    else:
        raise RuntimeError("DJANGO_SECRET_KEY must be set (openssl rand -hex 32).")

# Railway injects RAILWAY_PUBLIC_DOMAIN for the generated *.up.railway.app host;
# add custom domains through DJANGO_ALLOWED_HOSTS.
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS")
_railway_domain = os.environ.get("RAILWAY_PUBLIC_DOMAIN")
if _railway_domain:
    ALLOWED_HOSTS.append(_railway_domain)
# Railway's deploy health check sends this Host header.
ALLOWED_HOSTS.append("healthcheck.railway.app")
if DEBUG or TESTING:
    ALLOWED_HOSTS += ["localhost", "127.0.0.1", "testserver"]

# The public origin used in links we hand back to the app (Stripe return URLs).
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")
if not PUBLIC_BASE_URL and _railway_domain:
    PUBLIC_BASE_URL = f"https://{_railway_domain}"

CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")
if PUBLIC_BASE_URL.startswith("https://"):
    CSRF_TRUSTED_ORIGINS.append(PUBLIC_BASE_URL)

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework.authtoken",
    "accounts",
    "bookings",
    "handoff",
    "legal",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
                "legal.context.site",
            ],
        },
    },
]

DATABASES = {
    "default": dj_database_url.config(
        default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}",
        conn_max_age=600,
        conn_health_checks=True,
    )
}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = False
USE_TZ = True
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": (
            "django.contrib.staticfiles.storage.StaticFilesStorage"
            if (DEBUG or TESTING)
            else "whitenoise.storage.CompressedManifestStaticFilesStorage"
        )
    },
}

# ── Security (Railway terminates TLS in front of gunicorn) ───────────────────
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
if not (DEBUG or TESTING):
    SECURE_SSL_REDIRECT = env_bool("DJANGO_SSL_REDIRECT", True)
    SECURE_REDIRECT_EXEMPT = [r"^health/$"]  # the platform probes over plain HTTP
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = 31536000
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"

# ── REST framework ───────────────────────────────────────────────────────────
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["rest_framework.authentication.TokenAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    "EXCEPTION_HANDLER": "bookings.errors.exception_handler",
    "DEFAULT_THROTTLE_CLASSES": [],
    "DEFAULT_THROTTLE_RATES": {
        "register": os.environ.get("THROTTLE_REGISTER", "30/hour"),
        "search": os.environ.get("THROTTLE_SEARCH", "60/hour"),
        "checkout": os.environ.get("THROTTLE_CHECKOUT", "20/hour"),
        "read": os.environ.get("THROTTLE_READ", "600/hour"),
    },
}

# ── Duffel ───────────────────────────────────────────────────────────────────
DUFFEL_ACCESS_TOKEN = os.environ.get("DUFFEL_ACCESS_TOKEN", "")
DUFFEL_WEBHOOK_SECRET = os.environ.get("DUFFEL_WEBHOOK_SECRET", "")
DUFFEL_BASE_URL = os.environ.get("DUFFEL_BASE_URL", "https://api.duffel.com")
DUFFEL_API_VERSION = "v2"
DUFFEL_TIMEOUT_SECONDS = 30
DUFFEL_ORDER_TIMEOUT_SECONDS = 130  # airlines can take ~2 minutes to confirm
# Duffel test tokens start with duffel_test_ and only ever create fake bookings.
FLIGHTS_TEST_MODE = DUFFEL_ACCESS_TOKEN.startswith("duffel_test_")

# ── Stripe (customer payments) ───────────────────────────────────────────────
STRIPE_SECRET_KEY = os.environ.get("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
# Without Stripe we only allow the free "test" checkout when Duffel is in test
# mode, so a misconfigured production server can never hand out free flights.
PAYMENTS_ENABLED = bool(STRIPE_SECRET_KEY)
ALLOW_UNPAID_TEST_BOOKINGS = FLIGHTS_TEST_MODE and not PAYMENTS_ENABLED
STRIPE_CHECKOUT_MINUTES = 31  # Stripe's minimum session lifetime is 30 minutes

# ── Pricing ──────────────────────────────────────────────────────────────────
# Optional markup on top of the Duffel total. Zero by default.
SERVICE_FEE_PERCENT = Decimal(os.environ.get("SERVICE_FEE_PERCENT", "0"))
SERVICE_FEE_FIXED = Decimal(os.environ.get("SERVICE_FEE_FIXED", "0"))
MAX_SEARCH_OFFERS = 40

# ── Public site / legal ──────────────────────────────────────────────────────
APP_NAME = "JetSetter Pro"
COMPANY_NAME = os.environ.get("COMPANY_NAME", "JetSetter Pro")
SUPPORT_EMAIL = os.environ.get("SUPPORT_EMAIL", "")
APP_URL_SCHEME = "jetsetterpro"

# ── Logging ──────────────────────────────────────────────────────────────────
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(levelname)s %(name)s %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": os.environ.get("LOG_LEVEL", "INFO")},
}
