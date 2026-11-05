# Authentification et rôles SGSUS

## Identités et rôles

Les comptes sont des utilisateurs Django ; aucun second modèle utilisateur n’est créé. Les quatre rôles reconnus sont `admin`, `student`, `supervisor` et `responsible`, stockés dans les groupes Django correspondants. Un compte étudiant doit en plus être relié à une fiche existante par `StudentAccount`. Un superutilisateur reçoit le rôle `admin`. Le seul indicateur `is_staff` ne donne pas les permissions API d’administration.

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
| `POST /accounts/` | Administrateur | Crée un compte et son rôle ; `student_id` est obligatoire pour le rôle étudiant. |
| `PUT/PATCH /accounts/{id}/` | Administrateur | Modifie le compte, son rôle, son activation ou son mot de passe. |

Une création de compte envoie `username`, `password`, `role`, et selon le cas `student_id`, ainsi que les champs facultatifs `email`, `first_name` et `last_name`. La réponse ne contient jamais de mot de passe. Les valeurs de `role` sont limitées aux quatre rôles ci-dessus.

## Autorisations métier

| Rôle | Accès API |
|---|---|
| Administrateur | Gestion des comptes ; accès à tous les endpoints métier. |
| Responsable pédagogique | Campagnes, étudiants, dossiers, versions de documents, jurys, soutenances et évaluations. |
| Étudiant | Lecture et gestion de ses propres dossiers et versions de documents ; les vues filtrent les fiches par étudiant lié. |
| Encadreur | Création et consultation de ses propres avis (`reviews`). |

Les listes et détails de dossiers, documents et avis d’encadrement sont filtrés côté serveur. Les avis historiques dont l’auteur n’était pas enregistré restent consultables par un administrateur, mais ne sont pas exposés aux comptes encadreurs. Les comptes non authentifiés et inactifs ne sont pas autorisés. La gestion des comptes est réservée au rôle `admin`.

## Jetons et client Flutter

Le jeton d’accès expire après cinq minutes ; le jeton de renouvellement expire après un jour, tourne à chaque renouvellement et l’ancien est placé en liste noire. La déconnexion révoque le jeton de renouvellement, mais un jeton d’accès déjà délivré reste valide jusqu’à son expiration (au plus cinq minutes). Les contrôles d’activité et de rôle sont effectués côté API.

Flutter conserve les jetons avec `flutter_secure_storage`, vérifie `/profile/` à l’ouverture et tente un renouvellement lorsque le jeton d’accès a expiré. Si la révocation distante échoue, l’application efface quand même les jetons locaux et affiche un avertissement. En production, utiliser HTTPS.

L’application affiche un tableau de bord différent pour chacun des quatre rôles. Les cartes de modules indiquent explicitement « Module non intégré » : elles sont informatives et ne naviguent pas encore, car les écrans métier correspondants ne sont pas raccordés dans cette partie. La seule action de module actuellement opérationnelle est la déconnexion. Il n’existe pas de routes Flutter nommées pour ces modules ; l’écran d’accueil est protégé par la vérification de session et le tableau de bord refuse un profil absent ou inconnu.

Les tests Flutter vérifient les quatre associations rôle/tableau de bord, le garde d’accès sans session, l’absence actuelle de routes métier nommées, la déconnexion et la restauration des jetons après recréation du widget d’application. Le test unitaire de `SecureAuthStorage` utilise la plateforme simulée fournie par le plugin et confirme les clés, la lecture, l’écriture et la suppression, mais ne valide pas le chiffrement natif. Le test `integration_test/secure_storage_test.dart` exerce le plugin natif avec des clés temporaires isolées; il doit être lancé sur un appareil Android ou iOS et n’a pas été exécuté dans cet environnement faute d’appareil connecté. Les tests de parcours d’authentification continuent d’utiliser un dépôt HTTP simulé et un stockage mémoire : ils vérifient les réactions de l’interface, pas une connexion réelle à Django.

La migration des tables de liste noire SimpleJWT doit être appliquée avec `python manage.py migrate` ; elle ajoute les tables de jetons révoqués sans réinitialiser les tables métier.
