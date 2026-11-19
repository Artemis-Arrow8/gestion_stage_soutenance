/// Configuration commune à tous les tests Flutter du projet.
///
/// `flutter test` exécute automatiquement [testExecutable] avant chaque
/// fichier de test du dossier. On y remplace le cache hors ligne persistant
/// (SharedPreferences, indisponible hors d'un vrai appareil) par un cache
/// en mémoire, vidé entre deux tests.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/core/network/hors_ligne.dart';

/// Point d'entrée appelé par `flutter test` pour chaque fichier de test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    // Cache neuf et mode « en ligne » au début de chaque test.
    HorsLigne.cache = CacheMemoire();
    HorsLigne.signalerConnecte();
  });
  await testMain();
}
