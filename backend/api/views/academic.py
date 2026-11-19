"""
Vues du domaine académique : campagnes, étudiants, dossiers de stage,
versions de documents, avis d'encadrement et évaluations.

Chaque ViewSet applique deux niveaux de contrôle :
    * une classe de permission (qui peut appeler la route) ;
    * un filtrage du QuerySet (quelles lignes le rôle peut voir).
Ce double contrôle garantit qu'un étudiant ou un encadreur ne voit jamais
les dossiers des autres, même en devinant un identifiant.
"""

from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from api.exceptions import ConflitMetier
from api.models import (
    Assessment,
    Campaign,
    ConfidentialiteDossier,
    DocumentVersion,
    InternshipFolder,
    Review,
    Student,
)
from api.permissions import (
    IsAdminOrPedagogicalResponsible,
    IsAdminResponsibleOrStudent,
    IsPersonnelOrJury,
    IsReviewReader,
    IsSupervisor,
)
from api.roles import get_user_role
from api.serializers import (
    AssessmentSerializer,
    CampaignSerializer,
    ConfidentialiteDossierSerializer,
    DocumentVersionSerializer,
    HistoriqueDossierSerializer,
    InternshipFolderSerializer,
    ProcesVerbalSerializer,
    ReviewSerializer,
    StudentSerializer,
)
from api.services import dossiers, import_etudiants, notes
from api.services.idempotence import executer_idempotent

from .helpers import etudiant_du_compte


class CampaignViewSet(viewsets.ModelViewSet):
    """CRUD des campagnes académiques (/api/campaigns/), réservé au personnel."""

    # Les campagnes les plus récentes apparaissent en premier.
    queryset = Campaign.objects.all().order_by('-id')
    serializer_class = CampaignSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]


