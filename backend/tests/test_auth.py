from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from api.models import (
    Campaign,
    DocumentVersion,
    FolderSupervisor,
    InternshipFolder,
    Jury,
    JuryMember,
    JuryMemberAccount,
    Review,
    Student,
    StudentAccount,
)


User = get_user_model()


class AuthModuleTestCase(APITestCase):
    """Vérifie la connexion, les jetons JWT et les permissions associées."""

    def setUp(self):
        self.campaign = Campaign.objects.create(
            academic_year="2025-2026",
            is_active=True,
        )
        self.student = Student.objects.create(
            student_number="ETU12345",
            full_name="Kadiatou Guindo",
            email="kadiatou.guindo@itma.ml",
        )
        self.student_user = User.objects.create_user(
            username="ETU12345",
            password="student-password",
        )
        StudentAccount.objects.create(user=self.student_user, student=self.student)

        self.django_user = User.objects.create_user(
            username="admin_user",
            password="admin-password",
            is_staff=True,
        )
        self.django_user.role = "admin"
        admin_group, _ = Group.objects.get_or_create(name="admin")
        self.django_user.groups.add(admin_group)

        self.login_url = reverse("api-login")
        self.campaign_list_url = reverse("campaign-list")
        self.student_list_url = reverse("student-list")
        self.folder_list_url = reverse("internshipfolder-list")
        self.review_list_url = reverse("review-list")

    def test_login_success_returns_jwt_tokens(self):
        response = self.client.post(
            self.login_url,
            {"username": "ETU12345", "password": "student-password"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["user"]["student_number"], "ETU12345")
        self.assertTrue(response.data["access"])
        self.assertTrue(response.data["refresh"])

    def test_refresh_endpoint_returns_new_access_token(self):
        login = self.client.post(
            self.login_url,
            {"username": "ETU12345", "password": "student-password"},
            format="json",
        )

        response = self.client.post(
            reverse("token-refresh"),
            {"refresh": login.data["refresh"]},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["access"])

    def test_login_rejects_incorrect_password(self):
        response = self.client.post(
            self.login_url,
            {"username": "ETU12345", "password": "incorrect"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_rejects_unknown_account(self):
        response = self.client.post(
            self.login_url,
            {"username": "INCONNU999", "password": "password123"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_requires_both_credentials(self):
        response = self.client.post(
            self.login_url,
            {"username": ""},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_login_accepts_administrator_without_student_profile(self):
        response = self.client.post(
            self.login_url,
            {"username": "admin_user", "password": "admin-password"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["user"]["role"], "admin")

    def test_login_rejects_account_without_an_sgsus_role(self):
        User.objects.create_user(
            username="unassigned_account",
            password="Sgsus-Account!2026",
        )

        response = self.client.post(
            self.login_url,
            {"username": "unassigned_account", "password": "Sgsus-Account!2026"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_permission(self):
        self.client.force_authenticate(user=self.django_user)
        response = self.client.get(self.campaign_list_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_responsible_permission_uses_django_group(self):
        responsible = User.objects.create_user(
            username="responsible_user",
            password="responsible-password",
        )
        responsible.groups.add(Group.objects.create(name="responsible"))
        self.client.force_authenticate(user=responsible)

        response = self.client.get(self.campaign_list_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_student_permission_for_existing_student_object(self):
        self.client.force_authenticate(user=self.student)
        response = self.client.get(self.folder_list_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_supervisor_permission(self):
        supervisor = User.objects.create_user(
            username="supervisor_user",
            password="supervisor-password",
        )
        supervisor.groups.add(Group.objects.create(name="supervisor"))
        self.client.force_authenticate(user=supervisor)

        response = self.client.get(self.review_list_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_supervisor_can_only_read_and_create_their_own_reviews(self):
        supervisor = User.objects.create_user(
            username="review_author",
            password="Sgsus-Account!2026",
        )
        other_supervisor = User.objects.create_user(
            username="other_review_author",
            password="Sgsus-Account!2026",
        )
        supervisor.groups.add(Group.objects.get_or_create(name="supervisor")[0])
        other_supervisor.groups.add(
            Group.objects.get_or_create(name="supervisor")[0]
        )
        document = DocumentVersion.objects.create(
            folder=InternshipFolder.objects.create(
                student=self.student,
                campaign=self.campaign,
                company_name="Entreprise",
                subject="Dossier de test",
            ),
            version_number=1,
            file_path="rapport.pdf",
        )
        FolderSupervisor.objects.create(
            user=supervisor,
            folder=document.folder,
        )
        existing_review = Review.objects.create(
            document_version=document,
            author=supervisor,
            author_role="encadreur",
            decision="favorable",
        )
        Review.objects.create(
            document_version=document,
            author=other_supervisor,
            author_role="encadreur",
            decision="favorable",
        )
        self.client.force_authenticate(user=supervisor)

        listing = self.client.get(self.review_list_url)
        created = self.client.post(
            self.review_list_url,
            {
                "document_version": document.pk,
                "author": other_supervisor.pk,
                "author_role": "tuteur",
                "decision": "favorable",
                "comments": "Avis de suivi",
            },
            format="json",
        )
        updated_role = self.client.patch(
            reverse("review-detail", args=[created.data["id"]]),
            {"author_role": "tuteur"},
            format="json",
        )

        self.assertEqual(listing.status_code, status.HTTP_200_OK)
        self.assertEqual([item["id"] for item in listing.data], [existing_review.pk])
        self.assertEqual(created.status_code, status.HTTP_201_CREATED)
        self.assertEqual(created.data["author"], supervisor.pk)
        self.assertEqual(created.data["author_role"], "encadreur")
        self.assertEqual(updated_role.status_code, status.HTTP_200_OK)
        self.assertEqual(updated_role.data["author_role"], "encadreur")

    def test_supervisor_ne_voit_que_les_dossiers_et_documents_affectes(self):
        supervisor = User.objects.create_user(
            username="assigned_supervisor",
            password="Sgsus-Account!2026",
        )
        supervisor.groups.add(Group.objects.get_or_create(name="supervisor")[0])
        dossier_affecte = InternshipFolder.objects.create(
            student=self.student,
            campaign=self.campaign,
            company_name="Entreprise affectée",
            subject="Dossier affecté",
        )
        autre_etudiant = Student.objects.create(
            student_number="ETU54321",
            full_name="Autre étudiant",
            email="autre.etudiant@itma.ml",
        )
        dossier_prive = InternshipFolder.objects.create(
            student=autre_etudiant,
            campaign=self.campaign,
            company_name="Entreprise privée",
            subject="Dossier non affecté",
        )
        document_affecte = DocumentVersion.objects.create(
            folder=dossier_affecte,
            version_number=1,
            file_path="affecte.pdf",
        )
        DocumentVersion.objects.create(
            folder=dossier_prive,
            version_number=1,
            file_path="prive.pdf",
        )
        FolderSupervisor.objects.create(
            user=supervisor,
            folder=dossier_affecte,
        )
        self.client.force_authenticate(user=supervisor)

        dossiers = self.client.get(self.folder_list_url)
        documents = self.client.get(reverse("documentversion-list"))
        detail_prive = self.client.get(
            reverse("internshipfolder-detail", args=[dossier_prive.pk])
        )
        avis_interdit = self.client.post(
            self.review_list_url,
            {
                "document_version": DocumentVersion.objects.get(
                    folder=dossier_prive
                ).pk,
                "decision": "favorable",
            },
            format="json",
        )

        self.assertEqual(dossiers.status_code, status.HTTP_200_OK)
        self.assertEqual([item["id"] for item in dossiers.data], [dossier_affecte.pk])
        self.assertEqual(documents.status_code, status.HTTP_200_OK)
        self.assertEqual(
            [item["id"] for item in documents.data],
            [document_affecte.pk],
        )
        self.assertEqual(detail_prive.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(avis_interdit.status_code, status.HTTP_403_FORBIDDEN)

    def test_protected_endpoint_rejects_missing_authorization(self):
        response = self.client.get(self.student_list_url)

        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_protected_endpoint_rejects_non_bearer_authorization(self):
        self.client.credentials(HTTP_AUTHORIZATION="Basic dXNlcjpwYXNz")

        response = self.client.get(self.student_list_url)

        self.assertIn(
            response.status_code,
            [status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN],
        )

    def test_student_jwt_is_accepted_for_student_endpoint(self):
        own_folder = InternshipFolder.objects.create(
            student=self.student,
            campaign=self.campaign,
            company_name="Entreprise personnelle",
            subject="Dossier personnel",
        )
        other_student = Student.objects.create(
            student_number="ETU54321",
            full_name="Autre étudiant",
            email="autre@itma.ml",
        )
        InternshipFolder.objects.create(
            student=other_student,
            campaign=self.campaign,
            company_name="Autre entreprise",
            subject="Dossier privé",
        )
        access = str(RefreshToken.for_user(self.student_user).access_token)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

        response = self.client.get(self.folder_list_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([folder["id"] for folder in response.data], [own_folder.id])

    def test_student_cannot_mark_a_folder_receivable_or_edit_another_student_folder(self):
        other_student = Student.objects.create(
            student_number="ETU67890",
            full_name="Étudiant tiers",
            email="tiers@itma.ml",
        )
        other_folder = InternshipFolder.objects.create(
            student=other_student,
            campaign=self.campaign,
            company_name="Entreprise tierce",
            subject="Dossier privé",
            status="brouillon",
        )
        self.client.force_authenticate(user=self.student_user)

        created = self.client.post(
            self.folder_list_url,
            {
                "student": other_student.pk,
                "campaign": self.campaign.pk,
                "company_name": "Entreprise personnelle",
                "subject": "Dossier personnel",
                "status": "recevable",
            },
            format="json",
        )
        update_other = self.client.patch(
            reverse("internshipfolder-detail", args=[other_folder.pk]),
            {"status": "recevable"},
            format="json",
        )

        self.assertEqual(created.status_code, status.HTTP_201_CREATED)
        self.assertEqual(created.data["student"], self.student.pk)
        self.assertEqual(created.data["status"], "brouillon")
        self.assertEqual(update_other.status_code, status.HTTP_404_NOT_FOUND)

    def test_django_user_can_access_admin_endpoint(self):
        self.client.force_authenticate(user=self.django_user)

        response = self.client.get(self.student_list_url)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_invalid_bearer_token_is_rejected(self):
        self.client.credentials(HTTP_AUTHORIZATION="Bearer jeton-invalide")

        response = self.client.get(self.student_list_url)

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_jwt_for_deleted_user_is_rejected(self):
        access = str(RefreshToken.for_user(self.django_user).access_token)
        self.django_user.delete()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

        response = self.client.get(self.student_list_url)

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_returns_the_role_for_each_staff_account_type(self):
        for username, role in (
            ("responsible_user_login", "responsible"),
            ("supervisor_user_login", "supervisor"),
        ):
            with self.subTest(role=role):
                account = User.objects.create_user(
                    username=username,
                    password="Sgsus-Account!2026",
                )
                group, _ = Group.objects.get_or_create(name=role)
                account.groups.add(group)

                response = self.client.post(
                    self.login_url,
                    {"username": username, "password": "Sgsus-Account!2026"},
                    format="json",
                )

                self.assertEqual(response.status_code, status.HTTP_200_OK)
                self.assertEqual(response.data["user"]["role"], role)

    def test_login_rejects_inactive_account(self):
        self.student_user.is_active = False
        self.student_user.save(update_fields=["is_active"])

        response = self.client.post(
            self.login_url,
            {"username": "ETU12345", "password": "student-password"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_jwt_for_inactive_account_is_rejected(self):
        access = str(RefreshToken.for_user(self.student_user).access_token)
        self.student_user.is_active = False
        self.student_user.save(update_fields=["is_active"])

        response = self.client.get(
            self.folder_list_url,
            HTTP_AUTHORIZATION=f"Bearer {access}",
        )

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_logout_revokes_the_refresh_token(self):
        login = self.client.post(
            self.login_url,
            {"username": "ETU12345", "password": "student-password"},
            format="json",
        )
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {login.data['access']}"
        )

        logout = self.client.post(
            reverse("api-logout"),
            {"refresh": login.data["refresh"]},
            format="json",
        )
        refresh = self.client.post(
            reverse("token-refresh"),
            {"refresh": login.data["refresh"]},
            format="json",
        )

        self.assertEqual(logout.status_code, status.HTTP_200_OK)
        self.assertEqual(refresh.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_logout_rejects_another_users_refresh_token(self):
        student_login = self.client.post(
            self.login_url,
            {"username": "ETU12345", "password": "student-password"},
            format="json",
        )
        admin_login = self.client.post(
            self.login_url,
            {"username": "admin_user", "password": "admin-password"},
            format="json",
        )
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {student_login.data['access']}"
        )

        response = self.client.post(
            reverse("api-logout"),
            {"refresh": admin_login.data["refresh"]},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_profile_returns_only_the_authenticated_user(self):
        access = str(RefreshToken.for_user(self.student_user).access_token)
        response = self.client.get(
            reverse("api-profile"),
            HTTP_AUTHORIZATION=f"Bearer {access}",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["user"]["student_number"], "ETU12345")
        self.assertEqual(response.data["user"]["role"], "student")

    def test_student_reads_only_reviews_for_their_documents(self):
        own_folder = InternshipFolder.objects.create(
            student=self.student,
            campaign=self.campaign,
            company_name="Entreprise personnelle",
            subject="Mon dossier",
        )
        other_student = Student.objects.create(
            student_number="ETU67890",
            full_name="Autre étudiant",
            email="autre.etudiant@itma.ml",
        )
        other_folder = InternshipFolder.objects.create(
            student=other_student,
            campaign=self.campaign,
            company_name="Autre entreprise",
            subject="Dossier privé",
        )
        own_document = DocumentVersion.objects.create(
            folder=own_folder,
            version_number=1,
            file_path="own-report.pdf",
        )
        other_document = DocumentVersion.objects.create(
            folder=other_folder,
            version_number=1,
            file_path="other-report.pdf",
        )
        own_review = Review.objects.create(
            document_version=own_document,
            author_role="encadreur",
            decision="favorable",
        )
        Review.objects.create(
            document_version=other_document,
            author_role="encadreur",
            decision="favorable",
        )
        self.client.force_authenticate(user=self.student_user)

        response = self.client.get(self.review_list_url)
        filtered = self.client.get(
            self.review_list_url,
            {"document_version_id": own_document.pk},
        )
        invalid_filter = self.client.get(
            self.review_list_url,
            {"document_version_id": "invalide"},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([item["id"] for item in response.data], [own_review.pk])
        self.assertEqual(filtered.status_code, status.HTTP_200_OK)
        self.assertEqual([item["id"] for item in filtered.data], [own_review.pk])
        self.assertEqual(invalid_filter.status_code, status.HTTP_400_BAD_REQUEST)

    def test_role_permissions_are_isolated_by_endpoint(self):
        responsible = User.objects.create_user(
            username="responsible_matrix",
            password="Sgsus-Account!2026",
        )
        supervisor = User.objects.create_user(
            username="supervisor_matrix",
            password="Sgsus-Account!2026",
        )
        responsible.groups.add(Group.objects.get_or_create(name="responsible")[0])
        supervisor.groups.add(Group.objects.get_or_create(name="supervisor")[0])

        endpoints = (
            (self.campaign_list_url, self.django_user, status.HTTP_200_OK),
            (self.campaign_list_url, responsible, status.HTTP_200_OK),
            (self.campaign_list_url, self.student_user, status.HTTP_403_FORBIDDEN),
            (self.campaign_list_url, supervisor, status.HTTP_403_FORBIDDEN),
            (self.review_list_url, self.django_user, status.HTTP_200_OK),
            (self.review_list_url, supervisor, status.HTTP_200_OK),
            (self.review_list_url, responsible, status.HTTP_403_FORBIDDEN),
            (self.review_list_url, self.student_user, status.HTTP_200_OK),
            (self.folder_list_url, self.student_user, status.HTTP_200_OK),
            (self.folder_list_url, self.django_user, status.HTTP_200_OK),
            (self.folder_list_url, responsible, status.HTTP_200_OK),
            (self.folder_list_url, supervisor, status.HTTP_200_OK),
            (reverse("documentversion-list"), self.student_user, status.HTTP_200_OK),
            (reverse("documentversion-list"), responsible, status.HTTP_200_OK),
            (reverse("documentversion-list"), supervisor, status.HTTP_200_OK),
        )
        for url, user, expected_status in endpoints:
            with self.subTest(url=url, username=user.username):
                self.client.force_authenticate(user=user)
                self.assertEqual(
                    self.client.get(url).status_code,
                    expected_status,
                )

    def test_only_administrators_can_manage_accounts(self):
        responsible = User.objects.create_user(
            username="responsible_accounts",
            password="Sgsus-Account!2026",
        )
        responsible.groups.add(Group.objects.get_or_create(name="responsible")[0])
        self.client.force_authenticate(user=responsible)

        response = self.client.get(reverse("account-list"))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_staff_flag_alone_does_not_grant_administrator_api_access(self):
        staff_user = User.objects.create_user(
            username="staff_without_sgsus_role",
            password="Sgsus-Account!2026",
            is_staff=True,
        )
        self.client.force_authenticate(user=staff_user)

        response = self.client.get(self.student_list_url)

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_administrator_can_create_and_list_a_student_account(self):
        student = Student.objects.create(
            student_number="ETU77777",
            full_name="Étudiant créé",
            email="etu77777@example.test",
        )
        self.client.force_authenticate(user=self.django_user)

        created = self.client.post(
            reverse("account-list"),
            {
                "username": "ETU77777",
                "email": "etu77777@example.test",
                "password": "Strong-Passphrase!2026",
                "role": "student",
                "student_id": student.pk,
            },
            format="json",
        )
        listed = self.client.get(reverse("account-list"))

        self.assertEqual(created.status_code, status.HTTP_201_CREATED)
        self.assertNotIn("password", created.data)
        self.assertEqual(created.data["role"], "student")
        self.assertEqual(created.data["student_profile"]["id"], student.pk)
        self.assertEqual(listed.status_code, status.HTTP_200_OK)

    def test_administrator_account_can_access_django_admin_without_superuser(self):
        self.client.force_authenticate(user=self.django_user)

        response = self.client.post(
            reverse("account-list"),
            {
                "username": "api_admin_account",
                "password": "Strong-Passphrase!2026",
                "role": "admin",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        account = User.objects.get(username="api_admin_account")
        self.assertTrue(account.is_staff)
        self.assertFalse(account.is_superuser)

    def test_business_administrator_cannot_view_superuser_accounts(self):
        superuser = User.objects.create_superuser(
            username="protected_superuser",
            email="protected@example.test",
            password="Strong-Passphrase!2026",
        )
        self.client.force_authenticate(user=self.django_user)

        listing = self.client.get(reverse("account-list"))
        detail = self.client.get(
            reverse("account-detail", args=[superuser.pk])
        )

        self.assertEqual(listing.status_code, status.HTTP_200_OK)
        self.assertNotIn(
            superuser.pk,
            [account["id"] for account in listing.data],
        )
        self.assertEqual(detail.status_code, status.HTTP_404_NOT_FOUND)

    def test_administrator_can_create_a_scoped_jury_account(self):
        jury = Jury.objects.create(name="Jury authentifié", is_complete=True)
        member = JuryMember.objects.create(
            jury=jury,
            member_name="Membre authentifié",
            role_in_jury="president",
        )
        self.client.force_authenticate(user=self.django_user)

        response = self.client.post(
            reverse("account-list"),
            {
                "username": "jury_account",
                "password": "Strong-Passphrase!2026",
                "role": "jury",
                "jury_member_id": member.pk,
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["role"], "jury")
        self.assertEqual(response.data["jury_profile"]["id"], member.pk)
        user = User.objects.get(username="jury_account")
        self.assertEqual(
            JuryMemberAccount.objects.get(user=user).jury_member_id,
            member.pk,
        )
        login = self.client.post(
            self.login_url,
            {
                "username": "jury_account",
                "password": "Strong-Passphrase!2026",
            },
            format="json",
        )
        self.assertEqual(login.status_code, status.HTTP_200_OK)
        self.assertEqual(login.data["user"]["role"], "jury")
        self.assertEqual(login.data["user"]["jury_id"], jury.pk)

    def test_jury_role_requires_a_linked_jury_member(self):
        self.client.force_authenticate(user=self.django_user)

        response = self.client.post(
            reverse("account-list"),
            {
                "username": "jury_without_assignment",
                "password": "Strong-Passphrase!2026",
                "role": "jury",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("jury_member_id", response.data)

    def test_account_creation_rejects_weak_passwords(self):
        self.client.force_authenticate(user=self.django_user)

        response = self.client.post(
            reverse("account-list"),
            {
                "username": "weak_password_user",
                "password": "123",
                "role": "responsible",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.data)

    def test_administrator_can_change_role_and_deactivate_account(self):
        account = User.objects.create_user(
            username="account_to_update",
            password="Old-Passphrase!2026",
        )
        account.groups.add(Group.objects.get_or_create(name="responsible")[0])
        self.client.force_authenticate(user=self.django_user)

        response = self.client.patch(
            reverse("account-detail", args=[account.pk]),
            {"role": "supervisor", "is_active": False},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["role"], "supervisor")
        self.assertFalse(response.data["is_active"])
        account.refresh_from_db()
        self.assertFalse(account.is_active)
        self.assertEqual(
            list(account.groups.values_list("name", flat=True)),
            ["supervisor"],
        )

        disabled_login = self.client.post(
            self.login_url,
            {"username": "account_to_update", "password": "Old-Passphrase!2026"},
            format="json",
        )
        reactivated = self.client.patch(
            reverse("account-detail", args=[account.pk]),
            {"is_active": True},
            format="json",
        )
        active_login = self.client.post(
            self.login_url,
            {"username": "account_to_update", "password": "Old-Passphrase!2026"},
            format="json",
        )

        self.assertEqual(disabled_login.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(reactivated.status_code, status.HTTP_200_OK)
        self.assertTrue(reactivated.data["is_active"])
        self.assertEqual(active_login.status_code, status.HTTP_200_OK)

    def test_administrator_cannot_deactivate_own_account(self):
        self.client.force_authenticate(user=self.django_user)

        response = self.client.patch(
            reverse("account-detail", args=[self.django_user.pk]),
            {"is_active": False},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
