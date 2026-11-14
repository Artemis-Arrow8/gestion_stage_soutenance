from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .documents.views import DocumentDownloadView, DocumentUploadView
from .views import (
    AssessmentViewSet,
    CampaignViewSet,
    DefenseViewSet,
    DocumentVersionViewSet,
    InternshipFolderViewSet,
    LoginView,
    JuryMemberViewSet,
    JuryViewSet,
    LogoutView,
    ReviewViewSet,
    SalleViewSet,
    StudentViewSet,
    UserAccountViewSet,
    UserProfileView,
)

# Routeur principal DRF pour les ViewSets
router = DefaultRouter()
router.register(r'accounts', UserAccountViewSet, basename='account')
router.register(r'campaigns', CampaignViewSet, basename='campaign')
router.register(r'students', StudentViewSet, basename='student')
router.register(r'internship-folders', InternshipFolderViewSet)
router.register(r'document-versions', DocumentVersionViewSet)
router.register(r'reviews', ReviewViewSet, basename='review')
router.register(r'rooms', SalleViewSet, basename='room')
router.register(r'salles', SalleViewSet, basename='salle')
router.register(r'jurys', JuryViewSet, basename='jury')
router.register(r'jury-members', JuryMemberViewSet, basename='jury-member')
router.register(r'membres-jury', JuryMemberViewSet, basename='membre-jury')
router.register(r'defenses', DefenseViewSet, basename='defense')
router.register(r'soutenances', DefenseViewSet, basename='soutenance')
router.register(r'assessments', AssessmentViewSet, basename='assessment')

urlpatterns = [
    # Inclusion de toutes les routes du routeur DRF
    path('', include(router.urls)),
    path('login/', LoginView.as_view(), name='api-login'),
    path('logout/', LogoutView.as_view(), name='api-logout'),
    path('profile/', UserProfileView.as_view(), name='api-profile'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token-refresh'),
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