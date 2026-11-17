/// Test d'intégration du stockage sécurisé des jetons.
///
/// Contrairement aux tests unitaires (qui simulent le stockage), ce test
/// s'exécute sur un vrai appareil ou émulateur :
///   flutter test integration_test -d <appareil>
/// Il vérifie l'écriture, la relecture et la suppression de clés.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Vérifie sur une cible native que le plugin écrit et relit via son stockage.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('le stockage natif conserve et efface les clés de test', (
    WidgetTester tester,
  ) async {
    const storage = FlutterSecureStorage();
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final accessKey = 'sgsus_integration_test_access_$suffix';
    final refreshKey = 'sgsus_integration_test_refresh_$suffix';
    const accessValue = 'jeton-de-test-acces';
    const refreshValue = 'jeton-de-test-renouvellement';

    try {
      await storage.write(key: accessKey, value: accessValue);
      await storage.write(key: refreshKey, value: refreshValue);

      expect(await storage.read(key: accessKey), accessValue);
      expect(await storage.read(key: refreshKey), refreshValue);
    } finally {
      await storage.delete(key: accessKey);
      await storage.delete(key: refreshKey);
    }

    expect(await storage.read(key: accessKey), isNull);
    expect(await storage.read(key: refreshKey), isNull);
  });
}
