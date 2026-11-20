/// Coque de l'espace connecté : navigation par sections et mise en page
/// adaptative commune à tous les écrans.
///
/// * Grand écran (≥ [AppBreakpoints.expanded]) : barre latérale complète.
/// * Tablette (≥ [AppBreakpoints.compact]) : rail d'icônes compact.
/// * Téléphone : conçu pour l'usage à UNE MAIN (inspiré du mode Samsung) :
///   - barre de navigation en BAS de l'écran, à portée du pouce ;
///   - bouton « Menu » qui ouvre tous les modules en grandes cartes ;
///   - grand titre en haut : le contenu et les boutons descendent vers le
///     pouce ;
///   - actions de la page regroupées juste au-dessus de la barre du bas ;
///   - geste « retour » (glisser) : revient à l'écran précédent ; depuis
///     l'accueil, il faut le refaire une seconde fois pour quitter.
///
/// Chaque écran se construit avec [SgPage] en indiquant sa section, son
/// titre et ses actions ; la coque se charge du reste.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/network/hors_ligne.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../providers/planning_store.dart';
import '../screens/accounts_screen.dart';
import '../screens/campaigns_screen.dart';
import '../screens/conflicts_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/documents_screen.dart';
import '../screens/evaluations_screen.dart';
import '../screens/jury_screen.dart';
import '../screens/planning_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/rooms_screen.dart';
import '../services/conflict_report.dart';
import 'ui_kit.dart';

// ===========================================================================
// Sections et droits d'accès
// ===========================================================================

/// Sections principales de l'application.
enum AppSection {
  dashboard,
  campaigns,
  accounts,
  planning,
  rooms,
  jury,
  conflicts,
  evaluations,
  documents,
  profil,
}

/// Règles d'accès aux sections selon le rôle de l'utilisateur.
abstract final class Session {
  /// Libellé français d'un rôle technique.
  static String roleLabel(String? role) => AuthProvider.roleLabel(role);

  /// Vrai si l'utilisateur courant peut gérer le planning.
  static bool peutGerer(BuildContext context) =>
      context.read<AuthProvider>().canManage;

  /// Sections visibles par un [role], dans l'ordre du menu.
  ///
  /// Ces règles reflètent les permissions de l'API : masquer une section
  /// évite d'afficher un écran dont toutes les requêtes seraient refusées.
  static List<AppSection> sections(String? role) => switch (role) {
    'admin' => const [
      AppSection.dashboard,
      AppSection.campaigns,
      AppSection.accounts,
      AppSection.planning,
      AppSection.rooms,
      AppSection.jury,
      AppSection.conflicts,
      AppSection.evaluations,
      AppSection.documents,
      AppSection.profil,
    ],
    'responsible' => const [
      AppSection.dashboard,
      AppSection.campaigns,
      AppSection.planning,
      AppSection.rooms,
      AppSection.jury,
      AppSection.conflicts,
      AppSection.evaluations,
      AppSection.documents,
      AppSection.profil,
    ],
    // Le jury consulte ses soutenances, LIT les rapports avant le jour J
    // (« Rapports à lire ») et saisit les notes (chapitre 2).
    'jury' => const [
      AppSection.dashboard,
      AppSection.planning,
      AppSection.documents,
      AppSection.evaluations,
      AppSection.profil,
    ],
    'student' => const [
      AppSection.dashboard,
      AppSection.documents,
      AppSection.profil,
    ],
    'supervisor' => const [
      AppSection.dashboard,
      AppSection.documents,
      AppSection.profil,
    ],
    _ => const [AppSection.dashboard],
  };
}

/// Métadonnées d'affichage de chaque section.
extension AppSectionX on AppSection {
  /// Libellé court (menu).
  String get label => switch (this) {
    AppSection.dashboard => 'Tableau de bord',
    AppSection.campaigns => 'Campagnes',
    AppSection.accounts => 'Comptes',
    AppSection.planning => 'Planning',
    AppSection.rooms => 'Salles',
    AppSection.jury => 'Jurys',
    AppSection.conflicts => 'Conflits',
    AppSection.evaluations => 'Évaluations',
    AppSection.documents => 'Documents',
    AppSection.profil => 'Mon profil',
  };

