import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repositories/auth_repository.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    AuthRepository? authRepository,
    FlutterSecureStorage? storage,
  }) : _authRepository = authRepository ?? AuthRepository(),
       _storage = storage ?? const FlutterSecureStorage();

  final AuthRepository _authRepository;
  final FlutterSecureStorage _storage;

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _errorMessage;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _accessToken != null;
  String? get role => _user?['role'] ?? _user?['group'];

  Future<void> restoreSession() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _accessToken = await _storage.read(key: 'access_token');
      _refreshToken = await _storage.read(key: 'refresh_token');

      if (_accessToken == null && _refreshToken != null) {
        if (!await refreshAccessToken()) return;
      }
      if (_accessToken != null) {
        try {
          _user = await _loadUserProfile();
        } on ApiException catch (error) {
          if (error.statusCode != 401 || !await refreshAccessToken()) {
            rethrow;
          }
          _user = await _loadUserProfile();
        }
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
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveTokens(String access, String refresh) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
    _accessToken = access;
    _refreshToken = refresh;
  }

  Future<bool> refreshAccessToken() async {
    try {
      final refresh = _refreshToken ?? await _storage.read(key: 'refresh_token');
      if (refresh == null || refresh.isEmpty) {
        await clearSession();
        return false;
      }

      final response = await _authRepository.refresh(refresh);
      final access = response['access'];
      final rotatedRefresh = response['refresh'] ?? refresh;
      if (access is! String || access.isEmpty ||
          rotatedRefresh is! String || rotatedRefresh.isEmpty) {
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
      await clearSession();
      notifyListeners();
      return false;
    } on FormatException catch (error) {
      _errorMessage = error.message;
      await clearSession();
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Impossible de renouveler la session.';
      await clearSession();
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> _loadUserProfile() async {
    final token = _accessToken;
    if (token == null) {
      throw const FormatException('Aucun jeton d’accès n’est disponible.');
    }
    final response = await _authRepository.profile(token);
    final profile = response['user'];
    if (profile is! Map) {
      throw const FormatException(
        'Le serveur a renvoyé un profil utilisateur invalide.',
      );
    }
    return Map<String, dynamic>.from(profile);
  }

  Future<void> fetchUserProfile() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      try {
        _user = await _loadUserProfile();
      } on ApiException catch (error) {
        if (error.statusCode != 401 || !await refreshAccessToken()) {
          rethrow;
        }
        _user = await _loadUserProfile();
      }
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

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _authRepository.login(username.trim(), password);
      final access = response['access'];
      final refresh = response['refresh'];
      final profile = response['user'];
      if (access is! String || access.isEmpty ||
          refresh is! String || refresh.isEmpty ||
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

  Future<void> logout() async {
    String? logoutError;
    final access = _accessToken;
    final refresh = _refreshToken;
    if (access != null && refresh != null) {
      try {
        await _authRepository.logout(access, refresh);
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

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    await Future.wait([
      _storage.delete(key: 'access_token'),
      _storage.delete(key: 'refresh_token'),
    ]);
  }
}
