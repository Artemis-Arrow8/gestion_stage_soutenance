from pathlib import Path

from django.core.exceptions import ValidationError


MAX_DOCUMENT_SIZE = 10 * 1024 * 1024  # 10 Mo


def validate_pdf_file(uploaded_file):
    """
    Vérifie qu'un fichier déposé est un véritable PDF
    et respecte la limite de taille.
    """

    if uploaded_file is None:
        raise ValidationError("Aucun fichier n'a été fourni.")

    # Vérification de la taille
    if uploaded_file.size > MAX_DOCUMENT_SIZE:
        raise ValidationError(
            "Le fichier ne doit pas dépasser 10 Mo."
        )

    if uploaded_file.size < 5:
        raise ValidationError("Le fichier est vide ou invalide.")

    # Vérification de l'extension
    extension = Path(uploaded_file.name).suffix.lower()

    if extension != ".pdf":
        raise ValidationError(
            "Seuls les fichiers PDF sont autorisés."
        )

    # Vérification de la signature réelle du PDF
    uploaded_file.seek(0)
    signature = uploaded_file.read(5)
    uploaded_file.seek(0)

    if signature != b"%PDF-":
        raise ValidationError(
            "Le fichier fourni n'est pas un véritable document PDF."
        )

    return uploaded_file