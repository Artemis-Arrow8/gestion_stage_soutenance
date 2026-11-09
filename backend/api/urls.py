"""
Routes de l'API SGSUS.

Ressources des autres lots : campaigns, users, students, dossiers.
Module planification (Tâche 4) : salles, jurys, membres-jury, soutenances
(avec l'action lecture seule /soutenances/planning/).
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from api.views import (
    CampaignViewSet,
    DefenseViewSet,
    InternshipFolderViewSet,
    JuryMemberViewSet,
    JuryViewSet,
    SalleViewSet,
    StudentViewSet,
    UserViewSet,
    LoginView,
    LogoutView,
    UserProfileView,
)

router = DefaultRouter()

router.register(r"campaigns", CampaignViewSet, basename="campaign")
router.register(r"users", UserViewSet, basename="user")
router.register(r"students", StudentViewSet, basename="student")
router.register(r"dossiers", InternshipFolderViewSet, basename="dossier")
router.register(r"salles", SalleViewSet, basename="salle")
router.register(r"jurys", JuryViewSet, basename="jury")
router.register(r"membres-jury", JuryMemberViewSet, basename="membre-jury")
router.register(r"soutenances", DefenseViewSet, basename="soutenance")

urlpatterns = [
    path("login/", LoginView.as_view(), name="login"),
    path("profile/", UserProfileView.as_view(), name="profile"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("token/refresh/", TokenRefreshView.as_view(), name="token-refresh"),

    path("", include(router.urls)),
]