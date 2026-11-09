import '../services/api_service.dart';

/// Relie les opérations de session Flutter aux routes d’authentification Django.
class AuthRepository {
  AuthRepository({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  final ApiService _apiService;

  /// Authentifie un identifiant et un mot de passe auprès de Django.
  Future<Map<String, dynamic>> login(String username, String password) async {
    return _apiService.post('login/', {
      'username': username,
      'password': password,
    });
  }

  /// Obtient le profil courant à partir du jeton d’accès.
  Future<Map<String, dynamic>> profile(String accessToken) {
    return _apiService.get('profile/', accessToken: accessToken);
  }

  /// Révoque côté serveur le jeton de renouvellement de la session.
  Future<void> logout(String accessToken, String refreshToken) async {
    await _apiService.post('logout/', {
      'refresh': refreshToken,
    }, accessToken: accessToken);
  }

  /// Renouvelle un jeton d’accès et, le cas échéant, le jeton de renouvellement.
  Future<Map<String, dynamic>> refresh(String refreshToken) {
    return _apiService.post('token/refresh/', {'refresh': refreshToken});
  }
}
