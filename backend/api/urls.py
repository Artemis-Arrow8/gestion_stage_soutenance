from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .documents.views import DocumentUploadView, DocumentDownloadView
from .views import (
    CampaignViewSet, StudentViewSet, InternshipFolderViewSet,
    DocumentVersionViewSet, ReviewViewSet, JuryViewSet,
    JuryMemberViewSet, DefenseViewSet, AssessmentViewSet, LoginView,
    LogoutView, UserAccountViewSet, UserProfileView,
)

router = DefaultRouter()
router.register(r'accounts', UserAccountViewSet, basename='account')
router.register(r'campaigns', CampaignViewSet)
router.register(r'students', StudentViewSet)
router.register(r'internship-folders', InternshipFolderViewSet)
router.register(r'document-versions', DocumentVersionViewSet)
router.register(r'reviews', ReviewViewSet)
router.register(r'juries', JuryViewSet)
router.register(r'jury-members', JuryMemberViewSet)
router.register(r'defenses', DefenseViewSet)
router.register(r'assessments', AssessmentViewSet)

urlpatterns = [
    path('', include(router.urls)),
    path('login/', LoginView.as_view(), name='api-login'),
    path('logout/', LogoutView.as_view(), name='api-logout'),
    path('profile/', UserProfileView.as_view(), name='api-profile'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token-refresh'),
    path('documents/upload/', DocumentUploadView.as_view(), name='document-upload'),
    path('documents/download/<int:document_id>/', DocumentDownloadView.as_view(), name='document-download'),
]