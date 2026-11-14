import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gestion_stage_soutenance/providers/auth_provider.dart';

import '../screens/accounts_screen.dart';
import '../screens/campaigns_screen.dart';
import '../screens/documents_screen.dart';
import '../screens/conflicts_screen.dart';
import '../screens/jury_screen.dart';
import '../screens/planning_screen.dart';
import '../screens/rooms_screen.dart';

/// Vue principale du tableau de bord (HomeView).
/// Adapte dynamiquement l'affichage en fonction du rôle de l'utilisateur connecté
/// (admin, student, supervisor, responsible, jury).
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    // Vérification de la session utilisateur
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            "Aucune session active. Veuillez vous connecter.",
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
        ),
      );
    }

    // Un rôle absent ne doit pas être interprété comme un compte étudiant.
    final role = authProvider.role ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord - SGSUS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () async {
              await authProvider.logout();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // En-tête de profil utilisateur
            _buildProfileCard(user),
            const SizedBox(height: 24),
            const Text(
              "MES MODULES & ACTIONS",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Contenu dynamique selon le rôle
            _buildDashboardByRole(role, context),
          ],
        ),
      ),
    );
  }

  /// Carte affichant les informations sommaires de l'utilisateur connecté
  Widget _buildProfileCard(Map<String, dynamic> user) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.blueGrey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user['full_name'] ?? user['username'] ?? 'Utilisateur',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            "Email : ${user['email'] ?? 'Non renseigné'}",
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 4),
          Text(
            "Rôle : ${user['role'] ?? 'Non défini'}",
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }

  /// Sélectionne et affiche les actions et tableaux de bord spécifiques au rôle
  Widget _buildDashboardByRole(String role, BuildContext context) {
    switch (role) {
      case 'admin':
        return Column(
          children: [
            _buildActionCard(
              title: "Gestion des Campagnes",
              subtitle: "Configurer les années académiques et sessions",
              icon: Icons.calendar_today,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CampaignsScreen()),
              ),
            ),
            _buildActionCard(
              title: "Gestion des Utilisateurs & Rôles",
              subtitle: "Administrer les comptes et attributions",
              icon: Icons.people,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              ),
            ),
            _buildActionCard(
              title: "Planning des soutenances",
              subtitle: "Consulter et organiser les créneaux",
              icon: Icons.event_available,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanningScreen()),
              ),
            ),
            _buildActionCard(
              title: "Documents",
              subtitle: "Consulter les dossiers et versions",
              icon: Icons.description,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DocumentsScreen()),
              ),
            ),
            _buildActionCard(
              title: "Gestion des salles",
              subtitle: "Consulter et administrer les salles",
              icon: Icons.meeting_room,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RoomsScreen()),
              ),
            ),
            _buildActionCard(
              title: "Gestion des jurys",
              subtitle: "Consulter les jurys et leurs membres",
              icon: Icons.groups,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JuryScreen()),
              ),
            ),
            _buildActionCard(
              title: "Conflits de planning",
              subtitle: "Consulter les conflits détectés",
              icon: Icons.warning_amber,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConflictsScreen()),
              ),
            ),
          ],
        );

      case 'responsible':
        return Column(
          children: [
            _buildActionCard(
              title: "Gestion des Campagnes",
              subtitle: "Configurer les années académiques et sessions",
              icon: Icons.calendar_today,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CampaignsScreen()),
              ),
            ),
            _buildActionCard(
              title: "Validation des Dossiers de Stage",
              subtitle: "Consulter et évaluer les propositions de stage",
              icon: Icons.folder_shared,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DocumentsScreen()),
              ),
            ),
            _buildActionCard(
              title: "Planification des Soutenances",
              subtitle: "Consulter et organiser les créneaux",
              icon: Icons.event_available,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanningScreen()),
              ),
            ),
            _buildActionCard(
              title: "Gestion des salles",
              subtitle: "Consulter et administrer les salles",
              icon: Icons.meeting_room,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RoomsScreen()),
              ),
            ),
            _buildActionCard(
              title: "Gestion des jurys",
              subtitle: "Consulter les jurys et leurs membres",
              icon: Icons.groups,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JuryScreen()),
              ),
            ),
            _buildActionCard(
              title: "Conflits de planning",
              subtitle: "Consulter les conflits détectés",
              icon: Icons.warning_amber,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConflictsScreen()),
              ),
            ),
          ],
        );

      case 'supervisor':
        return Column(
          children: [
            _buildActionCard(
              title: "Dossiers affectés et avis d'encadrement",
              subtitle: "Consulter les rapports et donner un avis",
              icon: Icons.folder_shared,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DocumentsScreen()),
              ),
            ),
          ],
        );

      case 'jury':
        return Column(
          children: [
            _buildActionCard(
              title: "Mon planning de jury",
              subtitle: "Consulter les soutenances qui me sont affectées",
              icon: Icons.event_available,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanningScreen()),
              ),
            ),
          ],
        );

      case 'student':
        return Column(
          children: [
            _buildActionCard(
              title: "Mon dossier et mes documents",
              subtitle: "Consulter l'avancement et les rapports déposés",
              icon: Icons.description,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DocumentsScreen()),
              ),
            ),
          ],
        );
      default:
        return const Center(
          child: Text("Le rôle de ce compte n'est pas reconnu."),
        );
    }
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
