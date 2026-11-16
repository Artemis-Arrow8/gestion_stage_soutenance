/// Widget racine de l'application : fournisseurs d'état, thème et
/// aiguillage entre l'écran de connexion et l'espace connecté.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/ui_kit.dart';

/// Application SGSUS.
class SgsusApp extends StatelessWidget {
  /// Crée l'application ; [authProvider] est injectable pour les tests.
  const SgsusApp({super.key, this.authProvider});

  /// Fournisseur de session à utiliser (sinon, un nouveau est créé et la
  /// session enregistrée sur l'appareil est restaurée).
  final AuthProvider? authProvider;

  @override
  Widget build(BuildContext context) {
    final provided = authProvider;
    return MultiProvider(
      providers: [
        // Session globale ; restaurée dès le lancement.
        if (provided == null)
          ChangeNotifierProvider(create: (_) => AuthProvider()..restoreSession())
        else
          ChangeNotifierProvider.value(value: provided),
      ],
      child: MaterialApp(
        title: AppConfig.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}

/// Aiguille l'utilisateur selon l'état de sa session.
///
/// * restauration en cours → écran d'attente ;
/// * session ouverte → tableau de bord ;
/// * sinon → écran de connexion.
class AuthGate extends StatelessWidget {
  /// Crée l'aiguillage.
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoring) {
      return const Scaffold(
        body: SgLoading(message: 'Restauration de votre session…'),
      );
    }
    if (!auth.isAuthenticated) {
      // Session fermée (déconnexion, jeton expiré) alors que des écrans
      // secondaires sont peut-être empilés au-dessus : on revient à la
      // racine après la construction pour afficher l'écran de connexion.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final navigator = Navigator.maybeOf(context);
        if (navigator != null && navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      });
    }
    // La clé force la reconstruction complète lors d'un changement de
    // session (aucun état d'écran ne survit à une déconnexion).
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: auth.isAuthenticated
          ? const DashboardScreen(key: ValueKey('espace-connecte'))
          : const LoginScreen(key: ValueKey('connexion')),
    );
  }
}
