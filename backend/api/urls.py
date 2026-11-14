from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    AssessmentViewSet,
    CampaignViewSet,
    DefenseViewSet,
    DocumentVersionViewSet,
    InternshipFolderViewSet,
    JuryMemberViewSet,
    JuryViewSet,
    ReviewViewSet,
    SalleViewSet,
    StudentViewSet,
)

# Routeur principal DRF pour les ViewSets
router = DefaultRouter()
router.register(r'campaigns', CampaignViewSet, basename='campaign')
router.register(r'students', StudentViewSet, basename='student')
router.register(r'internship-folders', InternshipFolderViewSet, basename='internship-folder')
router.register(r'document-versions', DocumentVersionViewSet, basename='document-version')
router.register(r'reviews', ReviewViewSet, basename='review')
router.register(r'rooms', SalleViewSet, basename='room')
router.register(r'jurys', JuryViewSet, basename='jury')
router.register(r'jury-members', JuryMemberViewSet, basename='jury-member')
router.register(r'defenses', DefenseViewSet, basename='defense')
router.register(r'assessments', AssessmentViewSet, basename='assessment')

urlpatterns = [
    # Inclusion de toutes les routes du routeur DRF
    path('', include(router.urls)),
]