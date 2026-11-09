import 'package:flutter/material.dart';
import '../services/planning_store.dart';

class JuryScreen extends StatelessWidget {
  const JuryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text('Gestion des jurys'),
        backgroundColor: const Color(0xFF171717),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Membres disponibles',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Liste de démonstration des enseignants pouvant participer aux jurys.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          ...PlanningStore.juryMembers.map((member) {
            return Card(
              color: Colors.white,
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x1FD4AF37),
                  child: Icon(Icons.person, color: Color(0xFFD4AF37)),
                ),
                title: Text(member, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Membre du jury'),
                trailing: const Icon(Icons.verified_user_outlined),
              ),
            );
          }),
        ],
      ),
    );
  }
}
