/// État de session de l'application (authentification JWT).
///
/// [AuthProvider] est l'unique source de vérité de la session :
/// jetons, profil de l'utilisateur, rôle, états de chargement et d'erreur.
/// Il fournit aussi le client HTTP authentifié [AuthProvider.api] utilisé
/// par tous les services métier : le jeton courant y est injecté
/// automatiquement et renouvelé en cas d'expiration.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/network/api_service.dart';
import '../core/storage/auth_storage.dart';
import '../services/auth_service.dart';
import 'planning_store.dart';

/// Fournisseur d'état de la session, à placer en haut de l'arbre de widgets.
class AuthProvider extends ChangeNotifier {
  /// Crée le fournisseur.
  ///
  /// Toutes les dépendances sont injectables pour les tests :
  /// * [authService] : appels aux routes d'authentification ;
  /// * [storage] : persistance des jetons ;
  /// * [httpClient] : client HTTP du client authentifié [api].
  AuthProvider({
    AuthService? authService,
    AuthStorage? storage,
    http.Client? httpClient,
  }) : _authService = authService ?? AuthService(),
       _storage = storage ?? SecureAuthStorage() {
    // Le client lit toujours le jeton courant et déclenche
    // [refreshAccessToken] après une réponse 401.
    api = ApiService(
      client: httpClient,
      accessTokenProvider: () => _accessToken,
      refreshAccessToken: refreshAccessToken,
    );
  }

  final AuthService _authService;
  final AuthStorage _storage;

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  bool _isRestoring = false;
  String? _errorMessage;

  /// Renouvellement en cours, partagé entre requêtes concurrentes.
  Future<bool>? _pendingRefresh;

  /// Client HTTP authentifié, partagé par tous les services métier.
  late final ApiService api;

  // ---------------------------------------------------------------------
  // Lecture de l'état
  // ---------------------------------------------------------------------

  /// Jeton d'accès courant (ou `null` hors session).
  String? get accessToken => _accessToken;

  /// Jeton de renouvellement courant (ou `null` hors session).
  String? get refreshToken => _refreshToken;

  /// Profil renvoyé par l'API (`id`, `username`, `full_name`, `role`…).
  Map<String, dynamic>? get user => _user;

  /// Vrai pendant une opération (connexion, chargement du profil…).
  bool get isLoading => _isLoading;

  /// Vrai pendant la restauration de session au lancement de l'application.
  bool get isRestoring => _isRestoring;

  /// Dernier message d'erreur affichable (ou `null`).
  String? get errorMessage => _errorMessage;

  /// Vrai si une session est ouverte.
  bool get isAuthenticated => _accessToken != null;

  /// Rôle SGSUS de l'utilisateur (admin, responsible, supervisor, jury,
  /// student) ou `null`.
  String? get role => _user?['role'] ?? _user?['group'];

  /// Vrai pour les rôles qui administrent le planning (admin, responsable).
  bool get canManage => role == 'admin' || role == 'responsible';

  /// Nom à afficher : nom complet, sinon identifiant, sinon « Utilisateur ».
  String get displayName {
    final fullName = _user?['full_name']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final username = _user?['username']?.toString().trim() ?? '';
    return username.isNotEmpty ? username : 'Utilisateur';
  }

  /// Libellé français d'un rôle technique (ex. `responsible`).
  static String roleLabel(String? role) => switch (role) {
    'admin' => 'Administrateur',
    'responsible' => 'Responsable pédagogique',
    'supervisor' => 'Encadreur',
    'jury' => 'Membre du jury',
    'student' => 'Étudiant',
    _ => 'Utilisateur',
  };

  // ---------------------------------------------------------------------
  // Cycle de vie de la session
  // ---------------------------------------------------------------------

