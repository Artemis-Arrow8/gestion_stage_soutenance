/// Écran de connexion de l'application SGSUS.
///
/// Mise en page adaptative :
/// * grand écran : panneau de présentation sombre à gauche, formulaire à
///   droite ;
/// * téléphone / petite fenêtre : formulaire seul, centré, logo au-dessus.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/ui_kit.dart';

/// Écran de connexion (identifiant + mot de passe).
class LoginScreen extends StatefulWidget {
  /// Crée l'écran de connexion.
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// État de l'écran : contrôleurs de saisie et visibilité du mot de passe.
class _LoginScreenState extends State<LoginScreen> {
  /// Saisie de l'identifiant.
  final TextEditingController _usernameController = TextEditingController();

  /// Saisie du mot de passe.
  final TextEditingController _passwordController = TextEditingController();

  /// Clé du formulaire, pour déclencher la validation des champs.
  final _formKey = GlobalKey<FormState>();

  /// Vrai si le mot de passe est masqué.
  bool _obscurePassword = true;

  @override
  void dispose() {
    // Libération des contrôleurs pour éviter les fuites de mémoire.
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Valide le formulaire puis délègue la connexion au fournisseur de session.
  ///
  /// En cas de succès, l'aiguillage de l'application affiche automatiquement
  /// le tableau de bord ; en cas d'échec, le message d'erreur s'affiche.
  Future<void> _handleLogin() async {
    final auth = context.read<AuthProvider>();
    if (auth.isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    // Masque le clavier virtuel pendant la requête.
    FocusScope.of(context).unfocus();
    await auth.login(_usernameController.text.trim(), _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final form = _buildForm(context, showLogo: !wide);
          if (!wide) {
            // Une colonne : formulaire centré et défilable.
            return SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: form,
                  ),
                ),
              ),
            );
          }
          // Deux colonnes : présentation + formulaire.
          return Row(
            children: [
              const Expanded(flex: 5, child: _BrandPanel()),
              Expanded(
                flex: 4,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: form,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Construit la carte du formulaire ([showLogo] : logo au-dessus).
  Widget _buildForm(BuildContext context, {required bool showLogo}) {
    final auth = context.watch<AuthProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLogo) ...[
          const Center(child: _Logo(size: 60)),
          const SizedBox(height: 16),
          const Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Gestion des stages et des soutenances',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppColors.grey),
          ),
          const SizedBox(height: 28),
        ],
        SgCard(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Connexion',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Accédez à votre espace avec les identifiants fournis '
                  'par votre établissement.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.grey,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),

                // Message d'erreur renvoyé par le serveur (lisible : texte
                // rouge foncé sur fond rouge pâle).
                if (auth.errorMessage != null) ...[
                  SgBanner(
                    message: auth.errorMessage!,
                    tone: SgTone.danger,
                    onClose: auth.clearError,
                  ),
                  const SizedBox(height: 18),
                ],

                // Champ identifiant.
                TextFormField(
                  key: const Key('login-username'),
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: "Identifiant fourni par l'établissement",
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Veuillez entrer votre identifiant';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Champ mot de passe, avec bouton afficher/masquer.
                TextFormField(
                  key: const Key('login-password'),
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  // Touche « Entrée » : soumission directe du formulaire.
                  onFieldSubmitted: (_) => _handleLogin(),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Afficher le mot de passe'
                          : 'Masquer le mot de passe',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
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
                const SizedBox(height: 26),

                SgButton(
                  'Se connecter',
                  icon: Icons.arrow_forward_rounded,
                  expand: true,
                  loading: auth.isLoading,
                  onPressed: _handleLogin,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Rappel discret du serveur visé : utile pour vérifier qu'une
        // compilation pointe vers la bonne API (--dart-define). L'adresse
        // effective est utilisée (hôte et port) : pour la version PC, dont
        // l'adresse est relative (« /api »), on voit « localhost:8080 ».
        Text(
          'Serveur : ${Uri.tryParse(auth.api.baseUrl)?.authority ?? auth.api.baseUrl}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: AppColors.greyLight),
        ),
      ],
    );
  }
}

/// Panneau de présentation affiché à gauche sur grand écran.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.inkGradient),
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Logo(size: 46),
              SizedBox(width: 14),
              Text(
                AppConfig.appName,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          Spacer(),
          Text(
            'ESPACE UNIVERSITAIRE',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Stages et soutenances,\nréunis dans un seul espace.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              height: 1.25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          SizedBox(height: 28),
          _Feature(
            icon: Icons.calendar_month_rounded,
            text: 'Planification des soutenances sans conflit de salle ni de jury',
          ),
          _Feature(
            icon: Icons.folder_open_rounded,
            text: 'Dépôt et suivi des rapports de stage versionnés',
          ),
          _Feature(
            icon: Icons.verified_user_outlined,
            text: 'Accès sécurisé selon votre rôle',
          ),
          Spacer(),
          Text(
            'Gestion des stages et des soutenances universitaires',
            style: TextStyle(color: AppColors.greyLight, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Ligne « icône + avantage » du panneau de présentation.
class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  /// Icône illustrative.
  final IconData icon;

  /// Texte de l'avantage.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo de l'application : pastille dorée et coiffe universitaire.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  /// Côté du carré, en pixels logiques.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.goldLine,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33C9A227),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Icon(Icons.school_rounded, size: size * 0.52, color: AppColors.ink),
    );
  }
}
