import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthProvider extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _user;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters d'état
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _accessToken != null;

  // Rôle de l'utilisateur connecté (admin, student, supervisor, responsible)
  String? get role => _user?['role'] ?? _user?['group'];

  /// Restaure la session depuis le stockage sécurisé au lancement de l'application
  Future<void> restoreSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      _accessToken = await _storage.read(key: 'access_token');
      _refreshToken = await _storage.read(key: 'refresh_token');

      if (_accessToken != null) {
        await fetchUserProfile();
      }
    } catch (e) {
      _errorMessage = "Erreur lors de la restauration de la session.";
      await clearSession();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sauvegarde des tokens dans le stockage sécurisé
  Future<void> _saveTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  /// Tentative de rafraîchissement du token d'accès en cas d'expiration (401)
  Future<bool> refreshToken() async {
    try {
      _refreshToken = await _storage.read(key: 'refresh_token');
      if (_refreshToken == null) {
        await clearSession();
        return false;
      }

      // TODO: Remplacez par votre appel API de rafraîchissement (ex: AuthRepository.refresh(_refreshToken!))
      // Simulation / structure type :
      // final response = await ApiService.post('/api/token/refresh/', {'refresh': _refreshToken});
      // await _saveTokens(response['access'], _refreshToken!);
      
      notifyListeners();
      return true;
    } catch (e) {
      await clearSession();
      return false;
    }
  }

  /// Récupération du profil utilisateur connecté
  Future<void> fetchUserProfile() async {
    try {
      // TODO: Remplacez par l'appel à votre API de profil
      // _user = await AuthRepository.getProfile(_accessToken!);
      notifyListeners();
    } catch (e) {
      _errorMessage = "Impossible de récupérer le profil utilisateur.";
      notifyListeners();
    }
  }

  /// Connexion de l'utilisateur
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // TODO: Appel API de connexion (ex: AuthRepository.login(username, password))
      // const access = response['access'];
      // const refresh = response['refresh'];
      // _user = response['user'];
      // await _saveTokens(access, refresh);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = "Identifiants invalides ou erreur de connexion.";
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Déconnexion et nettoyage complet
  Future<void> logout() async {
    await clearSession();
    notifyListeners();
  }

  /// Nettoyage des tokens et de l'état local
  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}