  /// Restaure une session enregistrée au lancement de l'application.
  ///
  /// Si le jeton d'accès a expiré, il est renouvelé une fois avant de
  /// recharger le profil. En cas d'échec, la session locale est effacée et
  /// l'utilisateur retrouve l'écran de connexion.
  Future<void> restoreSession() async {
    _isRestoring = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _accessToken = await _storage.readAccessToken();
      _refreshToken = await _storage.readRefreshToken();

      // Jeton d'accès perdu mais renouvellement possible.
      if (_accessToken == null && _refreshToken != null) {
        if (!await refreshAccessToken()) return;
      }
      if (_accessToken != null) {
        _user = await _loadProfileWithRetry();
      }
    } on ApiException catch (error) {
      _errorMessage = error.message;
      await clearSession();
    } on FormatException catch (error) {
      _errorMessage = error.message;
      await clearSession();
    } catch (_) {
      _errorMessage = 'Impossible de restaurer la session.';
      await clearSession();
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  /// Authentifie l'utilisateur et ouvre la session.
  ///
  /// Retourne `true` en cas de succès ; sinon [errorMessage] explique la
  /// cause (identifiants incorrects, serveur injoignable…).
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authService.login(username.trim(), password);
      final access = response['access'];
      final refresh = response['refresh'];
      final profile = response['user'];
      // Contrat de réponse vérifié avant toute écriture locale.
      if (access is! String ||
          access.isEmpty ||
          refresh is! String ||
          refresh.isEmpty ||
          profile is! Map) {
        throw const FormatException(
          'Le serveur a renvoyé une réponse de connexion invalide.',
        );
      }

      await _saveTokens(access, refresh);
      _user = Map<String, dynamic>.from(profile);
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      await clearSession();
      return false;
    } on FormatException catch (error) {
      _errorMessage = error.message;
      await clearSession();
      return false;
    } catch (_) {
      _errorMessage = 'Identifiants invalides ou erreur de connexion.';
      await clearSession();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Renouvelle le jeton d'accès à partir du jeton de renouvellement.
  ///
  /// Les appels simultanés partagent la même requête : avec la rotation et
  /// la liste noire activées côté serveur, deux renouvellements parallèles
  /// invalideraient sinon la session. Retourne `true` en cas de succès ;
  /// en cas d'échec, la session est fermée.
  Future<bool> refreshAccessToken() {
    return _pendingRefresh ??= _doRefresh().whenComplete(() {
      _pendingRefresh = null;
    });
  }

  /// Recharge le profil (après une modification de compte, par exemple).
  Future<void> fetchUserProfile() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _user = await _loadProfileWithRetry();
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } on FormatException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Impossible de récupérer le profil utilisateur.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Change le mot de passe du compte connecté.
  ///
  /// Lève une [ApiException] au message explicite si le mot de passe
  /// actuel est faux ou si le nouveau ne respecte pas les règles de
  /// sécurité du serveur. La session en cours reste ouverte.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    await api.post('profile/password/', {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  /// Ferme la session : révocation distante du jeton, puis effacement local.
  ///
  /// La déconnexion locale a toujours lieu, même si le serveur est
  /// injoignable ; un message signale alors l'échec de la révocation.
  Future<void> logout() async {
    String? logoutError;
    final access = _accessToken;
    final refresh = _refreshToken;
    if (access != null && refresh != null) {
      try {
        await _authService.logout(access, refresh);
      } on ApiException catch (error) {
        logoutError = 'Déconnexion locale effectuée. ${error.message}';
      } catch (_) {
        logoutError =
            'Déconnexion locale effectuée, mais la révocation distante a échoué.';
      }
    }
    await clearSession();
    _errorMessage = logoutError;
    notifyListeners();
  }

  /// Efface jetons, profil et données de planning en mémoire et sur disque.
  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    // Les données métier de la session précédente ne doivent pas subsister.
    PlanningStore.clear();
    await _storage.clearTokens();
  }

  /// Efface le message d'erreur affiché (ex. quand l'utilisateur ressaisit).
  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Implémentation interne
  // ---------------------------------------------------------------------

  /// Enregistre les jetons en mémoire et dans le stockage sécurisé.
  Future<void> _saveTokens(String access, String refresh) async {
    await _storage.saveTokens(access, refresh);
    _accessToken = access;
    _refreshToken = refresh;
  }

  /// Effectue réellement le renouvellement (voir [refreshAccessToken]).
  Future<bool> _doRefresh() async {
    try {
      final refresh = _refreshToken ?? await _storage.readRefreshToken();
      if (refresh == null || refresh.isEmpty) {
        await clearSession();
        return false;
      }

      final response = await _authService.refresh(refresh);
      final access = response['access'];
      // Sans rotation, le serveur ne renvoie pas de nouveau `refresh`.
      final rotatedRefresh = response['refresh'] ?? refresh;
      if (access is! String ||
          access.isEmpty ||
          rotatedRefresh is! String ||
          rotatedRefresh.isEmpty) {
        throw const FormatException(
          'Le serveur a renvoyé des jetons de renouvellement invalides.',
        );
      }
      await _saveTokens(access, rotatedRefresh);
      _errorMessage = null;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
    } on FormatException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Impossible de renouveler la session.';
    }
    // Tout échec ferme la session : l'utilisateur doit se reconnecter.
    await clearSession();
    notifyListeners();
    return false;
  }

  /// Charge le profil ; après un 401, renouvelle le jeton et réessaie une fois.
  Future<Map<String, dynamic>> _loadProfileWithRetry() async {
    try {
      return await _loadUserProfile();
    } on ApiException catch (error) {
      if (!error.isUnauthorized || !await refreshAccessToken()) rethrow;
      return _loadUserProfile();
    }
  }

  /// Interroge `/api/profile/` avec le jeton courant.
  Future<Map<String, dynamic>> _loadUserProfile() async {
    final token = _accessToken;
    if (token == null) {
      throw const FormatException('Aucun jeton d’accès n’est disponible.');
    }
    final response = await _authService.profile(token);
    final profile = response['user'];
    if (profile is! Map) {
      throw const FormatException(
        'Le serveur a renvoyé un profil utilisateur invalide.',
      );
    }
    return Map<String, dynamic>.from(profile);
  }
}
