import 'package:flutter/material.dart';
import '../models/defense.dart';

class PlanningScreen extends StatelessWidget {
  PlanningScreen({super.key});

  final List<Defense> defenses = [
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text(
          'Planning des soutenances',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF173B70),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suivi des soutenances',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF173B70),
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Consultez les dates, les horaires, les salles et les jurys.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total',
                    defenses.length.toString(),
                    Icons.event,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'Confirmées',
                    defenses
                        .where((d) => d.status == 'Confirmée')
                        .length
                        .toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildStatCard(
                    'En attente',
                    defenses
                        .where((d) => d.status == 'En attente')
                        .length
                        .toString(),
                    Icons.pending_actions,
                    Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            const Text(
              'Liste des soutenances',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: ListView.builder(
                itemCount: defenses.length,
                itemBuilder: (context, index) {
                  final defense = defenses[index];

                  return _buildDefenseCard(defense);
                },
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La création sera ajoutée à la prochaine étape.'),
            ),
          );
        },
        backgroundColor: const Color(0xFF173B70),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nouvelle soutenance',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildDefenseCard(Defense defense) {
    final bool confirmed = defense.status == 'Confirmée';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  defense.studentName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: confirmed
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  defense.status,
                  style: TextStyle(
                    color: confirmed ? Colors.green : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            defense.subject,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
          ),

          const Divider(height: 24),

          _buildInfoRow(Icons.calendar_today, defense.date),
          _buildInfoRow(
            Icons.access_time,
            '${defense.startTime} - ${defense.endTime}',
          ),
          _buildInfoRow(Icons.meeting_room, defense.roomName),
          _buildInfoRow(Icons.groups, defense.juryName),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(
            icon,j
            size: 17,
            color: const Color(0xFF173B70),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}