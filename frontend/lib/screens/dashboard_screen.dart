import 'package:flutter/material.dart';
import '../services/planning_store.dart';
import 'conflicts_screen.dart';
import 'jury_screen.dart';
import 'planning_screen.dart';
import 'rooms_screen.dart';
import 'defense_form_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const Color noir = Color(0xFF171717);
  static const Color or = Color(0xFFD4AF37);
  static const Color fond = Color(0xFFF8F8F8);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: PlanningStore.defenses,
      builder: (context, defenses, _) {
        return Scaffold(
          backgroundColor: fond,
          appBar: AppBar(
            title: const Text(
              'GESTION DES SOUTENANCES',
              style: TextStyle(color: noir, fontWeight: FontWeight.bold, fontSize: 17),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConflictsScreen()),
                ),
                icon: const Icon(Icons.notifications_none, color: noir),
                tooltip: 'Voir les conflits',
              ),
            ],
          ),
          drawer: Drawer(
            backgroundColor: noir,
            child: ListView(
              padding: const EdgeInsets.only(top: 50),
              children: [
                const Icon(Icons.school, color: or, size: 55),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'GESTION DES SOUTENANCES',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 25),
                _menu(context, Icons.dashboard, 'Tableau de bord', const DashboardScreen()),
                _menu(context, Icons.calendar_month, 'Planning', const PlanningScreen()),
                _menu(context, Icons.meeting_room, 'Salles', const RoomsScreen()),
                _menu(context, Icons.groups, 'Jurys', const JuryScreen()),
                _menu(context, Icons.warning_amber, 'Conflits', const ConflictsScreen()),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bonjour !', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Bienvenue dans votre espace de planification.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: noir,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ESPACE DE PLANIFICATION', style: TextStyle(color: or, fontWeight: FontWeight.bold)),
                      SizedBox(height: 12),
                      Text(
                        'Organisez les soutenances universitaires facilement.',
                        style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Gérez les horaires, les salles et les jurys.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                const Text('Vue générale', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 650 ? 3 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _stat('Soutenances', '${defenses.length}', Icons.event),
                    _stat('Salles', '${PlanningStore.rooms.length}', Icons.meeting_room),
                    _stat('Jurys', '${PlanningStore.juryMembers.length}', Icons.groups),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('Actions rapides', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _action(
                  context,
                  'Ajouter une soutenance',
                  Icons.add,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DefenseFormScreen()),
                  ),
                ),
                _action(
                  context,
                  'Consulter le planning',
                  Icons.calendar_month,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanningScreen()),
                  ),
                ),
                _action(
                  context,
                  'Vérifier les conflits',
                  Icons.warning_amber,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ConflictsScreen()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menu(BuildContext context, IconData icon, String title, Widget page) {
    return ListTile(
      leading: const Icon(Icons.circle, color: or, size: 9),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        if (title != 'Tableau de bord') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => page));
        }
      },
    );
  }

  Widget _stat(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFEAEAEA)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: or, size: 27),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: noir)),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _action(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, color: noir),
          label: Text(title, style: const TextStyle(color: noir, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: or,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }
}
