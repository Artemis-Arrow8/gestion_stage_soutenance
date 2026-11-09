import 'package:flutter/material.dart';
import '../services/planning_store.dart';

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text('Gestion des salles'),
        backgroundColor: const Color(0xFF171717),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Salles disponibles',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Consultez les espaces utilisés pour les soutenances.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          ...PlanningStore.rooms.map((room) {
            return Card(
              color: Colors.white,
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x1FD4AF37),
                  child: Icon(Icons.meeting_room, color: Color(0xFFD4AF37)),
                ),
                title: Text(room, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Salle enregistrée dans la liste locale'),
                trailing: const Icon(Icons.check_circle, color: Colors.green),
              ),
            );
          }),
        ],
      ),
    );
  }
}
