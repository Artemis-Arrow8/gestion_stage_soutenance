"""
Vues du domaine académique : campagnes, étudiants, dossiers de stage,
versions de documents, avis d'encadrement et évaluations.

Chaque ViewSet applique deux niveaux de contrôle :
    * une classe de permission (qui peut appeler la route) ;
    * un filtrage du QuerySet (quelles lignes le rôle peut voir).
Ce double contrôle garantit qu'un étudiant ou un encadreur ne voit jamais
les dossiers des autres, même en devinant un identifiant.
"""

from rest_framework import viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError

from api.models import (
    Assessment,
    Campaign,
    DocumentVersion,
    InternshipFolder,
    Review,
    Student,
)
from api.permissions import (
    IsAdminOrPedagogicalResponsible,
    IsAdminResponsibleOrStudent,
    IsReviewReader,
    IsSupervisor,
)
from api.roles import get_user_role
from api.serializers import (
    AssessmentSerializer,
    CampaignSerializer,
    DocumentVersionSerializer,
    InternshipFolderSerializer,
    ReviewSerializer,
    StudentSerializer,
)

from .helpers import etudiant_du_compte


class CampaignViewSet(viewsets.ModelViewSet):
    """CRUD des campagnes académiques (/api/campaigns/), réservé au personnel."""

    # Les campagnes les plus récentes apparaissent en premier.
    queryset = Campaign.objects.all().order_by('-id')
    serializer_class = CampaignSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class StudentViewSet(viewsets.ModelViewSet):
    """CRUD des fiches étudiantes (/api/students/), réservé au personnel."""

    queryset = Student.objects.all()
    serializer_class = StudentSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class InternshipFolderViewSet(viewsets.ModelViewSet):
    """
    Gestion des dossiers de stage (/api/internship-folders/).

    Règles par rôle :
        * admin / responsable : accès complet ;
        * encadreur : lecture seule des dossiers qui lui sont affectés ;
        * étudiant : ses propres dossiers ; il ne peut ni changer le statut,
          ni réattribuer le dossier, ni changer de campagne après création.
    """

    queryset = InternshipFolder.objects.all()
    serializer_class = InternshipFolderSerializer
    permission_classes = [IsAdminResponsibleOrStudent]

    def get_serializer(self, *args, **kwargs):
        """
        Rend certains champs non modifiables lorsque l'appelant est étudiant.

        Retour :
            Le sérialiseur standard, dont les champs `student`, `status` (et
            `campaign` en modification) passent en lecture seule pour un
            étudiant : ces valeurs sont imposées côté serveur.
        """
        serializer = super().get_serializer(*args, **kwargs)
        if (
            get_user_role(self.request.user) == 'student'
            and self.action in ('create', 'update', 'partial_update')
        ):
            serializer.fields['student'].read_only = True
            serializer.fields['status'].read_only = True
            if self.action in ('update', 'partial_update'):
                serializer.fields['campaign'].read_only = True
            else:
                # À la création, la campagne devient facultative : l'étudiant
                # ne peut pas lister les campagnes, le serveur choisit donc
                # la campagne active (voir `perform_create`).
                serializer.fields['campaign'].required = False
        return serializer

    def get_queryset(self):
        """Filtre les dossiers visibles selon le rôle de l'appelant."""
        # `super().get_queryset()` renvoie une COPIE fraîche du queryset de
        # classe : sans elle, le résultat de la première liste resterait en
        # cache dans le processus et les nouvelles lignes seraient invisibles.
        base = super().get_queryset()
        role = get_user_role(self.request.user)
        student = etudiant_du_compte(self.request.user)
        if role in ('admin', 'responsible'):
            return base
        if role == 'supervisor':
            # `distinct()` évite les doublons dus à la jointure d'affectation.
            return base.filter(
                supervisor_assignments__user=self.request.user
            ).distinct()
        if student is None:
            return base.none()
        return base.filter(student=student)

    def perform_create(self, serializer):
        """
        Enregistre un nouveau dossier.

        Pour un étudiant, le dossier est forcément rattaché à sa propre fiche
        et créé au statut « brouillon ». Sans campagne fournie, la campagne
        active la plus récente est utilisée.

        Lève :
            PermissionDenied : compte étudiant sans fiche associée.
            ValidationError : aucune campagne active disponible.
        """
        student = etudiant_du_compte(self.request.user)
        if get_user_role(self.request.user) == 'student':
            if student is None:
                raise PermissionDenied("Aucun profil étudiant n'est associé à ce compte.")
            campagne = serializer.validated_data.get('campaign')
            if campagne is None:
                campagne = Campaign.objects.filter(is_active=True).order_by('-id').first()
            if campagne is None:
                raise ValidationError({
                    'campaign': "Aucune campagne n'est ouverte : contactez la scolarité."
                })
            serializer.save(student=student, status='brouillon', campaign=campagne)
            return
        serializer.save()

    def perform_update(self, serializer):
        """
        Enregistre une modification de dossier.

        Pour un étudiant, le propriétaire, le statut et la campagne d'origine
        sont réimposés : seules les informations descriptives changent.

        Lève :
            PermissionDenied : compte étudiant sans fiche associée.
        """
        student = etudiant_du_compte(self.request.user)
        if get_user_role(self.request.user) == 'student':
            if student is None:
                raise PermissionDenied("Aucun profil étudiant n'est associé à ce compte.")
            serializer.save(
                student=student,
                status=serializer.instance.status,
                campaign=serializer.instance.campaign,
            )
            return
        serializer.save()


