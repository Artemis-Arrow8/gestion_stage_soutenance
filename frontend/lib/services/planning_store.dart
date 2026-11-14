import 'package:flutter/foundation.dart';
import '../models/defense.dart';

class PlanningStore {
  PlanningStore._();

  static final ValueNotifier<List<Defense>> defenses =
      ValueNotifier<List<Defense>>([
    Defense(
      id: 1,
      studentName: 'Aminata Traoré',
      subject: 'Gestion intelligente des stages',
      date: '2026-11-10',
      startTime: '09:00',
      endTime: '10:00',
      roomName: 'Salle A1',
      juryName: 'M. Diallo, Mme Coulibaly',
      status: 'Confirmée',
    ),
    Defense(
      id: 2,
      studentName: 'Moussa Konaté',
      subject: 'Application de gestion scolaire',
      date: '2026-11-10',
      startTime: '10:30',
      endTime: '11:30',
      roomName: 'Salle B2',
      juryName: 'M. Touré, Mme Traoré',
      status: 'En attente',
    ),
    Defense(
      id: 3,
      studentName: 'Fatoumata Diarra',
      subject: 'Développement d’une application mobile',
      date: '2026-11-12',
      startTime: '14:00',
      endTime: '15:00',
      roomName: 'Salle A1',
      juryName: 'M. Diallo, M. Keïta',
      status: 'Confirmée',
    ),
  ]);

  static const List<String> rooms = [
    'Salle A1',
    'Salle A2',
    'Salle B1',
    'Salle B2',
    'Amphithéâtre',
  ];

  static const List<String> juryMembers = [
    'M. Diallo',
    'Mme Coulibaly',
    'M. Touré',
    'Mme Traoré',
    'M. Keïta',
    'Mme Diarra',
  ];

  static int nextId = 4;

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

  static void addDefense(Defense defense) {
    defenses.value = [...defenses.value, defense];
  }

  static void removeDefense(int id) {
    defenses.value =
        defenses.value.where((defense) => defense.id != id).toList();
  }
}
