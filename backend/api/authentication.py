from rest_framework_simplejwt.authentication import JWTAuthentication


class CustomUserAuthentication(JWTAuthentication):
    """Conserve l'ancien point d'entrée tout en validant les JWT."""
