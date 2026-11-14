import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gestion_stage_soutenance/providers/auth_provider.dart';
import 'package:gestion_stage_soutenance/views/home_view.dart';
import 'package:gestion_stage_soutenance/views/login_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Injection des providers globaux (gestion de session, authentification)
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..restoreSession()),
      ],
      child: MaterialApp(
        title: 'SGSUS - Gestion des Stages et Soutenances',
        debugShowCheckedModeBanner: false,
        // Thème visuel propre, professionnel et accessible (Material 3)
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        ),
        // Redirection dynamique selon l'état de la session
        home: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            if (authProvider.isLoading) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }
            // Si authentifié -> Accueil / Dashboard, sinon -> Connexion
            return authProvider.isAuthenticated
                ? const HomeView()
                : const LoginView();
          },
        ),
      ),
    );
  }
}