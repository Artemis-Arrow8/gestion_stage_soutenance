/// Tableau de bord : page d'accueil de l'espace connecté.
///
/// Son contenu s'adapte au rôle :
/// * administrateur / responsable : indicateurs, prochaines soutenances,
///   charge de la semaine et accès rapides ;
/// * membre du jury : ses prochaines soutenances et la charge de la semaine ;
/// * étudiant : état de son dossier et accès à ses documents ;
/// * encadreur : accès aux dossiers qui lui sont affectés.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../providers/planning_store.dart';
import '../services/conflict_report.dart';
import '../services/planning_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/defense_tile.dart';
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';
import 'defense_form_screen.dart';

/// Écran du tableau de bord.
class DashboardScreen extends StatefulWidget {
  /// Crée le tableau de bord.
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// État du tableau de bord : déclenche le chargement du planning.
class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Chargement après la première image : le contexte est alors prêt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(force: false);
    });
  }

  /// Vrai si le rôle courant a accès au planning des soutenances.
  bool _voitPlanning(AuthProvider auth) =>
      auth.canManage || auth.role == 'jury';

  /// Charge (ou recharge si [force]) le planning partagé.
  Future<void> _load({required bool force}) async {
    final auth = context.read<AuthProvider>();
    if (!_voitPlanning(auth)) return;
    final service = PlanningService(auth.api);
    if (force) {
      try {
        await PlanningStore.refresh(service, loadCatalog: auth.canManage);
      } catch (_) {
        // L'erreur est publiée dans PlanningStore.error et affichée.
      }
    } else {
      await PlanningStore.ensureLoaded(service, loadCatalog: auth.canManage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.role;
    // Prénom seul pour une salutation plus naturelle.
    final prenom = auth.displayName.split(' ').first;
    final today = DateTime.now();

    return SgPage(
      section: AppSection.dashboard,
      title: 'Bonjour, $prenom',
      subtitle:
          '${Session.roleLabel(role)} · année universitaire ${anneeScolaire(today)}',
      onRefresh: _voitPlanning(auth) ? () => _load(force: true) : null,
      actions: [
        if (auth.canManage)
          SgButton(
            'Nouvelle soutenance',
            icon: Icons.add_rounded,
            onPressed: () => pushPage(context, const DefenseFormScreen()),
          ),
        if (_voitPlanning(auth))
          SgButton(
            role == 'jury' ? 'Mon planning' : 'Planning',
            icon: Icons.calendar_month_outlined,
            variant: SgBtnVariant.outline,
            onPressed: () => navigateToSection(context, AppSection.planning),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Banner(role: role),
          const SizedBox(height: 24),
          if (_voitPlanning(auth))
            _PlanningOverview(canManage: auth.canManage)
          else if (role == 'student')
            _StudentFolderCard(profile: auth.user ?? const {}),
          if (role == 'student') const SizedBox(height: 24),
          const SgSectionTitle(
            'Accès rapides',
            subtitle: 'Les modules disponibles pour votre profil.',
          ),
          const SizedBox(height: 12),
          _QuickActions(role: role),
          const SizedBox(height: 36),
          Center(
            child: Text(
              'SGSUS — Gestion des stages et des soutenances · © ${today.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.greyLight),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Bandeau d'accueil
// ===========================================================================

/// Bandeau sombre d'introduction, au message adapté au rôle.
class _Banner extends StatelessWidget {
  const _Banner({required this.role});

  /// Rôle de l'utilisateur connecté.
  final String? role;

  @override
  Widget build(BuildContext context) {
    final (surtitre, titre, texte) = switch (role) {
      'admin' || 'responsible' => (
        'ESPACE DE PLANIFICATION',
        'Organisez vos soutenances avec précision.',
        'Horaires, salles, jurys et documents réunis dans un seul espace.',
      ),
      'jury' => (
        'ESPACE JURY',
        'Retrouvez les soutenances qui vous attendent.',
        'Consultez les créneaux, les salles et les sujets de vos soutenances.',
      ),
      'supervisor' => (
        'ESPACE ENCADREUR',
        'Suivez les dossiers de vos étudiants.',
        'Consultez les rapports déposés et rendez vos avis de recevabilité.',
      ),
      _ => (
        'ESPACE ÉTUDIANT',
        'Votre stage, étape par étape.',
        'Déposez vos rapports et suivez l’avancement de votre dossier.',
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: AppTheme.inkGradient,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surtitre,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    titre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    texte,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            // Illustration masquée sur les écrans étroits.
            if (c.maxWidth > 520) ...[
              const SizedBox(width: 20),
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: AppColors.gold,
                  size: 32,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Vue d'ensemble du planning (personnel et jury)
// ===========================================================================

/// Indicateurs, prochaines soutenances et charge de la semaine.
class _PlanningOverview extends StatelessWidget {
  const _PlanningOverview({required this.canManage});

  /// Vrai pour le personnel (indicateurs complets et création).
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    // Trois sources observées : données, chargement et erreur.
    return ValueListenableBuilder<bool>(
      valueListenable: PlanningStore.loading,
      builder: (context, loading, _) => ValueListenableBuilder<String?>(
        valueListenable: PlanningStore.error,
        builder: (context, error, _) => ValueListenableBuilder<List<Defense>>(
          valueListenable: PlanningStore.defenses,
          builder: (context, defenses, _) =>
              _content(context, defenses, loading, error),
        ),
      ),
    );
  }

  /// Construit la vue une fois les trois états connus.
  Widget _content(
    BuildContext context,
    List<Defense> defenses,
    bool loading,
    String? error,
  ) {
    final today = DateTime.now();
    final debutJour = DateTime(today.year, today.month, today.day);
    // Soutenances à venir (aujourd'hui inclus), dans l'ordre chronologique.
    final aVenir = defenses.where((d) {
      final p = parseDefenseDate(d.date);
      return p != null && !p.isBefore(debutJour);
    }).toList()
      ..sort(
        (a, b) => '${a.date}${a.startTime}'.compareTo('${b.date}${b.startTime}'),
      );
    final aujourdhui = aVenir
        .where((d) => parseDefenseDate(d.date) == debutJour)
        .length;
    final conflits = canManage ? ConflictScanner.scan(defenses).length : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) ...[
          SgBanner(
            message: 'Le planning n’a pas pu être chargé : $error',
            tone: SgTone.danger,
          ),
          const SizedBox(height: 18),
        ],
        // Indicateurs chiffrés.
        _StatsGrid(
          cards: [
            SgStatCard(
              label: canManage ? 'Soutenances planifiées' : 'Mes soutenances',
              value: '${defenses.length}',
              icon: Icons.event_available_rounded,
              tone: SgTone.info,
            ),
            SgStatCard(
              label: 'Aujourd’hui',
              value: '$aujourdhui',
              icon: Icons.today_rounded,
              tone: SgTone.gold,
              foot: aVenir.isEmpty ? null : '${aVenir.length} à venir',
            ),
            if (canManage) ...[
              SgStatCard(
                label: 'Salles actives',
                value: '${PlanningStore.rooms.length}',
                icon: Icons.meeting_room_rounded,
                tone: SgTone.success,
              ),
              SgStatCard(
                label: 'Conflits détectés',
                value: '$conflits',
                icon: Icons.report_gmailerrorred_rounded,
                tone: conflits > 0 ? SgTone.danger : SgTone.success,
                foot: conflits > 0 ? 'Action requise' : 'Planning sain',
              ),
            ],
          ],
        ),
        const SizedBox(height: 28),
        SgSectionTitle(
          'Prochaines soutenances',
          subtitle: 'Les échéances les plus proches du calendrier.',
          action: SgButton(
            'Tout voir',
            variant: SgBtnVariant.ghost,
            dense: true,
            onPressed: () => navigateToSection(context, AppSection.planning),
          ),
        ),
        const SizedBox(height: 12),
        if (loading && defenses.isEmpty)
          const SgLoading(message: 'Chargement du planning…')
        else if (aVenir.isEmpty)
          SgEmpty(
            icon: Icons.event_available_outlined,
            title: 'Aucune soutenance à venir',
            message: canManage
                ? 'Créez une première soutenance pour alimenter le planning.'
                : 'Aucune soutenance ne vous est encore affectée.',
            action: canManage
                ? SgButton(
                    'Créer une soutenance',
                    icon: Icons.add_rounded,
                    onPressed: () =>
                        pushPage(context, const DefenseFormScreen()),
                  )
                : null,
          )
        else
          Column(
            children: [
              for (final d in aVenir.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DefenseTile(
                    defense: d,
                    onTap: () =>
                        pushPage(context, DefenseDetailScreen(defense: d)),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 28),
        const SgSectionTitle(
          'Charge de la semaine',
          subtitle: 'Nombre de soutenances sur les 7 prochains jours.',
        ),
        const SizedBox(height: 12),
        _WeekChart(defenses: defenses),
        const SizedBox(height: 28),
      ],
    );
  }
}

/// Grille adaptative d'indicateurs : 4, 2 ou 1 par ligne selon la largeur.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.cards});

  /// Cartes à disposer.
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 14.0;
        final perRow = c.maxWidth >= 980
            ? cards.length.clamp(1, 4)
            : (c.maxWidth >= 460 ? 2 : 1);
        final width = (c.maxWidth - (perRow - 1) * gap) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

/// Histogramme des soutenances des 7 prochains jours.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.defenses});

  /// Soutenances à répartir par jour.
  final List<Defense> defenses;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final jours = List.generate(7, (i) => today.add(Duration(days: i)));
    // Nombre de soutenances par jour, calculé une seule fois.
    final counts = [
      for (final j in jours)
        defenses.where((d) {
          final p = parseDefenseDate(d.date);
          return p != null && sameDay(p, j);
        }).length,
    ];
    // L'échelle s'adapte au jour le plus chargé (minimum 3).
    final maxCount = counts.fold<int>(3, (m, c) => c > m ? c : m);

    return SgCard(
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 520;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < jours.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      _bar(counts[i], maxCount, isToday: i == 0, compact: compact),
                      const SizedBox(height: 8),
                      Text(
                        compact
                            ? joursCourts[jours[i].weekday - 1].substring(0, 1)
                            : joursCourts[jours[i].weekday - 1],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: i == 0 ? AppColors.ink : AppColors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${jours[i].day}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.greyLight,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Barre d'un jour : hauteur proportionnelle au nombre de soutenances.
  Widget _bar(
    int count,
    int maxCount, {
    required bool isToday,
    required bool compact,
  }) {
    final height = 16.0 + (count / maxCount) * 64;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: compact ? 3 : 8),
      decoration: BoxDecoration(
        color: count == 0
            ? AppColors.neutralBg
            : (isToday ? AppColors.gold : AppColors.ink),
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: count == 0
          ? null
          : Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isToday ? AppColors.ink : Colors.white,
              ),
            ),
    );
  }
}

// ===========================================================================
// Carte « Mon dossier » (étudiant)
// ===========================================================================

/// Résumé du dossier de stage de l'étudiant connecté.
class _StudentFolderCard extends StatelessWidget {
  const _StudentFolderCard({required this.profile});

  /// Profil renvoyé par l'API (`student_number`, `folder_status`…).
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final statut = profile['folder_status']?.toString();
    final matricule = profile['student_number']?.toString() ?? '';
    return SgCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.folder_shared_rounded,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mon dossier de stage',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  statut == null
                      ? 'Aucun dossier ouvert pour la campagne en cours.'
                      : 'Matricule $matricule',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          if (statut != null) SgBadge(statut, tone: sgToneForStatus(statut)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Accès rapides
// ===========================================================================

/// Grille de cartes menant aux sections accessibles au rôle.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.role});

  /// Rôle de l'utilisateur connecté.
  final String? role;

  /// Titre d'une carte : formulé selon le rôle pour la section documents.
  String _titre(AppSection s) => switch (s) {
    AppSection.documents when role == 'student' =>
      'Mon dossier et mes documents',
    AppSection.documents when role == 'supervisor' =>
      'Dossiers affectés et avis d\'encadrement',
    AppSection.planning when role == 'jury' => 'Mon planning de jury',
    AppSection.campaigns => 'Gestion des campagnes',
    AppSection.accounts => 'Comptes et rôles',
    _ => s.label,
  };

  @override
  Widget build(BuildContext context) {
    final sections = Session.sections(
      role,
    ).where((s) => s != AppSection.dashboard).toList();
    if (sections.isEmpty) {
      return const SgEmpty(
        icon: Icons.lock_outline_rounded,
        title: 'Aucun module disponible',
        message: 'Le rôle de ce compte n’est pas reconnu. Contactez un administrateur.',
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final perRow = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
        final width = (c.maxWidth - (perRow - 1) * gap) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in sections)
              SizedBox(width: width, child: _card(context, s)),
          ],
        );
      },
    );
  }

  /// Carte cliquable d'une section.
  Widget _card(BuildContext context, AppSection s) {
    return SgCard(
      padding: const EdgeInsets.all(16),
      onTap: () => navigateToSection(context, s),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(s.iconActive, size: 20, color: AppColors.gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titre(s),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  s.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.greyLight,
          ),
        ],
      ),
    );
  }
}
