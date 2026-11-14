import 'package:flutter/foundation.dart';

import '../models/defense.dart';
import 'planning_service.dart';

class PlanningStore {
  PlanningStore._();

  static final ValueNotifier<List<Defense>> defenses =
      ValueNotifier<List<Defense>>([]);
  static List<String> rooms = [];
  static List<String> juryMembers = [];

  /// Remplace les données d’affichage par les réponses courantes de l’API.
  static Future<void> refresh(
    PlanningService service, {
    bool loadCatalog = true,
  }) async {
    final loadedDefenses = await service.loadDefenses();
    final loadedRooms = loadCatalog ? await service.loadRooms() : const [];
    final loadedJuries = loadCatalog ? await service.loadJuries() : const [];

    rooms = loadedRooms
        .whereType<Map>()
        .where((room) => room['is_active'] != false)
        .map((room) => room['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    juryMembers = loadedJuries
        .whereType<Map>()
        .expand((jury) => jury['members'] is List ? jury['members'] as List : [])
        .whereType<Map>()
        .map((member) => member['member_name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    defenses.value = loadedDefenses;
  }

  static bool overlaps(String startA, String endA, String startB, String endB) {
    final a1 = _minutes(startA);
    final a2 = _minutes(endA);
    final b1 = _minutes(startB);
    final b2 = _minutes(endB);
    return a1 < b2 && b1 < a2;
  }

  static int _minutes(String value) {
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Affiche les collisions connues ; l’API reste seule autorité à l’écriture.
  static List<String> findConflicts(Defense candidate, {int? ignoreId}) {
    final conflicts = <String>[];
    for (final existing in defenses.value) {
      if (existing.id == ignoreId || existing.date != candidate.date) {
        continue;
      }
      if (!overlaps(candidate.startTime, candidate.endTime,
          existing.startTime, existing.endTime)) {
        continue;
      }

      if (existing.roomName == candidate.roomName) {
        conflicts.add(
          'La ${candidate.roomName} est déjà utilisée par ${existing.studentName} '
          '(${existing.startTime}–${existing.endTime}).',
        );
      }

      final candidateJury = candidate.juryName
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      final existingJury = existing.juryName
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      final common = candidateJury.intersection(existingJury);
      if (common.isNotEmpty) {
        conflicts.add(
          'Membre(s) du jury déjà occupé(s) : ${common.join(', ')} '
          'avec ${existing.studentName}.',
        );
      }
    }
    return conflicts;
  }
}
