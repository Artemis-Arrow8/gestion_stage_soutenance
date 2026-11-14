import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gestion_stage_soutenance/providers/auth_provider.dart';

/// Vue principale du tableau de bord (HomeView).
/// Adapte dynamiquement l'affichage en fonction du rôle de l'utilisateur connecté
/// (admin, student, supervisor, responsible).
class HomeView extends StatelessWidget {
  const HomeView({Key? key}) : super(key: key);

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

    final role = authProvider.role ?? 'student';

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
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
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
              onTap: () {},
            ),
            _buildActionCard(
              title: "Gestion des Utilisateurs & Rôles",
              subtitle: "Administrer les comptes et attributions",
              icon: Icons.people,
              onTap: () {},
            ),
          ],
        );

      case 'supervisor':
      case 'responsible':
        return Column(
          children: [
            _buildActionCard(
              title: "Validation des Dossiers de Stage",
              subtitle: "Consulter et évaluer les propositions de stage",
              icon: Icons.folder_shared,
              onTap: () {},
            ),
            _buildActionCard(
              title: "Planification des Soutenances",
              subtitle: "Affecter les salles et constituer les jurys",
              icon: Icons.event_available,
              onTap: () {},
            ),
          ],
        );

      case 'student':
      default:
        return Column(
          children: [
            _buildActionCard