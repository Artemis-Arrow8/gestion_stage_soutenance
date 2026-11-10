import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/document_provider.dart';
import 'views/home_view.dart';
import 'views/login_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.authProvider});

  final AuthProvider? authProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => (authProvider ?? AuthProvider())..restoreSession(),
        ),

        // Gestion globale des documents et des dépôts.
        ChangeNotifierProvider(
          create: (_) => DocumentProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'SGSUS - Gestion Stages et Soutenances',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD4AF37),
            primary: const Color(0xFFD4AF37),
            surface: Colors.white,
            onSurface: Colors.black,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          fontFamily: 'Fredoka',
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isInitializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!authProvider.isAuthenticated) {
      return const LoginView();
    }

    return const HomeView();
  }
}