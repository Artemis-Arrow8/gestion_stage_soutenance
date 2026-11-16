import '../services/api_service.dart';

/// Relie les opérations de session Flutter aux routes d’authentification Django.
class AuthRepository {
  AuthRepository({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  /// Client HTTP commun aux routes d’authentification Django.
  final ApiService _apiService;

  /// Authentifie un identifiant et un mot de passe auprès de Django.
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _apiService.post('login/', {
      'username': username,
      'password': password,
    });
    return _requireObject(response, 'connexion');
  }

  /// Obtient le profil courant à partir du jeton d’accès.
  Future<Map<String, dynamic>> profile(String accessToken) async {
    final response = await _apiService.get(
      'profile/',
      accessToken: accessToken,
    );
    return _requireObject(response, 'profil');
  }

  /// Révoque côté serveur le jeton de renouvellement de la session.
  Future<void> logout(String accessToken, String refreshToken) async {
    await _apiService.post('logout/', {
      'refresh': refreshToken,
    }, accessToken: accessToken);
  }

  /// Renouvelle un jeton d’accès et, le cas échéant, le jeton de renouvellement.
  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final response = await _apiService.post('token/refresh/', {
      'refresh': refreshToken,
    });
    return _requireObject(response, 'renouvellement du jeton');
  }

  /// Vérifie qu’une route d’authentification a renvoyé un objet JSON comme prévu.
  Map<String, dynamic> _requireObject(dynamic response, String operation) {
    if (response is Map<String, dynamic>) {
      return response;
    }
    throw FormatException(
      'Le serveur a renvoyé une réponse invalide pour $operation.',
    );
  }
}
