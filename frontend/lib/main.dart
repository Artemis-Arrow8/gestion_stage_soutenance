import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/dashboard_screen.dart';
import 'providers/auth_provider.dart';
import 'views/login_view.dart';

void main() {
  // S'assure que les liaisons du framework Flutter sont initialisées
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.authProvider});

  /// Fournisseur injectable pour tester l’application sans appeler le réseau.
  final AuthProvider? authProvider;

  @override
  Widget build(BuildContext context) {
    // MultiProvider injecte l'état global de l'authentification
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => (authProvider ?? AuthProvider())..restoreSession(),
        ),
      ],
      child: MaterialApp(
        title: 'SGSUS - Gestion Stages et Soutenances',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          // Palette personnalisée : Noir, Or et Blanc
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD4AF37), // Or classique
            primary: const Color(0xFFD4AF37), // Or principal
            surface: Colors.white,
            onSurface: Colors.black,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212), // Fond noir élégant
          fontFamily: 'Fredoka',
        ),
        // L’écran dépend de la session vérifiée auprès de l’API.
        home: const AuthGate(),
      ),
    );
  }
}

/// Protège le tableau de bord par une session restaurée et validée.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    if (authProvider.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!authProvider.isAuthenticated) {
      return const LoginView();
    }
    return const DashboardScreen();
  }
}