  /// Description d'une phrase (cartes d'accès rapide).
  String get description => switch (this) {
    AppSection.dashboard => 'Vue d’ensemble de votre activité.',
    AppSection.campaigns => 'Années académiques et sessions.',
    AppSection.accounts => 'Comptes, rôles et rattachements.',
    AppSection.planning => 'Calendrier jour, semaine et mois.',
    AppSection.rooms => 'Occupation et disponibilité des salles.',
    AppSection.jury => 'Membres et charge des jurys.',
    AppSection.conflicts => 'Chevauchements à arbitrer.',
    AppSection.evaluations => 'Notes, approbation et procès-verbaux.',
    AppSection.documents => 'Dossiers, rapports et avis.',
    AppSection.profil => 'Vos informations et votre mot de passe.',
  };

  /// Icône au repos.
  IconData get icon => switch (this) {
    AppSection.dashboard => Icons.space_dashboard_outlined,
    AppSection.campaigns => Icons.calendar_today_outlined,
    AppSection.accounts => Icons.manage_accounts_outlined,
    AppSection.planning => Icons.calendar_month_outlined,
    AppSection.rooms => Icons.meeting_room_outlined,
    AppSection.jury => Icons.groups_2_outlined,
    AppSection.conflicts => Icons.report_gmailerrorred_outlined,
    AppSection.evaluations => Icons.workspace_premium_outlined,
    AppSection.documents => Icons.folder_open_outlined,
    AppSection.profil => Icons.person_outline_rounded,
  };

  /// Icône de la section active.
  IconData get iconActive => switch (this) {
    AppSection.dashboard => Icons.space_dashboard_rounded,
    AppSection.campaigns => Icons.calendar_today_rounded,
    AppSection.accounts => Icons.manage_accounts_rounded,
    AppSection.planning => Icons.calendar_month_rounded,
    AppSection.rooms => Icons.meeting_room_rounded,
    AppSection.jury => Icons.groups_2_rounded,
    AppSection.conflicts => Icons.report_gmailerrorred_rounded,
    AppSection.evaluations => Icons.workspace_premium_rounded,
    AppSection.documents => Icons.folder_open_rounded,
    AppSection.profil => Icons.person_rounded,
  };
}

/// Retourne l'écran correspondant à une [section].
Widget screenFor(AppSection section) => switch (section) {
  AppSection.dashboard => const DashboardScreen(),
  AppSection.campaigns => const CampaignsScreen(),
  AppSection.accounts => const AccountsScreen(),
  AppSection.planning => const PlanningScreen(),
  AppSection.rooms => const RoomsScreen(),
  AppSection.jury => const JuryScreen(),
  AppSection.conflicts => const ConflictsScreen(),
  AppSection.evaluations => const EvaluationsScreen(),
  AppSection.documents => const DocumentsScreen(),
  AppSection.profil => const ProfileScreen(),
};

/// Ouvre une [section] depuis le menu principal.
///
/// La route racine (aiguillage de session, qui affiche le tableau de bord)
/// est toujours conservée : on remplace seulement les écrans empilés
/// au-dessus. Ainsi, une déconnexion ramène toujours à la connexion.
void navigateToSection(BuildContext context, AppSection section) {
  final navigator = Navigator.of(context);
  if (section == AppSection.dashboard) {
    navigator.popUntil((route) => route.isFirst);
    return;
  }
  navigator.pushAndRemoveUntil(
    _route(screenFor(section)),
    (route) => route.isFirst,
  );
}

/// Ouvre un écran secondaire (fiche, formulaire) par-dessus l'écran courant.
///
/// Retourne la valeur renvoyée par l'écran à sa fermeture (ex. `true` après
/// une création réussie).
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(_route<T>(page));
}

