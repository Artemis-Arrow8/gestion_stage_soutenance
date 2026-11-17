/// Écran « Mon profil » : identité de l'utilisateur connecté, informations
/// propres à son rôle et changement de mot de passe.
///
/// * Étudiant : son stage (entreprise, sujet, statut) et sa soutenance
///   (date, salle, jury, statut, note finale une fois validée).
/// * Membre du jury : le nom sous lequel il siège.
/// * Tous les rôles : formulaire de changement de mot de passe.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Écran du profil.
class ProfileScreen extends StatefulWidget {
  /// Crée l'écran du profil.
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// État de l'écran : rafraîchit le profil à l'ouverture.
class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Recharge le profil pour afficher les données les plus récentes
    // (statut du dossier, soutenance planifiée, note validée…).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().fetchUserProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? const <String, dynamic>{};

    return SgPage(
      section: AppSection.profil,
      title: 'Mon profil',
      subtitle: 'Vos informations personnelles et la sécurité de votre compte.',
      maxWidth: 980,
      onRefresh: auth.fetchUserProfile,
      child: LayoutBuilder(
        builder: (context, c) {
          final colonneGauche = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _IdentityCard(auth: auth),
              if (auth.role == 'student') ...[
                const SizedBox(height: 16),
                _StudentCard(user: user),
              ],
              if (auth.role == 'jury' && user['jury_member_name'] != null) ...[
                const SizedBox(height: 16),
                _InfoCard(
                  icon: Icons.groups_2_rounded,
                  titre: 'Membre du jury',
                  texte: 'Vous siégez sous le nom « ${user['jury_member_name']} ».',
                ),
              ],
            ],
          );
          const formulaire = _PasswordCard();
          // Deux colonnes sur grand écran, une seule sur téléphone.
          if (c.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [colonneGauche, const SizedBox(height: 16), formulaire],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: colonneGauche),
              const SizedBox(width: 16),
              const Expanded(flex: 5, child: formulaire),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Carte d'identité
// ===========================================================================

/// Bandeau noir et or : avatar, nom, rôle, identifiant et e-mail.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.auth});

  /// Session courante.
  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    final user = auth.user ?? const <String, dynamic>{};
    final email = user['email']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.inkGradient,
        borderRadius: BorderRadius.circular(AppTheme.radius + 2),
      ),
      child: Row(
        children: [
          // Avatar doré aux initiales.
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: AppTheme.goldLine,
              shape: BoxShape.circle,
            ),
            child: Text(
              initiales(auth.displayName),
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AuthProvider.roleLabel(auth.role).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                _ligne(Icons.alternate_email_rounded, user['username']?.toString() ?? ''),
                if (email.isNotEmpty) _ligne(Icons.mail_outline_rounded, email),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ligne « icône + texte » sur fond noir.
  Widget _ligne(IconData icon, String texte) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.55)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            texte,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

// ===========================================================================
// Informations de l'étudiant
// ===========================================================================

/// Carte « Mon stage » et « Ma soutenance » d'un étudiant.
class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.user});

  /// Profil renvoyé par l'API.
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final statut = user['folder_status']?.toString();
    final soutenance = user['defense'] is Map
        ? Map<String, dynamic>.from(user['defense'] as Map)
        : null;

    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SgOverline('Mon stage')),
              if (statut != null) SgStatusBadge(statut),
            ],
          ),
          const SizedBox(height: 14),
          if (statut == null)
            const Text(
              'Aucun dossier pour la campagne en cours. Créez-le depuis '
              'l’écran Documents.',
              style: TextStyle(fontSize: 13, color: AppColors.grey),
            )
          else ...[
            SgKv(label: 'Entreprise', value: user['folder_company']?.toString() ?? ''),
            const SizedBox(height: 12),
            SgKv(label: 'Sujet', value: user['folder_subject']?.toString() ?? ''),
            const SizedBox(height: 12),
            SgKv(label: 'Matricule', value: user['student_number']?.toString() ?? ''),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(),
          ),
          const SgOverline('Ma soutenance'),
          const SizedBox(height: 14),
          if (soutenance == null)
            const Text(
              'Votre soutenance n’est pas encore planifiée.',
              style: TextStyle(fontSize: 13, color: AppColors.grey),
            )
          else
            _soutenance(soutenance),
        ],
      ),
    );
  }

  /// Détails de la soutenance : date, horaires, salle, jury, statut, note.
  Widget _soutenance(Map<String, dynamic> s) {
    final debut = DateTime.tryParse(s['slot_start']?.toString() ?? '')?.toLocal();
    final fin = DateTime.tryParse(s['slot_end']?.toString() ?? '')?.toLocal();
    String heure(DateTime? d) => d == null
        ? '--:--'
        : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final note = s['final_average']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SgKv(
                label: 'Date',
                value: debut == null ? '—' : longDate(debut),
              ),
            ),
            SgStatusBadge(s['status']?.toString() ?? ''),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: SgKv(label: 'Horaires', value: '${heure(debut)} – ${heure(fin)}')),
            Expanded(child: SgKv(label: 'Salle', value: s['room_name']?.toString() ?? '')),
          ],
        ),
        const SizedBox(height: 12),
        SgKv(label: 'Jury', value: s['jury_name']?.toString() ?? ''),
        if (note != null) ...[
          const SizedBox(height: 16),
          // Note validée mise en valeur sur fond doré.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: AppColors.goldDeep),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Note finale validée',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${note.replaceAll('.', ',')} / 20',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.goldDeep,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Petite carte d'information générique (icône, titre, texte).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.titre, required this.texte});

  /// Icône illustrative.
  final IconData icon;

  /// Titre de la carte.
  final String titre;

  /// Texte explicatif.
  final String texte;

  @override
  Widget build(BuildContext context) {
    return SgCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.goldDeep),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(texte, style: const TextStyle(fontSize: 13, color: AppColors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Changement de mot de passe
// ===========================================================================

/// Formulaire de changement de mot de passe (actuel, nouveau, confirmation).
class _PasswordCard extends StatefulWidget {
  const _PasswordCard();

  @override
  State<_PasswordCard> createState() => _PasswordCardState();
}

/// État du formulaire : saisies, visibilité, envoi et erreur.
class _PasswordCardState extends State<_PasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _actuel = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();

  /// Vrai pour masquer les mots de passe saisis.
  bool _masque = true;

  /// Vrai pendant l'envoi au serveur.
  bool _envoi = false;

  /// Message d'erreur renvoyé par le serveur.
  String? _erreur;

  @override
  void dispose() {
    _actuel.dispose();
    _nouveau.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  /// Valide le formulaire puis demande le changement au serveur.
  Future<void> _valider() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await context.read<AuthProvider>().changePassword(
        _actuel.text,
        _nouveau.text,
      );
      if (!mounted) return;
      // Succès : on vide le formulaire et on confirme.
      _actuel.clear();
      _nouveau.clear();
      _confirmation.clear();
      SgToast.show(context, 'Mot de passe modifié avec succès.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } catch (_) {
      if (mounted) setState(() => _erreur = 'Le changement a échoué.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Bouton « œil » commun aux trois champs.
  Widget _oeil() => IconButton(
    tooltip: _masque ? 'Afficher' : 'Masquer',
    icon: Icon(
      _masque ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      size: 20,
    ),
    onPressed: () => setState(() => _masque = !_masque),
  );

  @override
  Widget build(BuildContext context) {
    return SgCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: AppColors.goldDeep),
                SizedBox(width: 10),
                Text(
                  'Changer mon mot de passe',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Au moins 8 caractères, en évitant les mots de passe trop simples.',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            const SizedBox(height: 18),
            if (_erreur != null) ...[
              SgBanner(
                message: _erreur!,
                tone: SgTone.danger,
                onClose: () => setState(() => _erreur = null),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _actuel,
              obscureText: _masque,
              decoration: InputDecoration(
                labelText: 'Mot de passe actuel',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: _oeil(),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Saisissez votre mot de passe actuel.' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nouveau,
              obscureText: _masque,
              decoration: const InputDecoration(
                labelText: 'Nouveau mot de passe',
                prefixIcon: Icon(Icons.lock_reset_rounded),
              ),
              validator: (v) {
                if (v == null || v.length < 8) return 'Au moins 8 caractères.';
                if (v == _actuel.text) return 'Choisissez un mot de passe différent.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmation,
              obscureText: _masque,
              decoration: const InputDecoration(
                labelText: 'Confirmer le nouveau mot de passe',
                prefixIcon: Icon(Icons.check_circle_outline_rounded),
              ),
              onFieldSubmitted: (_) => _valider(),
              validator: (v) => v != _nouveau.text
                  ? 'Les deux mots de passe ne correspondent pas.'
                  : null,
            ),
            const SizedBox(height: 20),
            SgButton(
              'Enregistrer le nouveau mot de passe',
              icon: Icons.check_rounded,
              expand: true,
              loading: _envoi,
              onPressed: _valider,
            ),
          ],
        ),
      ),
    );
  }
}
