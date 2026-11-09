import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/planning_store.dart';

class ConflictsScreen extends StatelessWidget {
  const ConflictsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, defenses, _) {
        final conflicts = <String>[];
        for (var i = 0; i < defenses.length; i++) {
          final found = PlanningStore.findConflicts(
            defenses[i],
            ignoreId: defenses[i].id,
          );
          for (final message in found) {
            final line = '${defenses[i].studentName} : $message';
            if (!conflicts.contains(line)) conflicts.add(line);
          }
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8F8F8),
          appBar: AppBar(
            title: const Text('Détection des conflits'),
            backgroundColor: const Color(0xFF171717),
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: conflicts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 58),
                        SizedBox(height: 12),
                        Text(
                          'Aucun conflit détecté',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Les salles et les membres des jurys ne sont pas réservés deux fois au même moment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      Text(
                        '${conflicts.length} conflit(s) détecté(s)',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...conflicts.map(
                        (message) => Card(
                          color: Colors.orange.shade50,
                          child: ListTile(
                            leading: const Icon(Icons.warning_amber, color: Colors.deepOrange),
                            title: Text(message),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
