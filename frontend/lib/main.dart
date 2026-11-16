/// Point d'entrée de l'application Flutter SGSUS.
///
/// L'application se lance avec l'URL de l'API fournie à la compilation :
///
/// ```sh
/// flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8001/api
/// ```
library;

import 'package:material_ui/material_ui.dart';

import 'app.dart';

/// Initialise le moteur Flutter puis démarre l'application.
void main() {
  // Requis avant tout accès aux plugins (stockage sécurisé…) au démarrage.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SgsusApp());
}
