import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/planning_store.dart';
import 'defense_detail_screen.dart';
import 'defense_form_screen.dart';

class PlanningScreen extends StatelessWidget {
  const PlanningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, defenses, _) {
        final confirmed = defenses.where((d) => d.status == 'Confirmée').length;
        final pending = defenses.where((d) => d.status == 'En attente').length;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F8F8),
          appBar: AppBar(
            title: const Text('Planning des soutenances'),
            backgroundColor: const Color(0xFF171717),
            foregroundColor: Colors.white,
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Suivi des soutenances',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Consultez les dates, les horaires, les salles et les jurys.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _stat('Total', defenses.length, Icons.event, Colors.blue),
                    _stat('Confirmées', confirmed, Icons.check_circle, Colors.green),
                    _stat('En attente', pending, Icons.pending_actions, Colors.orange),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Liste des soutenances',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: defenses.isEmpty
                      ? const Center(child: Text('Aucune soutenance enregistrée.'))
                      : ListView.builder(
                          itemCount: defenses.length,
                          itemBuilder: (context, index) {
                            final defense = defenses[index];
                            return Card(
                              color: Colors.white,
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                title: Text(
                                  defense.studentName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Text(
                                    '${defense.subject}\n'
                                    '${defense.date} • ${defense.startTime}–${defense.endTime}\n'
                                    '${defense.roomName} • ${defense.juryName}',
                                  ),
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DefenseDetailScreen(defense: defense),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: const Color(0xFF171717),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DefenseFormScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle soutenance'),
          ),
        );
      },
    );
  }

  Widget _stat(String title, int value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 6),
              Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
