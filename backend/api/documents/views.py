from django.core.files.storage import default_storage
from django.http import FileResponse, Http404
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from api.models import DocumentVersion, InternshipFolder
from api.serializers import DocumentVersionSerializer
from api.roles import get_user_role


class DocumentUploadView(APIView):
    """
    Permet de déposer ou uploader un document/rapport de stage
    lié à un dossier de stage spécifique.
    """
    parser_classes = [MultiPartParser, FormParser]
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, folder_id):
        user = request.user
        role = get_user_role(user)

        # Vérification de l'existence du dossier de stage
        try:
            folder = InternshipFolder.objects.get(pk=folder_id)
        except InternshipFolder.DoesNotExist:
            return Response(
                {"error": "Le dossier de stage est introuvable."},
                status=status.HTTP_404_NOT_FOUND
            )

        # Vérification des droits (étudiant propriétaire ou encadreur/admin)
        if role == 'student':
            try:
                if folder.student.student_account.user != user:
                    return Response(
                        {"error": "Vous n'êtes pas autorisé à modifier ce dossier."},
                        status=status.HTTP_403_FORBIDDEN
                    )
            except AttributeError:
                return Response(
                    {"error": "Compte étudiant non lié."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Récupération du fichier envoyé
        file_obj = request.FILES.get('file')
        if not file_obj:
            return Response(
                {"error": "Aucun fichier fourni."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Détermination du numéro de version suivant
        derniere_version = DocumentVersion.objects.filter(folder=folder).order_by('-version_number').first()
        prochain_num = (derniere_version.version_number + 1) if derniere_version else 1

        # Enregistrement du fichier via le stockage par défaut
        file_path = default_storage.save(f"documents/folder_{folder.pk}/{file_obj.name}", file_obj)

        # Création de l'enregistrement en base
        document_version = DocumentVersion.objects.create(
            folder=folder,
            version_number=prochain_num,
            file_path=file_path
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

        if not default_storage.exists(doc.file_path):
            return Response(
                {"error": "Le fichier physique est introuvable sur le serveur."},
                status=status.HTTP_404_NOT_FOUND
            )

        file_handle = default_storage.open(doc.file_path, 'rb')
        return FileResponse(file_handle, as_attachment=True, filename=doc.file_path.split('/')[-1])