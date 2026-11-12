import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/conflict_report.dart';
import '../services/planning_store.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';
import '../screens/dashboard_screen.dart';
import '../screens/planning_screen.dart';
import '../screens/rooms_screen.dart';
import '../screens/jury_screen.dart';
import '../screens/conflicts_screen.dart';
import '../screens/documents_screen.dart';

enum AppSection { dashboard, planning, rooms, jury, conflicts, documents }

enum AppRole { admin, planificateur, jury, etudiant, encadreur }

class Session {
  static AppRole role = AppRole.planificateur;
  static const String nom = 'Mariam Diarra';

  static String get roleLabel => switch (role) {
        AppRole.admin => 'Administrateur',
        AppRole.planificateur => 'Planificatrice',
        AppRole.jury => 'Membre du jury',
        AppRole.etudiant => 'Étudiant',
        AppRole.encadreur => 'Encadreur',
      };

  static bool get peutGerer => role == AppRole.admin || role == AppRole.planificateur;

  static List<AppSection> get sections => switch (role) {
        AppRole.admin || AppRole.planificateur => AppSection.values,
        AppRole.jury || AppRole.etudiant => const [
            AppSection.dashboard,
            AppSection.planning,
            AppSection.documents,
          ],
        AppRole.encadreur => const [
            AppSection.dashboard,
            AppSection.planning,
            AppSection.jury,
            AppSection.documents,
          ],
      };
}

extension AppSectionX on AppSection {
  String get label => switch (this) {
        AppSection.dashboard => 'Tableau de bord',
        AppSection.planning => 'Planning',
        AppSection.rooms => 'Salles',
        AppSection.jury => 'Jurys',
        AppSection.conflicts => 'Conflits',
        AppSection.documents => 'Documents',
      };

  IconData get icon => switch (this) {
        AppSection.dashboard => Icons.space_dashboard_outlined,
        AppSection.planning => Icons.calendar_month_outlined,
        AppSection.rooms => Icons.meeting_room_outlined,
        AppSection.jury => Icons.groups_2_outlined,
        AppSection.conflicts => Icons.report_gmailerrorred_outlined,
        AppSection.documents => Icons.folder_open_outlined,
      };

  IconData get iconActive => switch (this) {
        AppSection.dashboard => Icons.space_dashboard_rounded,
        AppSection.planning => Icons.calendar_month_rounded,
        AppSection.rooms => Icons.meeting_room_rounded,
        AppSection.jury => Icons.groups_2_rounded,
        AppSection.conflicts => Icons.report_gmailerrorred_rounded,
        AppSection.documents => Icons.folder_open_rounded,
      };
}

Widget screenFor(AppSection section) => switch (section) {
      AppSection.dashboard => const DashboardScreen(),
      AppSection.planning => const PlanningScreen(),
      AppSection.rooms => const RoomsScreen(),
      AppSection.jury => const JuryScreen(),
      AppSection.conflicts => const ConflictsScreen(),
      AppSection.documents => const DocumentsScreen(),
    };

/// Conteneur commun : sidebar + topbar + en-tête + contenu scrollable.
class SgPage extends StatelessWidget {
  const SgPage({
    super.key,
    required this.section,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    required this.child,
    this.maxWidth = 1320,
  });

  final AppSection section;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final showSidebar = w >= 1080;
        final showRail = w >= 820 && !showSidebar;
        final padH = w >= 900 ? 28.0 : 16.0;

        return Scaffold(
          backgroundColor: AppColors.bg,
          drawer: showSidebar
              ? null
              : Drawer(
                  width: 272,
                  backgroundColor: AppColors.ink,
                  child: _Sidebar(current: section, expanded: true),
                ),
          body: Row(
            children: [
              if (showSidebar) _Sidebar(current: section, expanded: true),
              if (showRail) _Sidebar(current: section, expanded: false),
              Expanded(
                child: Column(
                  children: [
                    const _TopBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(padH, 22, padH, 32),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _header(w),
                                const SizedBox(height: 20),
                                child,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(double w) {
    final titleCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: w >= 700 ? 23 : 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: const TextStyle(
                fontSize: 13, color: AppColors.grey, height: 1.45),
          ),
        ],
      ],
    );

    if (actions.isEmpty) return titleCol;

    if (w < 640) {
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

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Row(
            children: [
              if (w < 1080)
                IconButton(
                  splashRadius: 20,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded, color: AppColors.ink),
                ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: AppColors.gold, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text('SGSUS',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4)),
              if (w > 620) ...[
                const Text('  ·  ',
                    style: TextStyle(fontSize: 12, color: AppColors.greyLight)),
                Text(Session.roleLabel,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.grey)),
              ],
              const Spacer(),
              const _NotifyButton(),
              const SizedBox(width: 12),
              Container(width: 1, height: 26, color: AppColors.line),
              const SizedBox(width: 12),
              _ProfileButton(compact: w < 760),
            ],
          );
        },
      ),
    );
  }
}

