/*Configuration globale de l'application, fixée à la compilation.
 Centraliser ces valeurs ici évite de disperser des URL « en dur » dans
les services et facilite le passage d'un environnement à l'autre.*/
library;

/// Paramètres de l'application, accessibles en lecture seule.
abstract final class AppConfig {
  /// Nom court de l'application, affiché dans l'interface.
  static const String appName = 'SGSUS';

  /// Nom long, utilisé comme titre de la fenêtre / de l'onglet navigateur.
  static const String appTitle = 'SGSUS — Gestion des stages et soutenances';

  /// URL publique de l'API Django, terminée par `/api`.
  
  /// Valeur par défaut : le backend local publié par Docker Compose sur le
  /// port 8001. En production, fournir l'URL HTTPS du Web Service Render.
  /// Ne jamais y mettre l'URL PostgreSQL : Flutter ne parle qu'à l'API HTTP.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8001/api',
  );

  /// Délai maximal d'attente d'une réponse HTTP avant abandon.
  ///
  /// Généreux pour tolérer le « réveil » d'une instance Render gratuite
  /// mise en veille (jusqu'à une minute).
  static const Duration httpTimeout = Duration(seconds: 60);
}
