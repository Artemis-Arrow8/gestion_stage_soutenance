from datetime import datetime, timezone as datetime_timezone

from rest_framework.test import APITestCase
from rest_framework import status
from django.urls import reverse
from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import IntegrityError, transaction
from rest_framework_simplejwt.tokens import RefreshToken
from api.models import (
    Assessment,
    Campaign,
    Defense,
    DocumentVersion,
    InternshipFolder,
    Jury,
    JuryMember,
    Room,
    Student,
    StudentAccount,
)

User = get_user_model()

class SGSUSFeaturesTestCase(APITestCase):
    """
    Suite de tests pour valider les endpoints CRUD des Campagnes, 
    des Étudiants et des Dossiers de stage avec gestion des permissions.
    """

    def setUp(self):
        """
        Préparation des données initiales pour les tests de l'application.
        """
        # 1. Données de référence : Campagne
        self.campaign = Campaign.objects.create(
            academic_year="2025-2026",
            is_active=True
        )
        
        # 2. Données de référence : Étudiant
        self.student = Student.objects.create(
            student_number="ETU98765",
            full_name="Hélène Guindo",
            email="helene.guindo@itma.ml"
        )
        self.student_user = User.objects.create_user(
            username="student_test",
            password="student-password",
        )
        StudentAccount.objects.create(user=self.student_user, student=self.student)
        self.jury = Jury.objects.create(name="Jury de test")
        JuryMember.objects.create(
            jury=self.jury,
            member_name="Membre de test",
            role_in_jury="president",
        )
        Room.objects.create(name="Salle A", capacity=30)
        Room.objects.create(name="Salle B", capacity=30)
        
        # 3. Dossier de stage lié
        self.folder = InternshipFolder.objects.create(
            student=self.student,
            campaign=self.campaign,
            company_name="Tech Mali Solutions",
            subject="Développement d'une plateforme de gestion",
            status="recevable"
        )

        # 4. Création d'un utilisateur administrateur pour les tests globaux
        self.admin_user = User.objects.create_user(
            username="admin_test",
            password="password123",
            is_staff=True
        )
        self.admin_user.role = 'admin'
        self.admin_user.save()
        admin_group, _ = Group.objects.get_or_create(name='admin')
        self.admin_user.groups.add(admin_group)

        # URLs des routes DRF
        self.campaign_url = reverse('campaign-list')
        self.student_url = reverse('student-list')
        self.folder_url = reverse('internshipfolder-list')

    def test_get_campaigns_list(self):
        """Vérifie la récupération de la liste des campagnes académiques (200 OK)."""
        self.client.force_authenticate(user=self.admin_user)
        response = self.client.get(self.campaign_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(len(response.data), 1)

    def test_create_campaign(self):
        """Vérifie qu'on peut créer une nouvelle campagne (201 Created)."""
        self.client.force_authenticate(user=self.admin_user)
        payload = {
            "academic_year": "2025-2026",
            "is_active": False
        }
        response = self.client.post(self.campaign_url, payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_get_students_list(self):
        """Vérifie la récupération de la liste des étudiants enregistrés (200 OK)."""
        self.client.force_authenticate(user=self.admin_user)
        response = self.client.get(self.student_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data[0]['student_number'], "ETU98765")

    def test_internship_folder_creation(self):
        """Vérifie la création d'un dossier de stage par un étudiant (nécessite la permission IsStudent)."""
        # Authentification en tant qu'étudiant car InternshipFolderViewSet requiert IsStudent
        self.client.force_authenticate(user=self.student_user)
        
        payload = {
            "student": self.student.id,
            "campaign": self.campaign.id,  
            "company_name": "Orange Mali",
            "subject": "Mise en place d'un système de suivi",
            "status": "brouillon"
        }
        response = self.client.post(self.folder_url, payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_student_cannot_create_a_folder_for_another_student(self):
        """Force l'association du dossier au propriétaire du compte connecté."""
        other_student = Student.objects.create(
            student_number="ETU00000",
            full_name="Autre étudiant",
            email="autre.etudiant@itma.ml",
        )
        self.client.force_authenticate(user=self.student_user)

        response = self.client.post(
            self.folder_url,
            {
                "student": other_student.id,
                "campaign": self.campaign.id,
                "company_name": "Entreprise",
                "subject": "Sujet de stage",
                "status": "brouillon",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["student"], self.student.id)

    def test_student_only_sees_own_folders_and_documents(self):
        """Limite les listes de dossiers et documents à l'étudiant connecté."""
        other_student = Student.objects.create(
            student_number="ETU00000",
            full_name="Autre étudiant",
            email="autre.etudiant@itma.ml",
        )
        other_folder = InternshipFolder.objects.create(
            student=other_student,
            campaign=self.campaign,
            company_name="Entreprise",
            subject="Sujet privé",
            status="brouillon",
        )
        own_document = DocumentVersion.objects.create(
            folder=self.folder,
            version_number=1,
            file_path="own.pdf",
        )
        other_document = DocumentVersion.objects.create(
            folder=other_folder,
            version_number=1,
            file_path="other.pdf",
        )
        access = str(RefreshToken.for_user(self.student_user).access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

        folders = self.client.get(self.folder_url)
        documents = self.client.get(reverse("documentversion-list"))

        self.assertEqual([item["id"] for item in folders.data], [self.folder.id])
        self.assertEqual([item["id"] for item in documents.data], [own_document.id])
        self.assertNotEqual(own_document.id, other_document.id)

    def test_assessment_rejects_grades_above_twenty(self):
        defense = Defense.objects.create(
            folder=self.folder,
            room_name="Salle A",
            slot_range=(
                datetime(2026, 11, 5, 9, tzinfo=datetime_timezone.utc),
                datetime(2026, 11, 5, 10, tzinfo=datetime_timezone.utc),
            ),
            status="planifie",
        )
        self.client.force_authenticate(user=self.admin_user)

        response = self.client.post(
            reverse("assessment-list"),
            {
                "defense": defense.id,
                "report_grade": "20.01",
                "oral_grade": "15.00",
                "final_average": "17.50",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("report_grade", response.data)

    def test_assessment_accepts_grades_between_zero_and_twenty(self):
        defense = Defense.objects.create(
            folder=self.folder,
            room_name="Salle B",
            slot_range=(
                datetime(2026, 11, 5, 10, tzinfo=datetime_timezone.utc),
                datetime(2026, 11, 5, 11, tzinfo=datetime_timezone.utc),
            ),
            status="planifie",
        )
        self.client.force_authenticate(user=self.admin_user)

        response = self.client.post(
            reverse("assessment-list"),
            {
                "defense": defense.id,
                "report_grade": "0.00",
                "oral_grade": "20.00",
                "final_average": "10.00",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Assessment.objects.count(), 1)

    def test_defense_rejects_overlapping_room_booking(self):
        Defense.objects.create(
            folder=self.folder,
            room_name="Salle A",
            slot_range=(
                datetime(2026, 11, 5, 9, tzinfo=datetime_timezone.utc),
                datetime(2026, 11, 5, 10, tzinfo=datetime_timezone.utc),
            ),
        )
        self.client.force_authenticate(user=self.admin_user)

        response = self.client.post(
            reverse("defense-list"),
            {
                "folder": self.folder.id,
                "jury": self.jury.id,
                "room_name": "Salle A",
                "slot_start": "2026-11-05T09:30:00Z",
                "slot_end": "2026-11-05T10:30:00Z",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("room_name", response.data)

    def test_defense_accepts_adjacent_room_bookings(self):
        Defense.objects.create(
            folder=self.folder,
            room_name="Salle A",
            slot_range=(
                datetime(2026, 11, 5, 9, tzinfo=datetime_timezone.utc),
                datetime(2026, 11, 5, 10, tzinfo=datetime_timezone.utc),
            ),
        )
        self.client.force_authenticate(user=self.admin_user)

        response = self.client.post(
            reverse("defense-list"),
            {
                "folder": self.folder.id,
                "jury": self.jury.id,
                "room_name": "Salle A",
                "slot_start": "2026-11-05T10:00:00Z",
                "slot_end": "2026-11-05T11:00:00Z",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_defense_rejects_overlapping_jury_booking(self):
        jury = Jury.objects.create(name="Jury A")
        JuryMember.objects.create(
            jury=jury,
            member_name="Président du jury A",
            role_in_jury="president",
        )
        Defense.objects.create(
            folder=self.folder,
            jury=jury,
            room_name="Salle A",
            slot_range=(
                datetime(2026, 11, 5, 9, tzinfo=datetime_timezone.utc),
                datetime(2026, 11, 5, 10, tzinfo=datetime_timezone.utc),
            ),
        )
        self.client.force_authenticate(user=self.admin_user)

        response = self.client.post(
            reverse("defense-list"),
            {
                "folder": self.folder.id,
                "jury": jury.id,
                "room_name": "Salle B",
                "slot_start": "2026-11-05T09:30:00Z",
                "slot_end": "2026-11-05T10:30:00Z",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("jury", response.data)

    def test_database_rejects_overlapping_room_booking(self):
        Defense.objects.create(
            folder=self.folder,
            room_name="Salle A",
            slot_range=(
                datetime(2026, 11, 5, 9, tzinfo=datetime_timezone.utc),
                datetime(2026, 11, 5, 10, tzinfo=datetime_timezone.utc),
            ),
        )

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Defense.objects.create(
                    folder=self.folder,
                    room_name="Salle A",
                    slot_range=(
                        datetime(2026, 11, 5, 9, 30, tzinfo=datetime_timezone.utc),
                        datetime(2026, 11, 5, 10, 30, tzinfo=datetime_timezone.utc),
                    ),
                )

    def test_database_rejects_overlapping_jury_booking(self):
        jury = Jury.objects.create(name="Jury A")
        Defense.objects.create(
            folder=self.folder,
            jury=jury,
            room_name="Salle A",
            slot_range=(
                datetime(2026, 11, 5, 9, tzinfo=datetime_timezone.utc),
                datetime(2026, 11, 5, 10, tzinfo=datetime_timezone.utc),
            ),
        )

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Defense.objects.create(
                    folder=self.folder,
                    jury=jury,
                    room_name="Salle B",
                    slot_range=(
                        datetime(2026, 11, 5, 9, 30, tzinfo=datetime_timezone.utc),
                        datetime(2026, 11, 5, 10, 30, tzinfo=datetime_timezone.utc),
                    ),
                )