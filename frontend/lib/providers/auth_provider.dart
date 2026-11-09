import 'package:flutter/foundation.dart';

import '../repositories/auth_repository.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';

/// Pilote les états d’authentification et restaure les sessions persistées.
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? authRepository, AuthStorage? storage})
    : _authRepository = authRepository ?? AuthRepository(),
      _storage = storage ?? SecureAuthStorage();

  static const Set<String> _roles = {
    'admin',
    'student',
    'supervisor',
    'responsible',
  };

  final AuthRepository _authRepository;
  final AuthStorage _storage;

  bool _isLoading = false;
  bool _isInitializing = true;
  bool _isDisposed = false;
  Map<String, dynamic>? _user;
  String? _accessToken;
  String? _refreshToken;
  String? _errorMessage;
  Future<void>? _restoreOperation;

  /// Indique si une connexion ou restauration est en cours.
  bool get isLoading => _isLoading;

  /// Indique si la vérification initiale des jetons est terminée.
  bool get isInitializing => _isInitializing;

  /// Retourne le profil renvoyé par l’API Django.
  Map<String, dynamic>? get user => _user;

  /// Retourne le jeton à transmettre aux routes protégées.
  String? get accessToken => _accessToken;

  /// Retourne le jeton utilisé pour renouveler la session.
  String? get refreshToken => _refreshToken;

  /// Retourne le rôle SGSUS défini par le serveur.
  String? get role => _user?['role'] as String?;

  /// Retourne le dernier message d’erreur destiné à l’interface.
  String? get errorMessage => _errorMessage;

  /// Indique si un profil authentifié est actuellement disponible.
  bool get isAuthenticated => _user != null;

  /// Vérifie les jetons persistés et renouvelle la session si nécessaire.
  Future<void> restoreSession() {
    return _restoreOperation ??= _restoreSession();
  }

  Future<void> _restoreSession() async {
    _isInitializing = true;
    _notifyListeners();
    try {
      final accessToken = await _storage.readAccessToken();
      final refreshToken = await _storage.readRefreshToken();
      if (accessToken == null || refreshToken == null) {
        await _storage.clearTokens();
        return;
      }

      _accessToken = accessToken;
      _refreshToken = refreshToken;
      try {
        await _loadProfile(accessToken);
      } on ApiException catch (error) {
        if (error.statusCode == 403) {
          await _clearSession();
          return;
        }
        if (error.statusCode != 401) {
          _errorMessage = error.message;
          return;
        }
        await _refreshAndLoadProfile(refreshToken);
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _clearSession();
      } else {
        _errorMessage = error.message;
      }
    } on FormatException catch (error) {
      _errorMessage = error.message;
      await _clearSession();
    } on Exception catch (error) {
      _errorMessage = 'Impossible de restaurer la session : $error';
    } finally {
      _isInitializing = false;
      _notifyListeners();
    }
  }

  /// Échange les identifiants saisis contre la session réelle de l’API.
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    _notifyListeners();

    try {
      final response = await _authRepository.login(username, password);
      final user = _validatedUser(response['user']);
      final accessToken = _requiredToken(response['access'], 'accès');
      final refreshToken = _requiredToken(
        response['refresh'],
        'renouvellement',
      );
      await _storage.saveTokens(accessToken, refreshToken);
      _user = user;
      _accessToken = accessToken;
      _refreshToken = refreshToken;
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } on FormatException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (error) {
      _errorMessage = 'La session n’a pas pu être enregistrée : $error';
      return false;
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  /// Renouvelle les jetons puis recharge le profil courant.
  Future<bool> refreshSession() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) {
      await _clearSession();
      _notifyListeners();
      return false;
    }

    var refreshed = false;
    try {
      await _refreshAndLoadProfile(refreshToken);
      _errorMessage = null;
      refreshed = true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _clearSession();
      }
    } on FormatException catch (error) {
      _errorMessage = error.message;
      await _clearSession();
    } on Exception catch (error) {
      _errorMessage = 'Impossible de renouveler la session : $error';
    } finally {
      _notifyListeners();
    }
    return refreshed;
  }

  /// Révoque la session sur le serveur et efface toujours les jetons locaux.
  Future<bool> logout() async {
    var revoked = true;
    final accessToken = _accessToken;
    final refreshToken = _refreshToken;
    if (accessToken != null && refreshToken != null) {
      try {
        await _authRepository.logout(accessToken, refreshToken);
      } on ApiException catch (error) {
        revoked = false;
        _errorMessage =
            'Déconnexion locale effectuée ; révocation serveur impossible : ${error.message}';
      } catch (error) {
        revoked = false;
        _errorMessage =
            'Déconnexion locale effectuée ; révocation serveur impossible : $error';
      }
    }

    try {
      await _storage.clearTokens();
    } catch (error) {
      revoked = false;
      _errorMessage =
          'Impossible d’effacer les jetons de cet appareil : $error';
    }
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _notifyListeners();
    return revoked;
  }

  Future<void> _refreshAndLoadProfile(String refreshToken) async {
    final response = await _authRepository.refresh(refreshToken);
    final accessToken = _requiredToken(response['access'], 'accès');
    final rotatedRefresh = response['refresh'];
    final nextRefresh = rotatedRefresh == null
        ? refreshToken
        : _requiredToken(rotatedRefresh, 'renouvellement');
    await _storage.saveTokens(accessToken, nextRefresh);
    _accessToken = accessToken;
    _refreshToken = nextRefresh;
    await _loadProfile(accessToken);
  }

  Future<void> _loadProfile(String accessToken) async {
    final response = await _authRepository.profile(accessToken);
    _user = _validatedUser(response['user']);
    _accessToken = accessToken;
  }

  Map<String, dynamic> _validatedUser(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['role'] is! String ||
        !_roles.contains(value['role'])) {
      throw const FormatException(
        'Le profil renvoyé par le serveur est incomplet ou possède un rôle inconnu.',
      );
    }
    return Map<String, dynamic>.from(value);
  }

  String _requiredToken(dynamic value, String type) {
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'Le jeton d’$type renvoyé par le serveur est invalide.',
      );
    }
    return value;
  }

  Future<void> _clearSession() async {
    await _storage.clearTokens();
    _user = null;
    _accessToken = null;
    _refreshToken = null;
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
