"""
Table de routage de l'API REST SGSUS (montée sous le préfixe /api/).

Les ViewSets sont enregistrés auprès d'un `DefaultRouter` DRF, qui génère
automatiquement les routes de liste (`/ressource/`) et de détail
(`/ressource/<id>/`). Certaines ressources possèdent un alias français
(salles, soutenances, membres-jury) conservé pour compatibilité avec les
clients existants.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .documents.views import DocumentDownloadView, DocumentUploadView
from .views import (
    AssessmentViewSet,
    CampaignViewSet,
    ChangePasswordView,
    ConvocationViewSet,
    DefenseViewSet,
    DocumentVersionViewSet,
    HabilitationDossierViewSet,
    IndisponibiliteViewSet,
    InternshipFolderViewSet,
    JuryMemberViewSet,
    JuryViewSet,
    LoginView,
    LogoutView,
    ReviewViewSet,
    SalleViewSet,
    StudentViewSet,
    UserAccountViewSet,
    UserProfileView,
    VersionPlanningViewSet,
)

# Routeur principal DRF : il expose aussi une page d'index navigable sur /api/.
router = DefaultRouter()

# --- Comptes et référentiels académiques ---------------------------------
router.register(r'accounts', UserAccountViewSet, basename='account')
router.register(r'campaigns', CampaignViewSet, basename='campaign')
router.register(r'students', StudentViewSet, basename='student')
router.register(r'internship-folders', InternshipFolderViewSet)
router.register(r'document-versions', DocumentVersionViewSet)
router.register(r'reviews', ReviewViewSet, basename='review')
router.register(r'assessments', AssessmentViewSet, basename='assessment')

# --- Planification (avec alias français historiques) ------------------------
router.register(r'rooms', SalleViewSet, basename='room')
router.register(r'salles', SalleViewSet, basename='salle')
router.register(r'jurys', JuryViewSet, basename='jury')
router.register(r'jury-members', JuryMemberViewSet, basename='jury-member')
router.register(r'membres-jury', JuryMemberViewSet, basename='membre-jury')
router.register(r'defenses', DefenseViewSet, basename='defense')
router.register(r'soutenances', DefenseViewSet, basename='soutenance')
# Socle du dossier ALM : indisponibilités, planning publié, convocations,
# habilitations sur les dossiers confidentiels.
router.register(r'indisponibilites', IndisponibiliteViewSet, basename='indisponibilite')
router.register(r'versions-planning', VersionPlanningViewSet, basename='version-planning')
router.register(r'convocations', ConvocationViewSet, basename='convocation')
router.register(r'habilitations', HabilitationDossierViewSet, basename='habilitation')

urlpatterns = [
    # Toutes les routes générées par le routeur DRF.
    path('', include(router.urls)),

    # Authentification JWT.
    path('login/', LoginView.as_view(), name='api-login'),
    path('logout/', LogoutView.as_view(), name='api-logout'),
    path('profile/', UserProfileView.as_view(), name='api-profile'),
    # Changement de son propre mot de passe (utilisateur connecté).
    path(
        'profile/password/',
        ChangePasswordView.as_view(),
        name='api-change-password',
    ),
    path('token/refresh/', TokenRefreshView.as_view(), name='token-refresh'),

    # Dépôt et téléchargement des rapports PDF.
    path(
        'documents/upload/',
        DocumentUploadView.as_view(),
        name='document-upload',
    ),
    path(
        'documents/download/<int:document_id>/',
        DocumentDownloadView.as_view(),
        name='document-download',
    ),
]
