import uuid
from pathlib import Path

from django.core.files.storage import default_storage
from django.core.exceptions import ValidationError
from django.db import transaction

from api.models import DocumentVersion, InternshipFolder
from api.documents.validators import validate_pdf_file


@transaction.atomic
def upload_document(folder_id, uploaded_file):
    """
    Dépose une nouvelle version d'un document
    dans un dossier de stage existant.
    """

    # Vérifier le fichier avant de le stocker
    validate_pdf_file(uploaded_file)

    # Verrouiller le dossier pendant la création de la version
    try:
        folder = InternshipFolder.objects.select_for_update().get(
            pk=folder_id
        )
    except InternshipFolder.DoesNotExist:
        raise ValidationError(
            "Le dossier de stage demandé n'existe pas."
        )

    # Calculer le prochain numéro de version
    last_version = (
        DocumentVersion.objects
        .filter(folder=folder)
        .order_by("-version_number")
        .first()
    )

    next_version = (
        last_version.version_number + 1
        if last_version
        else 1
    )

    # Générer un nom imprévisible
    safe_filename = f"{uuid.uuid4().hex}.pdf"

    storage_path = (
        f"documents/folder_{folder.id}/{safe_filename}"
    )

    saved_path = default_storage.save(
        storage_path,
        uploaded_file
    )

    try:
        document = DocumentVersion.objects.create(
            folder=folder,
            version_number=next_version,
            file_path=saved_path,
        )
    except Exception:
        # Nettoyer le fichier si l'enregistrement échoue
        default_storage.delete(saved_path)
        raise

    return document