"""
Validation des fichiers déposés dans les dossiers de stage.

Seuls les PDF authentiques de moins de 10 Mo sont acceptés. L'extension
seule n'étant pas fiable, la signature binaire du fichier (« magic number »
`%PDF-`) est aussi contrôlée.
"""

from pathlib import Path

from django.core.exceptions import ValidationError

# Taille maximale d'un document déposé : 10 Mo.
MAX_DOCUMENT_SIZE = 10 * 1024 * 1024

# Taille minimale : un PDF valide contient au moins sa signature de 5 octets.
MIN_DOCUMENT_SIZE = 5

# Signature binaire qui ouvre tout fichier PDF.
SIGNATURE_PDF = b"%PDF-"


def validate_pdf_file(uploaded_file):
    """
    Vérifie qu'un fichier déposé est un véritable PDF de taille acceptable.

    Paramètres :
        uploaded_file (UploadedFile | None) : fichier reçu par Django.

    Retour :
        Le même `uploaded_file`, repositionné au début (prêt à être stocké).

    Lève :
        ValidationError : fichier absent, trop gros, vide, d'extension
        incorrecte ou dont le contenu n'est pas un PDF.
    """
    if uploaded_file is None:
        raise ValidationError("Aucun fichier n'a été fourni.")

    # Vérification de la taille (avant toute lecture du contenu).
    if uploaded_file.size > MAX_DOCUMENT_SIZE:
        raise ValidationError(
            "Le fichier ne doit pas dépasser 10 Mo."
        )

    if uploaded_file.size < MIN_DOCUMENT_SIZE:
        raise ValidationError("Le fichier est vide ou invalide.")

    # Vérification de l'extension (insensible à la casse).
    extension = Path(uploaded_file.name).suffix.lower()

    if extension != ".pdf":
        raise ValidationError(
            "Seuls les fichiers PDF sont autorisés."
        )

    # Vérification de la signature réelle : on lit les 5 premiers octets
    # puis on rembobine pour ne pas tronquer le fichier lors du stockage.
    uploaded_file.seek(0)
    signature = uploaded_file.read(len(SIGNATURE_PDF))
    uploaded_file.seek(0)

    if signature != SIGNATURE_PDF:
        raise ValidationError(
            "Le fichier fourni n'est pas un véritable document PDF."
        )

    return uploaded_file
