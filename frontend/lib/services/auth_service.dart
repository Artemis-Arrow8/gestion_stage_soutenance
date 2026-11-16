/// Accès aux routes d'authentification de l'API Django.
///
/// Ce service ne conserve aucun état : il traduit chaque opération de
/// session (connexion, profil, renouvellement, déconnexion) en appel HTTP.
/// L'état de la session (jetons, profil) est géré par `AuthProvider`.
library;

import '../core/network/api_service.dart';

/// Client des routes `/api/login/`, `/api/profile/`, `/api/logout/` et
/// `/api/token/refresh/`.
class AuthService {
  /// Crée le service ; [apiService] est injectable pour les tests.
  ///
  /// Le client utilisé ici n'a pas de fournisseur de jeton : chaque route
  /// protégée reçoit explicitement le jeton à utiliser.
  AuthService({ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  /// Client HTTP commun aux routes d'authentification.
  final ApiService _apiService;

  /// Authentifie un identifiant et un mot de passe.
  ///
  /// Retourne `{"access", "refresh", "user"}` ; lève une [ApiException]
  /// en cas de refus (401/403) et une [FormatException] si la réponse
  /// n'est pas un objet JSON.
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _apiService.post('login/', {
      'username': username,
      'password': password,
    });
    return _requireObject(response, 'connexion');
  }

  /// Obtient le profil du compte porteur de [accessToken].
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

  /// Renouvelle le jeton d'accès (et, avec la rotation, le jeton de
  /// renouvellement) à partir de [refreshToken].
  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    final response = await _apiService.post('token/refresh/', {
      'refresh': refreshToken,
    });
    return _requireObject(response, 'renouvellement du jeton');
  }

  /// Vérifie qu'une route a renvoyé un objet JSON, comme prévu.
  ///
  /// [operation] est cité dans le message d'erreur pour faciliter le
  /// diagnostic.
  Map<String, dynamic> _requireObject(dynamic response, String operation) {
    if (response is Map<String, dynamic>) {
      return response;
    }
    throw FormatException(
      'Le serveur a renvoyé une réponse invalide pour $operation.',
    );
  }
}