class StudentViewSet(viewsets.ModelViewSet):
    """
    CRUD des fiches étudiantes (/api/students/), réservé au personnel.

    Action POST /api/students/importer/ (F01) : import CSV idempotent avec
    prévisualisation (`simulation`), voir api/services/import_etudiants.py.
    """

    queryset = Student.objects.all()
    serializer_class = StudentSerializer
    permission_classes = [IsAdminOrPedagogicalResponsible]

    @action(detail=False, methods=['post'], url_path='importer',
            parser_classes=[MultiPartParser, FormParser, JSONParser])
    def importer(self, request):
        """
        Importe des étudiants dans une campagne.

        Corps : `campagne` (identifiant), `simulation` (booléen, facultatif)
        et soit un fichier CSV `fichier`, soit un texte CSV `csv`.
        Réponse 200 : rapport {etudiants_crees, etudiants_existants,
        dossiers_crees, dossiers_existants, erreurs[{ligne, erreur}]}.
        """
        campagne = Campaign.objects.filter(pk=request.data.get('campagne')).first()
        if campagne is None:
            raise ValidationError({'campagne': 'Choisissez une campagne existante.'})
        fichier = request.FILES.get('fichier')
        if fichier is not None:
            if fichier.size > 2 * 1024 * 1024:
                raise ValidationError({'fichier': 'Fichier trop volumineux (2 Mo maximum).'})
            try:
                texte = fichier.read().decode('utf-8-sig')
            except UnicodeDecodeError as erreur:
                raise ValidationError({'fichier': 'Le fichier doit être encodé en UTF-8.'}) from erreur
        else:
            texte = request.data.get('csv') or ''
        try:
            lignes = import_etudiants.lire_csv(texte)
        except ValueError as erreur:
            raise ValidationError({'fichier': str(erreur)}) from erreur
        simulation = str(request.data.get('simulation', '')).lower() in ('1', 'true', 'oui')

        def operation():
            rapport = import_etudiants.importer(lignes, campagne, request.user, simulation)
            return Response(rapport, status=status.HTTP_200_OK)

        return executer_idempotent(request, 'etudiants.importer', operation)


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

    # --- Transitions (api/services/dossiers.py) -------------------------
    # Chaque action passe par get_object() : un dossier hors du périmètre
    # de l'appelant renvoie 404 (son existence n'est pas révélée).

    def _repondre(self, dossier):
        """
        Renvoie le dossier à jour après une transition.

        Le dossier est relu par le queryset de la vue (et non par
        `refresh_from_db`) : les versions, avis et historique préchargés
        reflètent ainsi la transition qui vient d'être enregistrée.
        """
        dossier = self.get_queryset().get(pk=dossier.pk)
        return Response(self.get_serializer(dossier).data)

    @action(detail=True, methods=['post'])
    def soumettre(self, request, pk=None):
        """L'étudiant soumet son dossier (brouillon/à corriger → soumis)."""
        dossier = self.get_object()
        return self._repondre(dossiers.soumettre(dossier.pk, request.user))

    @action(detail=True, methods=['post'])
    def autoriser(self, request, pk=None):
        """Le responsable autorise la soutenance (validé → recevable)."""
        dossier = self.get_object()
        return self._repondre(dossiers.autoriser_soutenance(dossier.pk, request.user))

    @action(detail=True, methods=['post'])
    def refuser(self, request, pk=None):
        """Le responsable refuse le dossier ; corps : {"motif": "…"}."""
        dossier = self.get_object()
        return self._repondre(dossiers.refuser(dossier.pk, request.user, request.data.get('motif')))

    @action(detail=True, methods=['post'])
    def rouvrir(self, request, pk=None):
        """Le responsable rouvre un dossier refusé ou recevable ; corps : {"motif"}."""
        dossier = self.get_object()
        return self._repondre(dossiers.rouvrir(dossier.pk, request.user, request.data.get('motif')))

    @action(detail=True, methods=['get'])
    def historique(self, request, pk=None):
        """Historique des transitions du dossier (preuves conservées)."""
        dossier = self.get_object()
        lignes = dossier.historique.select_related('acteur', 'version_document')
        return Response(HistoriqueDossierSerializer(lignes, many=True).data)

    @action(detail=True, methods=['get', 'put'])
    def confidentialite(self, request, pk=None):
        """
        Lit (tous les ayants droit du dossier) ou modifie (personnel) le
        niveau de confidentialité, l'origine et l'embargo du rapport.
        """
        dossier = self.get_object()
        reglage, _ = ConfidentialiteDossier.objects.get_or_create(dossier=dossier)
        if request.method == 'PUT':
            if get_user_role(request.user) not in ('admin', 'responsible'):
                raise PermissionDenied("Seul le personnel modifie la confidentialité.")
            serializer = ConfidentialiteDossierSerializer(reglage, data=request.data)
            serializer.is_valid(raise_exception=True)
            serializer.save(decide_par=request.user)
            reglage.refresh_from_db()
        return Response(ConfidentialiteDossierSerializer(reglage).data)

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
        # Préchargement des champs d'affichage du sérialiseur (étudiant,
        # versions, avis, historique) : nombre de requêtes constant, quel
        # que soit le nombre de dossiers listés.
        base = (
            super().get_queryset()
            .select_related('student', 'confidentialite')
            .prefetch_related('document_versions__reviews', 'historique')
        )
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
            self._refuser_doublon(student, campagne)
            serializer.save(student=student, status='brouillon', campaign=campagne)
            return
        self._refuser_doublon(
            serializer.validated_data.get('student'),
            serializer.validated_data.get('campaign'),
        )
        serializer.save()

    @staticmethod
    def _refuser_doublon(etudiant, campagne):
        """
        F01 : un étudiant n'a qu'un dossier par campagne (index unique en base,
        migration 0013) ; on l'explique par un 409 plutôt qu'une erreur 500.
        """
        if etudiant is not None and campagne is not None and InternshipFolder.objects.filter(
            student=etudiant, campaign=campagne,
        ).exists():
            raise ConflitMetier(
                "Un dossier de stage existe déjà pour cet étudiant dans cette "
                "campagne : complétez-le plutôt que d'en créer un second.",
                regle='F01',
            )

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
    # Un avis est une décision tracée : il ne se modifie ni ne se supprime.
    # Une nouvelle version du rapport appelle un NOUVEL avis (STA05).
    http_method_names = ['get', 'post', 'head', 'options']

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
        Enregistre l'avis pédagogique via la machine à états du dossier.

        L'auteur est déduit du jeton ; l'avis est rattaché à la version
        examinée et fait passer le dossier soumis à « valide » (favorable)
        ou « a_corriger » (défavorable).

        Lève :
            PermissionDenied : encadreur non affecté au dossier ;
            ConflitMetier : dossier non soumis ou version périmée.
        """
        donnees = serializer.validated_data
        serializer.instance = dossiers.enregistrer_avis_pedagogique(
            donnees['document_version'].pk,
            self.request.user,
            (donnees.get('decision') or '').strip().lower(),
            donnees.get('comments') or '',
        )


class AssessmentViewSet(viewsets.ModelViewSet):
    """
    Évaluations et procès-verbaux (/api/assessments/), F06.

    * Personnel : toutes les évaluations. Membre du jury : uniquement celles
      des soutenances de son jury ; il saisit les notes, le président les
      approuve. La moyenne est calculée par le serveur (grille 40/60).
    * Une évaluation approuvée ne se modifie ni ne se supprime (STA06) :
      POST /rectifier/ (responsable, avec motif) crée une nouvelle version
      du procès-verbal (STA12).
    * POST /approuver/ : approbation (notes complètes, jury complet).
    * GET /proces-verbaux/ : toutes les versions du procès-verbal.
    """

    # Jointures préchargées (étudiant, jury) et tri par date de soutenance.
    queryset = Assessment.objects.select_related(
        'defense__folder__student', 'defense__folder__campaign', 'defense__jury',
    ).order_by('defense__slot_range', 'pk')
    serializer_class = AssessmentSerializer
    permission_classes = [IsPersonnelOrJury]

    def get_queryset(self):
        """Un membre du jury ne voit que les évaluations de son jury."""
        base = super().get_queryset()
        if get_user_role(self.request.user) == 'jury':
            return base.filter(
                defense__jury__members__account__user=self.request.user
            ).distinct()
        return base

    def _enregistrer(self, serializer):
        """Sauvegarde puis recalcule la moyenne selon la grille."""
        evaluation = serializer.save()
        notes.recalculer(evaluation)
        evaluation.save(update_fields=['final_average'])

    def perform_create(self, serializer):
        """Crée une évaluation (personnel ou membre du jury de la soutenance)."""
        brouillon = Assessment(defense=serializer.validated_data['defense'])
        if not notes.peut_saisir(self.request.user, brouillon):
            raise PermissionDenied("Vous ne siégez pas au jury de cette soutenance.")
        self._enregistrer(serializer)

    def perform_update(self, serializer):
        """Modifie une note non approuvée (STA06 sinon)."""
        notes.refuser_si_approuvee(serializer.instance)
        if not notes.peut_saisir(self.request.user, serializer.instance):
            raise PermissionDenied("Vous ne siégez pas au jury de cette soutenance.")
        self._enregistrer(serializer)

    def perform_destroy(self, instance):
        """Seul le personnel supprime une évaluation, jamais approuvée."""
        notes.refuser_si_approuvee(instance)
        if get_user_role(self.request.user) not in ('admin', 'responsible'):
            raise PermissionDenied("Seul le personnel peut supprimer une évaluation.")
        instance.delete()

    @action(detail=True, methods=['post'])
    def approuver(self, request, pk=None):
        """Approuve les notes et produit la version 1 du procès-verbal."""
        evaluation = self.get_object()

        def operation():
            pv = notes.approuver(evaluation.pk, request.user)
            return Response(ProcesVerbalSerializer(pv).data, status=status.HTTP_201_CREATED)

        return executer_idempotent(request, f'notes.approuver.{evaluation.pk}', operation)

    @action(detail=True, methods=['post'])
    def rectifier(self, request, pk=None):
        """
        Rectifie une note approuvée ; corps : report_grade, oral_grade, motif.
        Produit une nouvelle version du procès-verbal.
        """
        evaluation = self.get_object()

        def operation():
            pv = notes.rectifier(
                evaluation.pk, request.user,
                request.data.get('report_grade'), request.data.get('oral_grade'),
                request.data.get('motif'),
            )
            return Response(ProcesVerbalSerializer(pv).data, status=status.HTTP_201_CREATED)

        return executer_idempotent(request, f'notes.rectifier.{evaluation.pk}', operation)

    @action(detail=True, methods=['get'], url_path='proces-verbaux')
    def proces_verbaux(self, request, pk=None):
        """Toutes les versions du procès-verbal, de la plus ancienne à la plus récente."""
        evaluation = self.get_object()
        versions = evaluation.proces_verbaux.select_related('grille', 'approuve_par')
        return Response(ProcesVerbalSerializer(versions, many=True).data)
