from django.core.files.storage import default_storage
from django.core.exceptions import ValidationError as DjangoValidationError
from django.http import FileResponse, Http404
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from api.models import DocumentVersion, FolderSupervisor, InternshipFolder
from api.serializers import DocumentVersionSerializer
from api.roles import get_user_role
from api.documents.services import upload_document


class DocumentUploadView(APIView):
    """
    Permet de déposer ou uploader un document/rapport de stage
    lié à un dossier de stage spécifique.
    """
    parser_classes = [MultiPartParser, FormParser]
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, folder_id=None):
        user = request.user
        role = get_user_role(user)
        if role not in ('admin', 'responsible', 'student'):
            return Response(
                {"error": "Votre rôle ne permet pas de déposer un document."},
                status=status.HTTP_403_FORBIDDEN
            )

        if folder_id is None:
            try:
                folder_id = int(request.data.get('folder_id'))
            except (TypeError, ValueError):
                return Response(
                    {"error": "L'identifiant du dossier est invalide."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Vérification de l'existence du dossier de stage
        try:
            folder = InternshipFolder.objects.get(pk=folder_id)
        except InternshipFolder.DoesNotExist:
            return Response(
                {"error": "Le dossier de stage est introuvable."},
                status=status.HTTP_404_NOT_FOUND
            )

        # L'étudiant ne peut déposer que dans son dossier ; le personnel
        # administratif peut déposer pour les besoins de la gestion.
        if role == 'student':
            try:
                if folder.student.student_account.user != user:
                    return Response(
                        {"error": "Vous n'êtes pas autorisé à modifier ce dossier."},
                        status=status.HTTP_403_FORBIDDEN
                    )
            except AttributeError:
                return Response(
                    {"error": "Vous n'êtes pas autorisé à modifier ce dossier."},
                    status=status.HTTP_403_FORBIDDEN
                )

        # Récupération du fichier envoyé
        file_obj = request.FILES.get('file')
        if not file_obj:
            return Response(
                {"error": "Aucun fichier fourni."},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            document_version = upload_document(folder.pk, file_obj)
        except DjangoValidationError as error:
            return Response(
                {"file": error.messages},
                status=status.HTTP_400_BAD_REQUEST
            )

        serializer = DocumentVersionSerializer(document_version)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class DocumentDownloadView(APIView):
    """Permet de télécharger ou consulter un document versionné."""
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, document_id):
        try:
            doc = DocumentVersion.objects.get(pk=document_id)
        except DocumentVersion.DoesNotExist:
            raise Http404("Le document demandé est introuvable.")

        role = get_user_role(request.user)
        if role not in ('admin', 'responsible', 'student', 'supervisor'):
            return Response(
                {"error": "Votre rôle ne permet pas de télécharger ce document."},
                status=status.HTTP_403_FORBIDDEN
            )
        if role == 'student':
            try:
                owns_document = (
                    doc.folder.student.student_account.user_id == request.user.pk
                )
            except AttributeError:
                owns_document = False
            if not owns_document:
                return Response(
                    {"error": "Vous n'êtes pas autorisé à consulter ce document."},
                    status=status.HTTP_403_FORBIDDEN
                )
        elif role == 'supervisor' and not FolderSupervisor.objects.filter(
            user=request.user,
            folder=doc.folder,
        ).exists():
            return Response(
                {"error": "Ce dossier ne vous a pas été affecté."},
                status=status.HTTP_403_FORBIDDEN
            )

        if not default_storage.exists(doc.file_path):
            return Response(
                {"error": "Le fichier physique est introuvable sur le serveur."},
                status=status.HTTP_404_NOT_FOUND
            )

        file_handle = default_storage.open(doc.file_path, 'rb')
        return FileResponse(file_handle, as_attachment=True, filename=doc.file_path.split('/')[-1])