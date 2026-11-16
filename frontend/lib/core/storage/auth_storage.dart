/// Stockage persistant des jetons de session (JWT).
///
/// L'interface [AuthStorage] découple le fournisseur d'authentification du
/// mécanisme de stockage réel : en production, [SecureAuthStorage] s'appuie
/// sur le trousseau sécurisé de la plateforme (Keychain, Keystore, stockage
/// chiffré du navigateur) ; dans les tests, une implémentation en mémoire
/// peut être injectée.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Contrat de stockage des jetons d'accès et de renouvellement.
abstract interface class AuthStorage {
  /// Enregistre les deux jetons de la session.
  Future<void> saveTokens(String accessToken, String refreshToken);

  /// Récupère le jeton d'accès conservé sur l'appareil (ou `null`).
  Future<String?> readAccessToken();

  /// Récupère le jeton de renouvellement conservé sur l'appareil (ou `null`).
  Future<String?> readRefreshToken();

  /// Efface les jetons locaux lors de la déconnexion.
  Future<void> clearTokens();
}

/// Implémentation sécurisée fondée sur `flutter_secure_storage`.
class SecureAuthStorage implements AuthStorage {
  /// Crée le stockage ; [storage] est injectable pour les tests.
  SecureAuthStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Clé du jeton d'accès (préfixée pour éviter toute collision).
  static const String _accessKey = 'sgsus_access_token';

  /// Clé du jeton de renouvellement.
  static const String _refreshKey = 'sgsus_refresh_token';

  /// Accès au stockage sécurisé de la plateforme.
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
    // Suppressions indépendantes : on les lance en parallèle.
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