class _NotifyButton extends StatelessWidget {
  const _NotifyButton();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, defenses, _) {
        final count = ConflictScanner.scan(defenses).length;
        return Tooltip(
          message: 'Conflits et notifications',
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ConflictsScreen()),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.line),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications_none_rounded,
                      size: 18, color: AppColors.ink),
                  if (count > 0)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700),
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

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.compact});

  final bool compact;

  static String libelle(AppRole r) => switch (r) {
        AppRole.admin => 'Administrateur',
        AppRole.planificateur => 'Planificateur',
        AppRole.jury => 'Membre du jury',
        AppRole.etudiant => 'Étudiant',
        AppRole.encadreur => 'Encadreur',
      };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppRole>(
      tooltip: 'Compte',
      offset: const Offset(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (role) {
        Session.role = role;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
      },
      itemBuilder: (context) => [
        const PopupMenuItem<AppRole>(
          enabled: false,
          child: Text('CHANGER DE PROFIL (DÉMO)',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: .7,
                  fontWeight: FontWeight.w700,
                  color: AppColors.greyLight)),
        ),
        for (final r in AppRole.values)
          PopupMenuItem<AppRole>(
            value: r,
            child: Row(
              children: [
                Icon(
                  r == Session.role
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: r == Session.role ? AppColors.gold : AppColors.greyLight,
                ),
                const SizedBox(width: 10),
                Text(libelle(r), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Row(
        children: [
          const SgAvatar(initials: 'MD', size: 34),
          if (!compact) ...[
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(Session.nom,
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text(Session.roleLabel,
                    style: const TextStyle(fontSize: 11, color: AppColors.grey)),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppColors.grey),
          ],
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.expanded});

  final AppSection current;
  final bool expanded;

  void _go(BuildContext context, AppSection section) {
    final scaf = Scaffold.maybeOf(context);
    if (scaf != null && scaf.isDrawerOpen) scaf.closeDrawer();
    if (section == current) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screenFor(section)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = Session.sections;
    return Container(
      width: expanded ? 264 : 78,
      color: AppColors.ink,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  expanded ? 20 : 0, 22, expanded ? 20 : 0, 16),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: AppTheme.goldLine,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.school_rounded,
                        size: 20, color: AppColors.ink),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 11),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('SGSUS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.6,
                                height: 1.1)),
                        SizedBox(height: 2),
                        Text('Soutenances',
                            style: TextStyle(
                                color: Color(0xFF8C8C8C), fontSize: 10.5)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202020),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: const Color(0xFF2E2E2E)),
                  ),
                  child: Row(
                    children: [
                      const SgAvatar(initials: 'MD', size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(Session.nom,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(Session.roleLabel,
                                style: const TextStyle(
                                    color: Color(0xFF9A9A9A), fontSize: 10.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Divider(color: Color(0xFF2C2C2C), height: 8),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  if (expanded)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(9, 2, 9, 8),
                      child: Text('NAVIGATION',
                          style: TextStyle(
                              color: Color(0xFF6E6E6E),
                              fontSize: 9.5,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700)),
                    ),
                  for (final s in items) _item(context, s),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2C2C2C), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: _logout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logout() {
    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0, vertical: 11),
      child: Row(
        mainAxisAlignment:
            expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          const Icon(Icons.logout_rounded, size: 17, color: Color(0xFFB0B0B0)),
          if (expanded) ...[
            const SizedBox(width: 11),
            const Text('Déconnexion',
                style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 12.5)),
          ],
        ],
      ),
    );
    final tappable = InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () {},
      child: content,
    );
    return expanded ? tappable : Tooltip(message: 'Déconnexion', child: tappable);
  }

  Widget _item(BuildContext context, AppSection s) {
    final active = s == current;
    final content = Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 9 : 0, vertical: 11),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF262626) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisAlignment:
            expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          if (active && expanded) ...[
            Container(
              width: 3,
              height: 17,
              margin: const EdgeInsets.only(right: 9),
              decoration: BoxDecoration(
                  color: AppColors.gold, borderRadius: BorderRadius.circular(2)),
            ),
          ],
          Icon(
            active ? s.iconActive : s.icon,
            size: 18,
            color: active ? AppColors.gold : const Color(0xFFB0B0B0),
          ),
          if (expanded) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.label,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFFC8C8C8),
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final tappable = InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => _go(context, s),
      child: content,
    );
    return expanded ? tappable : Tooltip(message: s.label, child: tappable);
  }
}