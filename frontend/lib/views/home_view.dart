import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'documents_view.dart';
import 'document_upload_view.dart';

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
          child: Text(
            'Cette session ne donne accès à aucun espace SGSUS.',
          ),
        ),
      );
    }

    const gold = Color(0xFFD4AF37);
    const card = Color(0xFF1E1E1E);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          dashboard.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: card,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: gold,
            ),
            tooltip: 'Se déconnecter',
            onPressed: () => authProvider.logout(),
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
                    backgroundColor: gold,
                    child: Icon(
                      Icons.person,
                      size: 35,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bienvenue,',
                          style: TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          user['full_name']?.toString() ??
                              'Compte SGSUS',
                          style: const TextStyle(
                            color: gold,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              _buildProfileCard(user, dashboard),

              const SizedBox(height: 25),

              const Text(
                'MES MODULES',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: GridView.builder(
                  itemCount: dashboard.actions.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.15,
                  ),
                  itemBuilder: (context, index) {
                    final action = dashboard.actions[index];

                    return _buildActionCard(
                      context,
                      action,
                      authProvider,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

 // Configuration des espaces selon le rôle.
_RoleDashboard? _dashboardForRole(String? role) {
  return switch (role) {
    'admin' => const _RoleDashboard(
        title: 'Tableau de bord — Administration',
        roleName: 'Administrateur',
        accountLabel: 'Compte :',
        actions: [
          _DashboardAction(
            Icons.manage_accounts,
            'Gestion des comptes',
          ),
          _DashboardAction(
            Icons.school,
            'Gestion des étudiants',
          ),
          _DashboardAction(
            Icons.folder,
            'Gestion des dossiers',
          ),
        ],
      ),
    'responsible' => const _RoleDashboard(
        title: 'Tableau de bord — Pédagogie',
        roleName: 'Responsable pédagogique',
        accountLabel: 'Compte :',
        actions: [
          _DashboardAction(
            Icons.campaign,
            'Campagnes',
          ),
          _DashboardAction(
            Icons.event_note,
            'Planification',
          ),
          _DashboardAction(
            Icons.folder_open,
            'Suivi des dossiers',
          ),
        ],
      ),
    'supervisor' => const _RoleDashboard(
        title: 'Tableau de bord — Encadrement',
        roleName: 'Encadreur',
        accountLabel: 'Compte :',
        actions: [
          _DashboardAction(
            Icons.rate_review,
            'Avis d’encadrement',
          ),
          _DashboardAction(
            Icons.fact_check,
            'Suivi des avis',
          ),
        ],
      ),
    'student' => const _RoleDashboard(
        title: 'Tableau de bord — Étudiant',
        roleName: 'Étudiant',
        accountLabel: 'Numéro étudiant :',
        actions: [
          _DashboardAction(
            Icons.folder_open,
            'Mon dossier de stage',
          ),
          _DashboardAction(
            Icons.upload_file,
            'Déposer un document',
          ),
          _DashboardAction(
            Icons.description,
            'Mes documents',
          ),
          _DashboardAction(
            Icons.timeline,
            'Suivi de mon dossier',
          ),
          _DashboardAction(
            Icons.event_note,
            'Ma soutenance',
          ),
        ],
      ),
    _ => null,
  };
}

  // Affichage des informations du compte.
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
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),

          const Divider(
            color: Colors.white24,
            height: 24,
          ),

          _buildInfoRow(
            dashboard.accountLabel,
            user['student_number']?.toString() ??
                user['username']?.toString() ??
                'N/A',
          ),

          const SizedBox(height: 12),

          _buildInfoRow(
            'Email :',
            user['email']?.toString() ?? 'N/A',
          ),

          const SizedBox(height: 12),

          _buildInfoRow(
            'Rôle :',
            dashboard.roleName,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // Gestion des clics sur les modules.
  Widget _buildActionCard(
    BuildContext context,
    _DashboardAction action,
    AuthProvider authProvider,
  ) {
    final isDocumentModule =
        action.title == 'Mes documents' ||
        action.title == 'Déposer un document';

    return InkWell(
      borderRadius: BorderRadius.circular(16),

      onTap: () {
        if (isDocumentModule) {
          final folderId = authProvider.folderId;
          final token = authProvider.accessToken;

          // Vérification de la session et du dossier.
          if (folderId == null || token == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Le dossier de stage ou le jeton '
                  'de connexion est indisponible.',
                ),
              ),
            );
            return;
          }

          // Choix de l'écran selon le module.
          final Widget page;

          if (action.title == 'Déposer un document') {
            page = DocumentUploadView(
              folderId: folderId,
              accessToken: token,
            );
          } else {
            page = DocumentsView(
              folderId: folderId,
              accessToken: token,
            );
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => page,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${action.title} sera intégré prochainement.',
              ),
            ),
          );
        }
      },

      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white10,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              action.icon,
              size: 38,
              color: const Color(0xFFD4AF37),
            ),

            const SizedBox(height: 12),

            Text(
              action.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Accéder au module',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Modèle du tableau de bord.
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

// Modèle des actions.
class _DashboardAction {
  const _DashboardAction(this.icon, this.title);

  final IconData icon;
  final String title;
}