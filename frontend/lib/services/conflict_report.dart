/// Détection locale des conflits de planning (salle ou jury doublement
/// réservés sur des créneaux qui se chevauchent).
///
/// Cette analyse est purement indicative : elle alimente les alertes de
/// l'interface. Le serveur reste l'unique autorité lors de l'écriture
/// (règle EXG01, garantie par des contraintes PostgreSQL).
library;

import '../models/defense.dart';

/// Catégorie d'un conflit détecté.
enum ConflictKind {
  /// Même salle réservée deux fois sur le même créneau.
  salle,

  /// Même membre de jury engagé dans deux soutenances simultanées.
  jury,

  /// Chevauchement horaire générique.
  horaire,
}

/// Conflit détecté, prêt à être affiché.
class ConflitItem {
  /// Crée un conflit.
  const ConflitItem({
    required this.etudiant,
    required this.message,
    required this.kind,
  });

  /// Étudiant dont la soutenance est en conflit.
  final String etudiant;

  /// Description lisible du conflit.
  final String message;

  /// Catégorie du conflit.
  final ConflictKind kind;

  /// Clé unique, utilisée pour dédoublonner les conflits symétriques.
  String get key => '$etudiant|$message';

  /// Libellé de la catégorie, en français.
  String get typeLabel => switch (kind) {
    ConflictKind.salle => 'Conflit de salle',
    ConflictKind.jury => 'Conflit de jury',
    ConflictKind.horaire => 'Chevauchement d’horaires',
  };
}

/// Fonctions d'analyse des conflits d'une liste de soutenances.
abstract final class ConflictScanner {
  /// Indique si deux plages horaires `HH:MM` se chevauchent.
  ///
  /// Les bornes sont semi-ouvertes : une soutenance qui finit à 10:00 ne
  /// chevauche pas celle qui commence à 10:00.
  static bool overlaps(String startA, String endA, String startB, String endB) {
    final a1 = _minutes(startA);
    final a2 = _minutes(endA);
    final b1 = _minutes(startB);
    final b2 = _minutes(endB);
    return a1 < b2 && b1 < a2;
  }

  /// Convertit une heure `HH:MM` en minutes depuis minuit (0 si invalide).
  static int _minutes(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  /// Découpe un nom de jury « A, B, C » en ensemble de membres normalisés.
  static Set<String> _membres(String juryName) => juryName
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();

  /// Liste les conflits entre [candidate] et les soutenances [existing].
  ///
  /// [ignoreId] exclut une soutenance (elle-même, lors d'une modification).
  /// Retourne des messages lisibles, vides s'il n'y a aucun conflit.
  static List<String> findConflicts(
    Defense candidate,
    List<Defense> existing, {
    int? ignoreId,
  }) {
    final conflicts = <String>[];
    for (final other in existing) {
      // Seules les soutenances du même jour peuvent se chevaucher.
      if (other.id == ignoreId || other.date != candidate.date) continue;
      if (!overlaps(
        candidate.startTime,
        candidate.endTime,
        other.startTime,
        other.endTime,
      )) {
        continue;
      }

      if (other.roomName == candidate.roomName) {
        conflicts.add(
          'La ${candidate.roomName} est déjà utilisée par ${other.studentName} '
          '(${other.startTime}–${other.endTime}).',
        );
      }

      // Conflit de jury : au moins un membre commun aux deux jurys.
      final common = _membres(
        candidate.juryName,
      ).intersection(_membres(other.juryName));
      if (common.isNotEmpty) {
        conflicts.add(
          'Membre(s) du jury déjà occupé(s) : ${common.join(', ')} '
          'avec ${other.studentName}.',
        );
      }
    }
    return conflicts;
  }

  /// Déduit la catégorie d'un conflit à partir de son message.
  static ConflictKind kindOf(String message) {
    final v = message.toLowerCase();
    if (v.contains('salle') || v.contains('room')) return ConflictKind.salle;
    if (v.contains('jury') || v.contains('membre')) return ConflictKind.jury;
    return ConflictKind.horaire;
  }

  /// Analyse tout un planning et retourne la liste dédoublonnée des conflits.
  static List<ConflitItem> scan(List<Defense> defenses) {
    final out = <ConflitItem>[];
    final seen = <String>{};
    for (final d in defenses) {
      for (final m in findConflicts(d, defenses, ignoreId: d.id)) {
        final item = ConflitItem(
          etudiant: d.studentName,
          message: m,
          kind: kindOf(m),
        );
        // `add` retourne false si la clé est déjà connue (doublon).
        if (seen.add(item.key)) out.add(item);
      }
    }
    return out;
  }
}
