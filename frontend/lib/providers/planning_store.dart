/// Magasin partagé des données de planning (soutenances, salles, jurys).
///
/// Plusieurs écrans (tableau de bord, planning, salles, jurys, conflits,
/// cloche de notifications) affichent les mêmes soutenances. Plutôt que de
/// recharger l'API sur chaque écran, ils observent ce magasin unique via des
/// [ValueNotifier] : un seul chargement met à jour toute l'interface.
library;

import 'package:flutter/foundation.dart';

import '../core/network/api_service.dart';
import '../models/defense.dart';
import '../services/conflict_report.dart';
import '../services/planning_service.dart';

/// État global du planning, accessible de façon statique.
abstract final class PlanningStore {
  /// Soutenances connues, triées par le serveur.
  static final ValueNotifier<List<Defense>> defenses =
      ValueNotifier<List<Defense>>(const []);

  /// Vrai pendant un chargement depuis l'API.
  static final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// Dernier message d'erreur de chargement (ou `null`).
  static final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// Noms des salles actives (vide pour un membre du jury).
  static List<String> rooms = [];

  /// Noms des membres de jury connus, sans doublon.
  static List<String> juryMembers = [];

  /// Vrai lorsqu'un premier chargement a réussi.
  static bool _loaded = false;

  /// Chargement en cours, partagé pour éviter les appels concurrents.
  static Future<void>? _pending;

  /// Recharge toutes les données depuis l'API.
  ///
  /// [loadCatalog] charge aussi salles et jurys (réservé au personnel :
  /// un membre du jury n'a pas accès au catalogue complet).
  /// Les erreurs sont publiées dans [error] puis relancées à l'appelant.
  static Future<void> refresh(
    PlanningService service, {
    bool loadCatalog = true,
  }) {
    // Si un chargement est déjà en cours, on le partage au lieu d'en lancer
    // un second (plusieurs écrans peuvent demander un rafraîchissement).
    return _pending ??= _load(service, loadCatalog).whenComplete(() {
      _pending = null;
    });
  }

  /// Charge les données si elles ne l'ont jamais été (premier affichage).
  ///
  /// Les erreurs sont seulement publiées dans [error] : l'écran appelant
  /// les affiche via un `ValueListenableBuilder`.
  static Future<void> ensureLoaded(
    PlanningService service, {
    bool loadCatalog = true,
  }) async {
    if (_loaded) return;
    try {
      await refresh(service, loadCatalog: loadCatalog);
    } catch (_) {
      // Déjà publié dans `error`.
    }
  }

  /// Vide le magasin (appelé à la déconnexion pour ne rien laisser fuiter
  /// d'une session à l'autre).
  static void clear() {
    defenses.value = const [];
    rooms = [];
    juryMembers = [];
    error.value = null;
    _loaded = false;
  }

  /// Retourne les conflits connus de [candidate] avec le planning actuel.
  ///
  /// [ignoreId] exclut la soutenance elle-même lors d'une modification.
  static List<String> findConflicts(Defense candidate, {int? ignoreId}) {
    return ConflictScanner.findConflicts(
      candidate,
      defenses.value,
      ignoreId: ignoreId,
    );
  }

  /// Implémentation du chargement : appels API puis publication atomique.
  static Future<void> _load(PlanningService service, bool loadCatalog) async {
    loading.value = true;
    error.value = null;
    try {
      final loadedDefenses = await service.loadDefenses();
      final loadedRooms = loadCatalog
          ? await service.loadRooms()
          : const <Map<String, dynamic>>[];
      final loadedJuries = loadCatalog
          ? await service.loadJuries()
          : const <Map<String, dynamic>>[];

      // Salles actives uniquement, par nom.
      rooms = loadedRooms
          .where((room) => room['is_active'] != false)
          .map((room) => room['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
      // Membres de tous les jurys, dédoublonnés.
      juryMembers = loadedJuries
          .expand(
            (jury) => jury['members'] is List ? jury['members'] as List : [],
          )
          .whereType<Map>()
          .map((member) => member['member_name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      // Publié en dernier : les écrans voient des données cohérentes.
      defenses.value = loadedDefenses;
      _loaded = true;
    } on ApiException catch (e) {
      error.value = e.message;
      rethrow;
    } on FormatException catch (e) {
      error.value = e.message;
      rethrow;
    } catch (_) {
      error.value = 'Impossible de charger le planning.';
      rethrow;
    } finally {
      loading.value = false;
    }
  }
}
