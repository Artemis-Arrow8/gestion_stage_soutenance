from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    CampaignViewSet, UserViewSet, StudentViewSet, 
    InternshipViewSet, DefenseViewSet
)

router = DefaultRouter()
router.register(r'campaigns', CampaignViewSet)
router.register(r'users', UserViewSet)
router.register(r'students', StudentViewSet)
router.register(r'internships', InternshipViewSet)
router.register(r'defenses', DefenseViewSet)

urlpatterns = [
    path('', include(router.urls)),
]