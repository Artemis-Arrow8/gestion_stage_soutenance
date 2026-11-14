import '../models/defense.dart';
import 'planning_store.dart';

enum ConflictKind { salle, jury, horaire }

class ConflitItem {
  const ConflitItem({
    required this.etudiant,
    required this.message,
    required this.kind,
  });

  final String etudiant;
  final String message;
  final ConflictKind kind;

  String get key => '$etudiant|$message';

  String get typeLabel => switch (kind) {
        ConflictKind.salle => 'Conflit de salle',
        ConflictKind.jury => 'Conflit de jury',
        ConflictKind.horaire => 'Chevauchement d’horaires',
      };
}

class ConflictScanner {
  static ConflictKind kindOf(String message) {
    final v = message.toLowerCase();
    if (v.contains('salle') || v.contains('room')) return ConflictKind.salle;
    if (v.contains('jury') || v.contains('membre')) return ConflictKind.jury;
    return ConflictKind.horaire;
  }

  static List<ConflitItem> scan(List<Defense> defenses) {
    final out = <ConflitItem>[];
    final seen = <String>{};
    for (final d in defenses) {
      for (final m in PlanningStore.findConflicts(d, ignoreId: d.id)) {
        final item = ConflitItem(
          etudiant: d.studentName,
          message: m,
          kind: kindOf(m),
        );
        if (seen.add(item.key)) out.add(item);
      }
    }
    return out;
  }
}