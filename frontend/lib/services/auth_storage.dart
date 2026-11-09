import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Définit le stockage des jetons pour faciliter les tests hors ligne.
abstract interface class AuthStorage {
  /// Enregistre les deux jetons de la session.
  Future<void> saveTokens(String accessToken, String refreshToken);

  /// Récupère le jeton d’accès conservé sur l’appareil.
  Future<String?> readAccessToken();

  /// Récupère le jeton de renouvellement conservé sur l’appareil.
  Future<String?> readRefreshToken();

  /// Efface les jetons locaux lors de la déconnexion.
  Future<void> clearTokens();
}

/// Protège les jetons avec le stockage sécurisé fourni par la plateforme.
class SecureAuthStorage implements AuthStorage {
  SecureAuthStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _accessKey = 'sgsus_access_token';
  static const String _refreshKey = 'sgsus_refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