/// Remplace l'écran courant par [page] (ex. fiche rechargée après une
/// modification).
Future<void> replacePage(BuildContext context, Widget page) {
  return Navigator.of(context).pushReplacement(_route<void>(page));
}

/// Route standard Material : ses transitions viennent du thème
/// (`AppTheme.light.pageTransitionsTheme`). Elle prend en charge les gestes
/// de retour de chaque plateforme : glissement depuis le bord (iPhone),
/// geste « retour » prédictif (Android), bouton ou geste retour du
/// navigateur (Web).
PageRoute<T> _route<T>(Widget page) =>
    MaterialPageRoute<T>(builder: (_) => page);

// ===========================================================================
// Mise en page commune
// ===========================================================================

/// Gabarit de page : navigation, barre supérieure, en-tête et contenu.
class SgPage extends StatelessWidget {
  /// Crée une page.
  ///
  /// * [section] : section mise en évidence dans le menu ;
  /// * [title] / [subtitle] : en-tête de la page ;
  /// * [actions] : boutons affichés à droite du titre ;
  /// * [onRefresh] : active le « tirer pour actualiser » ;
  /// * [maxWidth] : largeur maximale du contenu sur grand écran.
  const SgPage({
    super.key,
    required this.section,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    required this.child,
    this.onRefresh,
    this.maxWidth = 1280,
  });

  /// Section active dans le menu.
  final AppSection section;

  /// Titre de la page.
  final String title;

  /// Sous-titre facultatif.
  final String? subtitle;

  /// Actions principales de la page.
  final List<Widget> actions;

  /// Contenu de la page.
  final Widget child;

  /// Rappel d'actualisation (glisser vers le bas).
  final Future<void> Function()? onRefresh;

  /// Largeur maximale du contenu.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final showSidebar = w >= AppBreakpoints.expanded;
        final showRail = w >= AppBreakpoints.compact && !showSidebar;
        // Téléphone : navigation à une main, en bas de l'écran.
        final mobile = !showSidebar && !showRail;
        // Marges latérales plus généreuses sur grand écran.
        final padH = w >= AppBreakpoints.medium ? 32.0 : 16.0;
        // Mode « une main » : grand espace au-dessus du titre (environ 12 %
        // de la hauteur) pour que le contenu descende vers le pouce.
        final hauteur = MediaQuery.sizeOf(context).height;
        final espaceHaut = mobile ? (hauteur * 0.12).clamp(24.0, 110.0) : 24.0;

        Widget content = SingleChildScrollView(
          // Toujours défilable pour que « tirer pour actualiser » fonctionne.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(padH, espaceHaut, padH, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sur téléphone, les actions vont en bas (zone du pouce).
                  _header(w, avecActions: !mobile),
                  const SizedBox(height: 24),
                  child,
                ],
              ),
            ),
          ),
        );
        if (onRefresh != null) {
          content = RefreshIndicator(onRefresh: onRefresh!, child: content);
        }

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: Row(
            children: [
              if (showSidebar) _Sidebar(current: section, expanded: true),
              if (showRail) _Sidebar(current: section, expanded: false),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(compact: mobile),
                    // Bandeau visible seulement sans connexion au serveur.
                    _BandeauHorsLigne(onRetry: onRefresh),
                    Expanded(child: content),
                  ],
                ),
              ),
            ],
          ),
          // Téléphone : actions de la page + barre de navigation, en bas.
          bottomNavigationBar: mobile
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (actions.isNotEmpty) _BarreActions(actions: actions),
                    _BottomNav(current: section),
                  ],
                )
              : null,
        );
      },
    );
  }

  /// En-tête : titre, sous-titre et, si [avecActions], les actions.
  ///
  /// Sur téléphone, le titre est plus grand (style « une main ») et les
  /// actions sont affichées en bas de l'écran par [_BarreActions].
  Widget _header(double w, {required bool avecActions}) {
    final titleCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: w >= 700 ? 26 : 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            height: 1.2,
            color: AppColors.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.grey,
              height: 1.45,
            ),
          ),
        ],
      ],
    );

    if (actions.isEmpty || !avecActions) return titleCol;

    // Écran étroit : actions sous le titre, sur plusieurs lignes si besoin.
    if (w < AppBreakpoints.compact + 40) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleCol,
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleCol),
        const SizedBox(width: 16),
        Wrap(spacing: 10, runSpacing: 10, children: actions),
      ],
    );
  }
}

