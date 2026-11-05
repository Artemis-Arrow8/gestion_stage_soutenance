import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Affiche un tableau de bord correspondant au rôle fourni par l’API.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final dashboard = _dashboardForRole(authProvider.role);
    if (user == null || dashboard == null) {
      return const Scaffold(
        body: Center(
          child: Text('Cette session ne donne accès à aucun espace SGSUS.'),
        ),
      );
    }

    const goldColor = Color(0xFFD4AF37);
    const cardColor = Color(0xFF1E1E1E);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          dashboard.title,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: cardColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: goldColor),
            tooltip: 'Se déconnecter',
            onPressed: authProvider.logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: goldColor,
                    child: Icon(Icons.person, size: 35, color: Colors.black),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bienvenue,',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user['full_name'] as String? ?? 'Compte SGSUS',
                          style: const TextStyle(
                            color: goldColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildProfileCard(user, dashboard),
              const SizedBox(height: 32),
              const Text(
                'Modules à intégrer selon votre rôle',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: dashboard.actions.map(_buildActionCard).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Associe seulement les quatre rôles SGSUS connus à un tableau de bord.
  _RoleDashboard? _dashboardForRole(String? role) {
    return switch (role) {
      'admin' => const _RoleDashboard(
        title: 'Tableau de bord — Administration',
        roleName: 'Administrateur',
        accountLabel: 'Compte :',
        actions: [
          _DashboardAction(Icons.manage_accounts, 'Gestion des comptes'),
          _DashboardAction(Icons.school, 'Gestion des étudiants'),
        ],
      ),
      'responsible' => const _RoleDashboard(
        title: 'Tableau de bord — Pédagogie',
        roleName: 'Responsable pédagogique',
        accountLabel: 'Compte :',
        actions: [
          _DashboardAction(Icons.campaign, 'Campagnes'),
          _DashboardAction(Icons.event_note, 'Planification'),
        ],
      ),
      'supervisor' => const _RoleDashboard(
        title: 'Tableau de bord — Encadrement',
        roleName: 'Encadreur',
        accountLabel: 'Compte :',
        actions: [
          _DashboardAction(Icons.rate_review, 'Avis d’encadrement'),
          _DashboardAction(Icons.fact_check, 'Suivi des avis'),
        ],
      ),
      'student' => const _RoleDashboard(
        title: 'Tableau de bord — Étudiant',
        roleName: 'Étudiant',
        accountLabel: 'Numéro d’étudiant :',
        actions: [
          _DashboardAction(Icons.folder_open, 'Mon dossier de stage'),
          _DashboardAction(Icons.event_note, 'Ma soutenance'),
        ],
      ),
      _ => null,
    };
  }

  /// Présente les informations du profil retourné par Django.
  Widget _buildProfileCard(
    Map<String, dynamic> user,
    _RoleDashboard dashboard,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profil du compte',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white24, height: 24),
          _buildInfoRow(
            dashboard.accountLabel,
            user['student_number'] as String? ??
                user['username'] as String? ??
                'N/A',
          ),
          const SizedBox(height: 12),
          _buildInfoRow('Email :', user['email'] as String? ?? 'N/A'),
          const SizedBox(height: 12),
          _buildInfoRow('Rôle :', dashboard.roleName),
        ],
      ),
    );
  }

  /// Affiche une ligne de renseignement sans faire confiance à des valeurs nulles.
  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// Signale un module prévu sans simuler une navigation qui n’existe pas encore.
  Widget _buildActionCard(_DashboardAction action) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(action.icon, size: 40, color: const Color(0xFFD4AF37)),
          const SizedBox(height: 12),
          Text(
            action.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Module non intégré',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Regroupe les libellés et les entrées visibles pour un rôle.
class _RoleDashboard {
  const _RoleDashboard({
    required this.title,
    required this.roleName,
    required this.accountLabel,
    required this.actions,
  });

  final String title;
  final String roleName;
  final String accountLabel;
  final List<_DashboardAction> actions;
}

/// Représente une entrée descriptive du tableau de bord.
class _DashboardAction {
  const _DashboardAction(this.icon, this.title);

  final IconData icon;
  final String title;
}
