from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.storage import default_storage
from django.http import FileResponse
from django.shortcuts import get_object_or_404

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.exceptions import PermissionDenied, ValidationError

from api.models import InternshipFolder, DocumentVersion
from api.serializers import DocumentVersionSerializer
from api.documents.services import upload_document
from api.roles import get_user_role


def get_student_for_user(user):
    """Récupère la fiche étudiant liée au compte connecté."""
    account = getattr(user, "student_account", None)
    return account.student if account else None


class DocumentUploadView(APIView):
    """Permet de déposer un document PDF dans un dossier de stage."""

    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        folder_id = request.data.get("folder_id")
        uploaded_file = request.FILES.get("file")

        if not folder_id or not uploaded_file:
            return Response(
                {"error": "Le dossier et le fichier PDF sont obligatoires."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            folder_id = int(folder_id)
        except (ValueError, TypeError):
            return Response(
                {"error": "Identifiant du dossier invalide."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        folder = get_object_or_404(InternshipFolder, pk=folder_id)

        role = get_user_role(request.user)
        student = get_student_for_user(request.user)

        if role not in ("admin", "responsible"):
            if student is None or folder.student_id != student.id:
                raise PermissionDenied(
                    "Vous ne pouvez déposer un document que dans votre propre dossier."
                )

        try:
            document = upload_document(folder.id, uploaded_file)
        except DjangoValidationError as error:
            raise ValidationError(error.messages) from error

        return Response(
            {
                "message": "Document déposé avec succès.",
                "document": DocumentVersionSerializer(document).data,
            },
            status=status.HTTP_201_CREATED,
        )


class DocumentDownloadView(APIView):
    """Permet de télécharger un document en respectant les droits d'accès."""

    permission_classes = [IsAuthenticated]

    def get(self, request, document_id):
        document = get_object_or_404(
            DocumentVersion.objects.select_related("folder", "folder__student"),
            pk=document_id,
        )

        role = get_user_role(request.user)
        student = get_student_for_user(request.user)

        if role not in ("admin", "responsible"):
            if student is None or document.folder.student_id != student.id:
                raise PermissionDenied(
                    "Vous ne pouvez pas télécharger ce document."
                )

        try:
            file = default_storage.open(document.file_path, "rb")
        except (FileNotFoundError, OSError):
            return Response(
                {"error": "Le fichier demandé est introuvable."},
                status=status.HTTP_404_NOT_FOUND,
            )

        filename = f"document_{document.id}_v{document.version_number}.pdf"

        return FileResponse(
            file,
            as_attachment=True,
            filename=filename,
            content_type="application/pdf",
        )