// ===========================================================================
// Barre supérieure
// ===========================================================================

/// Barre supérieure : marque, alertes et compte.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.compact});

  /// Version allégée pour téléphone (la navigation est en bas d'écran).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Vrai sur tout écran ouvert par-dessus l'accueil (module, fiche,
    // formulaire) : une flèche « Retour » est alors affichée, en plus du
    // geste de glissement depuis le bord de l'écran.
    final peutRevenir = ModalRoute.of(context)?.canPop ?? false;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // Filet doré en bas de la barre : rappel discret de la charte.
      foregroundDecoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.gold, width: 2)),
      ),
      decoration: const BoxDecoration(color: AppColors.white),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Row(
            children: [
              // Flèche « Retour » : même effet que le geste de glissement
              // (`maybePop` respecte la garde des formulaires en cours).
              if (peutRevenir)
                IconButton(
                  tooltip: 'Retour',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                )
              else
                const SizedBox(width: 4),
              // Rappel de marque, utile quand la barre latérale est masquée.
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                AppConfig.appName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              if (!compact && w > 560) ...[
                const Text(
                  '  ·  ',
                  style: TextStyle(fontSize: 12, color: AppColors.greyLight),
                ),
                Flexible(
                  child: Text(
                    Session.roleLabel(auth.role),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.grey,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Alerte de conflits : seulement pour qui peut les traiter.
              if (auth.canManage) ...[
                const _ConflictBell(),
                const SizedBox(width: 10),
              ],
              // L'avatar ouvre la page « Mon profil ».
              Tooltip(
                message: 'Mon profil',
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => navigateToSection(context, AppSection.profil),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _ProfileChip(compact: w < 720),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Se déconnecter',
                onPressed: () => context.read<AuthProvider>().logout(),
                icon: const Icon(
                  Icons.logout_rounded,
                  size: 20,
                  color: AppColors.grey,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cloche affichant le nombre de conflits détectés dans le planning.
class _ConflictBell extends StatelessWidget {
  const _ConflictBell();

  @override
  Widget build(BuildContext context) {
    // Se met à jour automatiquement à chaque rechargement du planning.
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, defenses, _) {
        final count = ConflictScanner.scan(defenses).length;
        return Tooltip(
          message: count == 0
              ? 'Aucun conflit détecté'
              : '$count conflit(s) à traiter',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => navigateToSection(context, AppSection.conflicts),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.notifications_none_rounded,
                    size: 19,
                    color: AppColors.ink,
                  ),
                  if (count > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Avatar et nom de l'utilisateur connecté (nom masqué si [compact]).
class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.compact});

  /// Affiche seulement l'avatar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.displayName;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SgAvatar(initials: initiales(name), size: 34),
        if (!compact) ...[
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                Session.roleLabel(auth.role),
                style: const TextStyle(fontSize: 11, color: AppColors.grey),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Barre latérale
// ===========================================================================

/// Menu de navigation sombre (complet si [expanded], sinon rail d'icônes).
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.expanded});

  /// Section active.
  final AppSection current;

  /// Version complète (libellés) ou réduite (icônes seules).
  final bool expanded;

  /// Ferme le tiroir éventuel puis ouvre la section [section].
  void _go(BuildContext context, AppSection section) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
    if (section == current) return;
    navigateToSection(context, section);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final items = Session.sections(auth.role);
    return Container(
      width: expanded ? 264 : 80,
      color: AppColors.ink,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            _brand(),
            if (expanded) _userCard(auth),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Divider(color: AppColors.sidebarLine, height: 1),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  if (expanded)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(10, 2, 10, 10),
                      child: Text(
                        'NAVIGATION',
                        style: TextStyle(
                          color: AppColors.sidebarMuted,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  for (final s in items) _item(context, s),
                ],
              ),
            ),
            const Divider(color: AppColors.sidebarLine, height: 1),
            Padding(padding: const EdgeInsets.all(12), child: _logout(context)),
          ],
        ),
      ),
    );
  }

  /// Logo et nom de l'application.
  Widget _brand() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        expanded ? 20 : 0,
        22,
        expanded ? 20 : 0,
        16,
      ),
      child: Row(
        mainAxisAlignment: expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppTheme.goldLine,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.school_rounded,
              size: 21,
              color: AppColors.ink,
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConfig.appName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Stages & soutenances',
                  style: TextStyle(color: AppColors.greyLight, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Carte « utilisateur connecté » de la barre complète.
  Widget _userCard(AuthProvider auth) {
    final name = auth.displayName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.sidebarActive,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SgAvatar(initials: initiales(name), size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Session.roleLabel(auth.role),
                    style: const TextStyle(
                      color: AppColors.greyLight,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bouton de déconnexion en bas du menu.
  Widget _logout(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 12 : 0,
        vertical: 11,
      ),
      child: Row(
        mainAxisAlignment: expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.logout_rounded,
            size: 18,
            color: AppColors.sidebarText,
          ),
          if (expanded) ...[
            const SizedBox(width: 12),
            const Text(
              'Déconnexion',
              style: TextStyle(color: AppColors.sidebarText, fontSize: 13),
            ),
          ],
        ],
      ),
    );
    final tappable = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.read<AuthProvider>().logout(),
      child: content,
    );
    return expanded
        ? tappable
        : Tooltip(message: 'Déconnexion', child: tappable);
  }

  /// Entrée de menu d'une section (mise en évidence si active).
  Widget _item(BuildContext context, AppSection s) {
    final active = s == current;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 12 : 0,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: active ? AppColors.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Icon(
            active ? s.iconActive : s.icon,
            size: 19,
            color: active ? AppColors.gold : AppColors.sidebarText,
          ),
          if (expanded) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.sidebarText,
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            // Repère doré de la section active.
            if (active)
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.gold,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ],
      ),
    );

    final tappable = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _go(context, s),
      child: content,
    );
    // En mode rail, l'infobulle remplace le libellé masqué.
    return expanded ? tappable : Tooltip(message: s.label, child: tappable);
  }
}

