import 'package:flutter/material.dart';
import '../models/defense.dart';

class DefenseDetailScreen extends StatelessWidget {
  final Defense defense;

  const DefenseDetailScreen({super.key, required this.defense});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text('Détails de la soutenance'),
        backgroundColor: const Color(0xFF171717),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF171717),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.school, color: gold, size: 34),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Fiche de soutenance',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _detail('Étudiant', defense.studentName, Icons.person),
          _detail('Sujet', defense.subject, Icons.book),
          _detail('Date', defense.date, Icons.calendar_month),
          _detail('Horaire', '${defense.startTime} – ${defense.endTime}', Icons.access_time),
          _detail('Salle', defense.roomName, Icons.meeting_room),
          _detail('Jury', defense.juryName, Icons.groups),
          _detail('Statut', defense.status, Icons.info_outline),
        ],
      ),
    );
  }

  Widget _detail(String label, String value, IconData icon) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFD4AF37)),
        title: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        subtitle: Text(
          value,
          style: const TextStyle(
            color: Color(0xFF171717),
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
