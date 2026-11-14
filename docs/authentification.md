# Authentification et rôles SGSUS

## Identités et rôles

Les comptes sont des utilisateurs Django ; aucun second modèle utilisateur n’est créé. Les rôles reconnus sont `admin`, `student`, `supervisor`, `responsible` et `jury`. Un compte étudiant est relié à une fiche par `StudentAccount` ; un compte jury est relié à un seul membre par `JuryMemberAccount`. Un superutilisateur reçoit le rôle `admin`. Le seul indicateur `is_staff` ne donne pas les permissions API d’administration.

Les rôles des comptes non étudiants sont affectés depuis l’API d’administration des comptes ou depuis les groupes Django. La gestion API ne permet pas de créer de superutilisateur ni de supprimer un compte. Les mots de passe sont hachés par Django et passent par ses validateurs.

## Routes

Toutes les routes sont préfixées par `/api/`.

| Méthode et route | Accès | Résultat |
|---|---|---|
| `POST /login/` | Public | Vérifie identifiant, mot de passe, compte actif et rôle ; retourne `user`, `access` et `refresh`. |
| `POST /token/refresh/` | Public avec jeton de renouvellement | Renouvelle le jeton d’accès et fait tourner le jeton de renouvellement. |
| `POST /logout/` | JWT d’accès valide | Révoque le jeton de renouvellement du compte connecté. |
| `GET /profile/` | JWT d’accès valide | Retourne uniquement le profil du compte connecté sous la clé `user`. |
| `GET /accounts/`, `GET /accounts/{id}/` | Administrateur | Consulte les comptes et leurs profils étudiants minimaux. |
| `POST /accounts/` | Administrateur | Crée un compte et son rôle ; `student_id` ou `jury_member_id` est obligatoire pour les rôles correspondants. |
| `PUT/PATCH /accounts/{id}/` | Administrateur | Modifie le compte, son rôle, son activation ou son mot de passe. |

Une création de compte envoie `username`, `password`, `role`, et selon le cas `student_id` ou `jury_member_id`, ainsi que les champs facultatifs `email`, `first_name` et `last_name`. La réponse ne contient jamais de mot de passe. Les valeurs de `role` sont limitées aux cinq rôles ci-dessus. Un membre de jury ne peut être associé qu’à un seul compte.

## Autorisations métier

| Rôle | Accès API |
|---|---|
| Administrateur | Gestion des comptes ; accès à tous les endpoints métier. |
| Responsable pédagogique | Campagnes, étudiants, dossiers, versions de documents, jurys, soutenances et évaluations. |
| Étudiant | Lecture et gestion de ses propres dossiers et versions de documents ; les vues filtrent les fiches par étudiant lié. |
| Encadreur | Lecture des dossiers et documents qui lui sont affectés ; création et consultation de ses avis sur ces seuls dossiers. |
| Membre du jury | Lecture des informations et soutenances du jury auquel son compte est lié. Les écritures restent réservées au personnel habilité. |

Les listes et détails de dossiers, documents et avis d’encadrement sont filtrés côté serveur. Les affectations encadreur–dossier sont gérées depuis l’administration Django (`FolderSupervisor`) ; un encadreur sans affectation ne voit aucun dossier et ne peut pas déposer d’avis. Les avis historiques dont l’auteur n’était pas enregistré restent consultables par un administrateur, mais ne sont pas exposés aux comptes encadreurs. Les comptes non authentifiés et inactifs ne sont pas autorisés. La gestion des comptes est réservée au rôle `admin`.

## Jetons et client Flutter

Le jeton d’accès expire après cinq minutes ; le jeton de renouvellement expire après un jour, tourne à chaque renouvellement et l’ancien est placé en liste noire. La déconnexion révoque le jeton de renouvellement, mais un jeton d’accès déjà délivré reste valide jusqu’à son expiration (au plus cinq minutes). Les contrôles d’activité et de rôle sont effectués côté API.

Flutter conserve les jetons avec `flutter_secure_storage`, vérifie `/profile/` à l’ouverture et tente un renouvellement lorsque le jeton d’accès a expiré. Si la révocation distante échoue, l’application efface quand même les jetons locaux et affiche un avertissement. En production, utiliser HTTPS.

Le tableau de bord adapte les modules au rôle connecté. Les étudiants et responsables accèdent à la gestion documentaire ; les responsables et membres du jury accèdent au planning. Les écrans planning et création de soutenance communiquent avec l’API ; toute réservation est revalidée par le serveur. Les écrans de gestion des campagnes, des comptes et des affectations d’encadrement ne sont pas encore intégrés.

Les tests Flutter vérifient les rôles, le garde d’accès sans session, la déconnexion, la restauration et le renouvellement des jetons. Les requêtes documentaires et de planning réessaient une fois après un 401 si le renouvellement réussit. Le test unitaire de `SecureAuthStorage` utilise la plateforme simulée fournie par le plugin et confirme les clés, la lecture, l’écriture et la suppression, mais ne valide pas le chiffrement natif. Le test `integration_test/secure_storage_test.dart` exerce le plugin natif avec des clés temporaires isolées ; il doit être lancé sur un appareil Android ou iOS et n’a pas été exécuté dans cet environnement faute d’appareil connecté. Les tests de parcours d’authentification continuent d’utiliser un dépôt HTTP simulé et un stockage mémoire : ils vérifient les réactions de l’interface, pas une connexion réelle à Django.

La migration des tables de liste noire SimpleJWT doit être appliquée avec `python manage.py migrate` ; elle ajoute les tables de jetons révoqués sans réinitialiser les tables métier.