// ===========================================================================
// Navigation « une main » (téléphone)
// ===========================================================================

/// Sections affichées directement dans la barre du bas, selon le rôle.
///
/// Au plus 3 sections + « Menu » : des cibles larges, faciles à atteindre
/// avec le pouce. Les autres modules sont dans le menu en cartes.
List<AppSection> _sectionsBarre(String? role) {
  final toutes = Session.sections(role);
  const prioritaires = [
    AppSection.dashboard,
    AppSection.planning,
    AppSection.documents,
    AppSection.profil,
  ];
  final choisies = prioritaires.where(toutes.contains).toList();
  // Avec un menu « Plus », on garde 3 sections pour laisser sa place.
  return toutes.length > choisies.length ? choisies.take(3).toList() : choisies;
}

/// Barre de navigation en bas de l'écran (téléphone).
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current});

  /// Section active.
  final AppSection current;

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().role;
    final barre = _sectionsBarre(role);
    final avecMenu = Session.sections(role).length > barre.length;
    // La section courante peut ne pas figurer dans la barre : on surligne
    // alors « Menu ».
    final index = barre.contains(current)
        ? barre.indexOf(current)
        : (avecMenu ? barre.length : 0);

    return NavigationBar(
      height: 68,
      backgroundColor: AppColors.white,
      indicatorColor: AppColors.goldSoft,
      surfaceTintColor: Colors.transparent,
      selectedIndex: index,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) {
        if (i < barre.length) {
          if (barre[i] != current) navigateToSection(context, barre[i]);
        } else {
          _ouvrirMenu(context, current);
        }
      },
      destinations: [
        for (final s in barre)
          NavigationDestination(
            icon: Icon(s.icon, color: AppColors.grey),
            selectedIcon: Icon(s.iconActive, color: AppColors.goldDeep),
            label: s == AppSection.dashboard ? 'Accueil' : s.label,
          ),
        if (avecMenu)
          const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded, color: AppColors.grey),
            selectedIcon: Icon(
              Icons.grid_view_rounded,
              color: AppColors.goldDeep,
            ),
            label: 'Menu',
          ),
      ],
    );
  }
}

