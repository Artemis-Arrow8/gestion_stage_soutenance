from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.storage import default_storage
from django.db import ProgrammingError, transaction
from django.http import FileResponse
from django.shortcuts import get_object_or_404

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser
from rest_framework.exceptions import PermissionDenied, ValidationError

from api.models import InternshipFolder, DocumentVersion, Review
from api.serializers import DocumentVersionSerializer, ReviewSerializer
from api.documents.services import upload_document
from api.roles import get_user_role


def get_student_for_user(user):
    """Récupère la fiche étudiant liée au compte connecté.

    Tolère une dérive de schéma (table student_account absente) en
    retournant None au lieu de faire planter toute la vue en 500.
    """
    try:
        account = getattr(user, "student_account", None)
    except ProgrammingError:
        # Réinitialise la transaction échouée pour garder la connexion utilisable.
        transaction.rollback()
        return None
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


class DocumentListView(APIView):
    """Affiche les versions des documents d'un dossier."""

    permission_classes = [IsAuthenticated]

    def get(self, request, folder_id):
        folder = get_object_or_404(
            InternshipFolder,
            pk=folder_id
        )

        role = get_user_role(request.user)
        student = get_student_for_user(request.user)

        if role not in ("admin", "responsible"):
            if student is None or folder.student_id != student.id:
                raise PermissionDenied(
                    "Vous ne pouvez pas consulter ce dossier."
                )

        documents = DocumentVersion.objects.filter(
            folder=folder
        ).order_by("-version_number")

        serializer = DocumentVersionSerializer(
            documents,
            many=True
        )

        return Response(serializer.data)


class ReviewListCreateView(APIView):
    """Avis de l'encadreur / du tuteur sur une version de document.

    GET  /api/documents/{id}/reviews/ — consultation (encadreur, responsable,
         admin ou étudiant propriétaire du dossier).
    POST /api/documents/{id}/reviews/ — création (encadreur, responsable ou
         admin uniquement) avec decision 'favorable' ou 'defavorable'.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request, document_id):
        document = get_object_or_404(
            DocumentVersion.objects.select_related("folder", "folder__student"),
            pk=document_id,
        )

        role = get_user_role(request.user)

        if role not in ("admin", "responsible", "supervisor"):
            student = get_student_for_user(request.user)
            if student is None or document.folder.student_id != student.id:
                raise PermissionDenied(
                    "Vous ne pouvez pas consulter les avis de ce document."
                )

        reviews = document.reviews.order_by("-created_at")
        serializer = ReviewSerializer(reviews, many=True)
        return Response(serializer.data)

    def post(self, request, document_id):
        document = get_object_or_404(
            DocumentVersion.objects.select_related("folder", "folder__student"),
            pk=document_id,
        )

        role = get_user_role(request.user)

        if role not in ("admin", "responsible", "supervisor"):
            raise PermissionDenied(
                "Seuls les encadreurs, responsables et administrateurs "
                "peuvent donner un avis sur un document."
            )

        decision = request.data.get("decision")
        if decision not in ("favorable", "defavorable"):
            return Response(
                {"error": "La décision doit valoir 'favorable' ou 'defavorable'."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        comments = request.data.get("comments") or None

        # L'auteur de l'avis est déduit du rôle du compte connecté.
        author_role = {"supervisor": "encadreur", "responsible": "tuteur"}.get(
            role, "encadreur"
        )
        # Un admin peut préciser explicitement sous quel chapeau il s'exprime.
        if role == "admin" and request.data.get("author_role") in ("encadreur", "tuteur"):
            author_role = request.data["author_role"]

        review = Review.objects.create(
            document_version=document,
            author_role=author_role,
            decision=decision,
            comments=comments,
        )

        serializer = ReviewSerializer(review)
        return Response(serializer.data, status=status.HTTP_201_CREATED)
