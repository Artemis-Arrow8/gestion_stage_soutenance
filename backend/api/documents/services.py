"""
Services métier de la gestion documentaire (dépôt des rapports de stage).

Le dépôt est transactionnel : le dossier est verrouillé pendant le calcul du
numéro de version afin que deux dépôts simultanés ne produisent jamais deux
fois la même version.
"""

import uuid

from django.core.exceptions import ValidationError
from django.core.files.storage import default_storage
from django.db import transaction

from api.documents.validators import validate_pdf_file
from api.models import DocumentVersion, InternshipFolder


@transaction.atomic
def upload_document(folder_id, uploaded_file):
    """
    Dépose une nouvelle version de document dans un dossier de stage.

    Paramètres :
        folder_id (int) : identifiant du dossier de stage cible.
        uploaded_file (UploadedFile) : fichier PDF reçu.

    Retour :
        DocumentVersion : la version créée (numéro = dernière version + 1).

    Lève :
        ValidationError : fichier invalide ou dossier inexistant.
    """
    # Vérifier le fichier avant de le stocker.
    validate_pdf_file(uploaded_file)

    # Verrouiller la ligne du dossier (SELECT … FOR UPDATE) pendant la
    # création : un dépôt concurrent attendra la fin de cette transaction.
    try:
        folder = InternshipFolder.objects.select_for_update().get(
            pk=folder_id
        )
    except InternshipFolder.DoesNotExist:
        raise ValidationError(
            "Le dossier de stage demandé n'existe pas."
        )

    # Calculer le prochain numéro de version.
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

    # Générer un nom de fichier imprévisible : le nom d'origine fourni par le
    # client n'est jamais utilisé (évite collisions et traversée de chemin).
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
        # Nettoyer le fichier orphelin si l'enregistrement en base échoue.
        default_storage.delete(saved_path)
        raise

    return document