class DocumentVersionViewSet(viewsets.ReadOnlyModelViewSet):
    """
    Consultation des versions de rapports (/api/document-versions/).

    Lecture seule : le dépôt passe par /api/documents/upload/ qui valide le
    PDF et calcule le numéro de version (voir `api.documents`).
    """

    queryset = DocumentVersion.objects.all()
    serializer_class = DocumentVersionSerializer
    permission_classes = [IsAdminResponsibleOrStudent]

    def get_queryset(self):
        """Restreint les versions visibles au périmètre du rôle."""
        # `super().get_queryset()` renvoie une COPIE fraîche du queryset de
        # classe : sans elle, le résultat de la première liste resterait en
        # cache dans le processus et les nouvelles lignes seraient invisibles.
        base = super().get_queryset()
        role = get_user_role(self.request.user)
        student = etudiant_du_compte(self.request.user)
        if role in ('admin', 'responsible'):
            return base
        if role == 'supervisor':
            return base.filter(
                folder__supervisor_assignments__user=self.request.user
            ).distinct()
        if student is None:
            return base.none()
        return base.filter(folder__student=student)


class ReviewViewSet(viewsets.ModelViewSet):
    """
    Avis d'encadrement sur les versions de documents (/api/reviews/).

    * Lecture : admin, encadreur (ses propres avis sur ses dossiers),
      étudiant (avis portant sur ses documents).
    * Écriture : admin et encadreur uniquement.
    Filtre optionnel : ?document_version_id=<id>.
    """

    queryset = Review.objects.all()
    serializer_class = ReviewSerializer
    permission_classes = [IsSupervisor]

    def get_permissions(self):
        """Choisit la permission selon l'action (lecture plus large qu'écriture)."""
        permission = (
            IsReviewReader
            if self.action in ('list', 'retrieve')
            else IsSupervisor
        )
        return [permission()]

    def get_queryset(self):
        """
        Filtre les avis visibles puis applique le filtre `document_version_id`.

        Lève :
            ValidationError : `document_version_id` non entier (HTTP 400).
        """
        # `super().get_queryset()` renvoie une COPIE fraîche du queryset de
        # classe : sans elle, le résultat de la première liste resterait en
        # cache dans le processus et les nouvelles lignes seraient invisibles.
        base = super().get_queryset()
        role = get_user_role(self.request.user)
        if role == 'admin':
            queryset = base
        elif role == 'supervisor':
            # Un encadreur ne voit que ses avis, sur des dossiers affectés.
            queryset = base.filter(
                author=self.request.user,
                document_version__folder__supervisor_assignments__user=self.request.user
            ).distinct()
        elif role == 'student':
            student = etudiant_du_compte(self.request.user)
            if student is None:
                return base.none()
            queryset = base.filter(
                document_version__folder__student=student
            )
        else:
            return base.none()

        document_id = self.request.query_params.get('document_version_id')
        if document_id is not None:
            try:
                document_id = int(document_id)
            except ValueError as error:
                raise ValidationError({
                    'document_version_id': 'Un identifiant entier est requis.'
                }) from error
            queryset = queryset.filter(document_version_id=document_id)
        return queryset

    def perform_create(self, serializer):
        """
        Crée un avis en imposant l'auteur et son rôle.

        Lève :
            PermissionDenied : un encadreur tente de commenter un dossier
            qui ne lui est pas affecté.
        """
        if get_user_role(self.request.user) == 'supervisor':
            document = serializer.validated_data['document_version']
            if not document.folder.supervisor_assignments.filter(
                user=self.request.user
            ).exists():
                raise PermissionDenied(
                    "Vous ne pouvez donner un avis que sur un dossier qui vous est affecté."
                )
        # L'auteur n'est jamais fourni par le client : il est déduit du jeton.
        serializer.save(
            author=self.request.user,
            author_role='encadreur',
        )


class AssessmentViewSet(viewsets.ModelViewSet):
    """CRUD des évaluations et notes finales (/api/assessments/), réservé au personnel."""

    # Jointures préchargées (étudiant, jury) et tri par date de soutenance.
    queryset = Assessment.objects.select_related(
        'defense__folder__student', 'defense__jury',
    ).order_by('defense__slot_range', 'pk')
    serializer_class = AssessmentSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]
