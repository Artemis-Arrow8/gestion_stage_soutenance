"""
Vues HTTP de la gestion documentaire : dépôt et téléchargement des rapports.

Routes :
    POST /api/documents/upload/                      (multipart : folder_id, file)
    GET  /api/documents/download/<document_id>/

Contrôles d'accès appliqués :
    * dépôt : admin, responsable, ou étudiant propriétaire du dossier ;
    * téléchargement : admin, responsable, étudiant propriétaire ou
      encadreur affecté au dossier.
"""

from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.storage import default_storage
from django.http import FileResponse, Http404
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from api.documents.services import upload_document
from api.models import DocumentVersion, FolderSupervisor, InternshipFolder
from api.roles import get_user_role
from api.serializers import DocumentVersionSerializer

# Rôles autorisés à déposer un document.
ROLES_DEPOT = ('admin', 'responsible', 'student')

# Rôles autorisés à télécharger un document (sous réserve de périmètre).
ROLES_TELECHARGEMENT = ('admin', 'responsible', 'student', 'supervisor')


class DocumentUploadView(APIView):
    """
    Dépose une nouvelle version de rapport dans un dossier de stage.

    Réponses :
        201 : version créée (DocumentVersionSerializer) ;
        400 : identifiant de dossier invalide, fichier absent ou non conforme ;
        403 : rôle non autorisé ou dossier d'un autre étudiant ;
        404 : dossier inexistant.
    """

    # Le fichier arrive en multipart/form-data.
    parser_classes = [MultiPartParser, FormParser]
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, folder_id=None):
        """
        Valide les droits et le fichier puis délègue le stockage au service.

        Paramètres :
            request : requête multipart contenant `folder_id` et `file`.
            folder_id (int | None) : identifiant passé dans l'URL (optionnel ;
                à défaut, il est lu dans le corps de la requête).
        """
        user = request.user
        role = get_user_role(user)
        if role not in ROLES_DEPOT:
            return Response(
                {"error": "Votre rôle ne permet pas de déposer un document."},
                status=status.HTTP_403_FORBIDDEN
            )

        # Identifiant du dossier : URL d'abord, sinon champ de formulaire.
        if folder_id is None:
            try:
                folder_id = int(request.data.get('folder_id'))
            except (TypeError, ValueError):
                return Response(
                    {"error": "L'identifiant du dossier est invalide."},
                    status=status.HTTP_400_BAD_REQUEST
                )

        # Vérification de l'existence du dossier de stage.
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
                # Fiche étudiante sans compte associé : accès refusé.
                return Response(
                    {"error": "Vous n'êtes pas autorisé à modifier ce dossier."},
                    status=status.HTTP_403_FORBIDDEN
                )

        # Récupération du fichier envoyé.
        file_obj = request.FILES.get('file')
        if not file_obj:
            return Response(
                {"error": "Aucun fichier fourni."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Validation PDF + versionnement + stockage (transactionnel).
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
    """
    Télécharge le fichier PDF d'une version de document.

    Réponses :
        200 : flux binaire du PDF (pièce jointe) ;
        403 : rôle non autorisé ou document hors du périmètre de l'appelant ;
        404 : version inexistante ou fichier physique absent du stockage.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, document_id):
        """
        Contrôle le périmètre d'accès puis renvoie le fichier en streaming.

        Paramètres :
            document_id (int) : identifiant de la version demandée.
        """
        try:
            doc = DocumentVersion.objects.get(pk=document_id)
        except DocumentVersion.DoesNotExist:
            raise Http404("Le document demandé est introuvable.")

        role = get_user_role(request.user)
        if role not in ROLES_TELECHARGEMENT:
            return Response(
                {"error": "Votre rôle ne permet pas de télécharger ce document."},
                status=status.HTTP_403_FORBIDDEN
            )
        if role == 'student':
            # Un étudiant ne télécharge que les documents de son propre dossier.
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
            # Un encadreur ne télécharge que les dossiers qui lui sont affectés.
            return Response(
                {"error": "Ce dossier ne vous a pas été affecté."},
                status=status.HTTP_403_FORBIDDEN
            )

        # Le stockage Render gratuit est éphémère : le fichier peut avoir
        # disparu après un redéploiement alors que la ligne existe encore.
        if not default_storage.exists(doc.file_path):
            return Response(
                {"error": "Le fichier physique est introuvable sur le serveur."},
                status=status.HTTP_404_NOT_FOUND
            )

        # `FileResponse` diffuse le fichier par blocs sans le charger en mémoire.
        file_handle = default_storage.open(doc.file_path, 'rb')
        return FileResponse(
            file_handle,
            as_attachment=True,
            filename=doc.file_path.split('/')[-1],
        )