/// Ouvre le menu complet : tous les modules en grandes cartes, en bas de
/// l'écran (atteignables d'une main), plus la déconnexion.
void _ouvrirMenu(BuildContext context, AppSection current) {
  final auth = context.read<AuthProvider>();
  final sections = Session.sections(auth.role);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Tous les modules',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            // Grille de cartes : 3 par ligne, grandes cibles tactiles.
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                for (final s in sections)
                  _CarteMenu(
                    section: s,
                    active: s == current,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (s != current) navigateToSection(context, s);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SgButton(
              'Se déconnecter',
              icon: Icons.logout_rounded,
              variant: SgBtnVariant.outline,
              expand: true,
              onPressed: () {
                Navigator.pop(ctx);
                auth.logout();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Carte d'un module dans le menu complet.
class _CarteMenu extends StatelessWidget {
  const _CarteMenu({
    required this.section,
    required this.active,
    required this.onTap,
  });

  /// Module représenté.
  final AppSection section;

  /// Vrai si c'est le module affiché actuellement.
  final bool active;

  /// Action au toucher.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.ink : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                section.iconActive,
                size: 26,
                color: active ? AppColors.gold : AppColors.goldDeep,
              ),
              const SizedBox(height: 8),
              Text(
                section.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre des actions de la page, posée au-dessus de la navigation du bas
/// sur téléphone (zone naturelle du pouce).
class _BarreActions extends StatelessWidget {
  const _BarreActions({required this.actions});

  /// Boutons d'action de la page.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      // Défilement horizontal si les boutons ne tiennent pas sur une ligne.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              actions[i],
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Bandeau « Mode hors ligne »
// ===========================================================================

/// Bandeau noir et or affiché sous la barre supérieure quand le serveur
/// est injoignable.
///
/// Il indique de quand datent les données affichées (mémorisées lors de la
/// dernière connexion) et rappelle que les modifications attendent le
/// retour du réseau. « Réessayer » relance le chargement de la page ; dès
/// qu'une réponse arrive du serveur, le bandeau disparaît tout seul.
class _BandeauHorsLigne extends StatelessWidget {
  const _BandeauHorsLigne({this.onRetry});

  /// Rechargement de la page (null : pas de bouton « Réessayer »).
  final Future<void> Function()? onRetry;

  /// Date courte et heure : « 19/11 à 14:32 ».
  static String _quand(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)} à ${deux(d.hour)}:${deux(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HorsLigne.actif,
      builder: (context, actif, _) {
        if (!actif) return const SizedBox.shrink();
        return ValueListenableBuilder<DateTime?>(
          valueListenable: HorsLigne.donneesDu,
          builder: (context, date, _) => Material(
            color: AppColors.ink,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: AppColors.gold,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mode hors ligne',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          date == null
                              ? 'Serveur injoignable. Les modifications '
                                    'attendront le retour de la connexion.'
                              : 'Données du ${_quand(date)}. Les '
                                    'modifications attendront la connexion.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.gold,
                      ),
                      child: const Text('Réessayer'),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
