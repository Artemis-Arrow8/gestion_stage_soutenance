import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  // Contrôleurs pour récupérer les saisies des champs de texte
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Clé globale pour la validation du formulaire
  final _formKey = GlobalKey<FormState>();

  // Couleurs de la charte graphique : Blanc, Or et Noir
  final Color _goldColor = const Color(0xFFD4AF37); // Or classique
  final Color _cardColor = const Color(
    0xFFF5F5F5,
  ); // Gris très clair pour distinguer les champs du fond blanc

  @override
  void dispose() {
    // Nettoyage des contrôleurs pour éviter les fuites de mémoire
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Valide le formulaire puis délègue la connexion réelle au fournisseur.
  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      await authProvider.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Écoute du provider pour réagir aux états de chargement et erreurs
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: Colors.white, // Fond blanc
      body: SafeArea(
        child: Center(
          // SingleChildScrollView combiné à ConstrainedBox et IntrinsicHeight
          // pour permettre le défilement fluide sans erreur de contrainte de hauteur.
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 80,
              ),
              child: IntrinsicHeight(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Icône académique aux reflets dorés
                      Icon(Icons.school_rounded, size: 80, color: _goldColor),
                      const SizedBox(height: 16),

                      // Titre de l'application en Noir pour contraster avec le fond blanc
                      const Text(
                        'SGSUS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Sous-titre explicatif en gris foncé sur fond blanc
                      const Text(
                        'Gestion des Stages et Soutenances',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      const SizedBox(height: 40),

                      // Affichage dynamique des erreurs retournées par le serveur
                      if (authProvider.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.shade400),
                          ),
                          child: Text(
                            authProvider.errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Champ de saisie : identifiant transmis par l'établissement
                      TextFormField(
                        key: const Key('login-username'),
                        controller: _usernameController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: "Identifiant fourni par l'établissement",
                          labelStyle: const TextStyle(color: Colors.black54),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: _goldColor,
                          ),
                          filled: true,
                          fillColor: _cardColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: _goldColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Veuillez entrer votre identifiant';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Champ de saisie : Mot de passe
                      TextFormField(
                        key: const Key('login-password'),
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          labelStyle: const TextStyle(color: Colors.black54),
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: _goldColor,
                          ),
                          filled: true,
                          fillColor: _cardColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: _goldColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Veuillez entrer votre mot de passe';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 28),

                      // Bouton de connexion doré ; le texte noir assure un bon contraste.
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: authProvider.isLoading
                              ? null
                              : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _goldColor,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: authProvider.isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Se connecter',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
