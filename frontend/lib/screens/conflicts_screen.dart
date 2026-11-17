/// Gestion des conflits de planning (salles ou jurys réservés deux fois
/// sur des créneaux qui se chevauchent).
///
/// La détection est faite localement à partir du planning partagé
/// (voir `ConflictScanner`). Pour chaque conflit, l'écran présente les
/// soutenances concernées et une piste de résolution ; la correction se
/// fait ensuite sur la soutenance elle-même.
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
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';

/// Écran des conflits.
class ConflictsScreen extends StatefulWidget {
  /// Crée l'écran des conflits.
  const ConflictsScreen({super.key});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

/// État de l'écran : conflits masqués pendant la session.
class _ConflictsScreenState extends State<ConflictsScreen> {
  late final PlanningService _service;
  late final bool _peutGerer;

  /// Clés des conflits masqués par l'utilisateur (non persistées).
  final Set<String> _masques = {};

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _service = PlanningService(auth.api);
    _peutGerer = auth.canManage;
    PlanningStore.ensureLoaded(_service, loadCatalog: _peutGerer);
  }

  /// Recharge le planning depuis le serveur et réaffiche les conflits masqués.
  Future<void> _actualiser() async {
    setState(_masques.clear);
    try {
      await PlanningStore.refresh(_service, loadCatalog: _peutGerer);
    } catch (_) {
      // Erreur publiée dans PlanningStore.error et affichée ci-dessous.
    }
  }

  /// Retourne la soutenance de l'étudiant en conflit puis celles qui la
  /// chevauchent (même jour, même salle ou même jury).
  List<Defense> _concernees(ConflitItem item, List<Defense> all) {
    final mine = all.where((d) => d.studentName == item.etudiant).toList();
    if (mine.isEmpty) return const [];
    final d0 = mine.first;
    final autres = all.where(
      (d) =>
          d.id != d0.id &&
          ConflictScanner.findConflicts(d0, [d], ignoreId: d0.id).isNotEmpty,
    );
    return [d0, ...autres];
  }

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.conflicts,
      title: 'Gestion des conflits',
      subtitle:
          'Détection automatique des chevauchements de salles et de jurys.',
      onRefresh: _actualiser,
      actions: [
        SgButton(
          'Actualiser',
          icon: Icons.refresh_rounded,
          variant: SgBtnVariant.outline,
          onPressed: _actualiser,
        ),
      ],
      child: ValueListenableBuilder<bool>(
        valueListenable: PlanningStore.loading,
        builder: (context, loading, _) => ValueListenableBuilder<String?>(
          valueListenable: PlanningStore.error,
          builder: (context, error, _) => ValueListenableBuilder<List<Defense>>(
            valueListenable: PlanningStore.defenses,
            builder: (context, all, _) {
              if (loading && all.isEmpty) {
                return const SgLoading(message: 'Analyse du planning…');
              }
              if (error != null && all.isEmpty) {
                return SgErrorState(
                  title: 'Impossible de charger le planning',
                  message: error,
                  onRetry: _actualiser,
                );
              }
              return _contenu(all);
            },
          ),
        ),
      ),
    );
  }

  /// Indicateurs puis liste des conflits non masqués.
  Widget _contenu(List<Defense> all) {
    final items = ConflictScanner.scan(
      all,
    ).where((c) => !_masques.contains(c.key)).toList();
    final salles = items.where((i) => i.kind == ConflictKind.salle).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final perRow = c.maxWidth >= 720 ? 3 : 1;
            final w = (c.maxWidth - (perRow - 1) * gap) / perRow;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: w,
                  child: SgStatCard(
                    label: 'Conflits à traiter',
                    value: '${items.length}',
                    icon: Icons.report_gmailerrorred_rounded,
                    tone: items.isEmpty ? SgTone.success : SgTone.danger,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: SgStatCard(
                    label: 'Conflits de salles',
                    value: '$salles',
                    icon: Icons.meeting_room_outlined,
                    tone: SgTone.warning,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: SgStatCard(
                    label: 'Conflits de jurys',
                    value: '${items.length - salles}',
                    icon: Icons.groups_2_outlined,
                    tone: SgTone.info,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (_masques.isNotEmpty) ...[
          SgBanner(
            message:
                '${_masques.length} conflit(s) masqué(s) pour cette session. '
                'Ils réapparaîtront à la prochaine actualisation tant que '
                'les soutenances concernées n’auront pas été corrigées.',
            tone: SgTone.info,
          ),
          const SizedBox(height: 16),
        ],
        if (items.isEmpty)
          const SgEmpty(
            icon: Icons.verified_outlined,
            tone: SgTone.success,
            title: 'Aucun conflit détecté',
            message:
                'Les salles et les jurys ne sont pas réservés deux fois au même moment.',
          )
        else ...[
          Text(
            '${items.length} conflit(s) à traiter',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _carte(item, all),
            ),
        ],
      ],
    );
  }

  /// Piste de résolution adaptée au type de conflit.
  String _piste(ConflictKind kind) => switch (kind) {
    ConflictKind.salle =>
      'Piste : affecter une autre salle libre sur ce créneau, ou décaler '
          'l’une des soutenances.',
    ConflictKind.jury =>
      'Piste : replanifier l’une des soutenances sur un créneau où le jury '
          'est disponible, ou confier la soutenance à un autre jury.',
    ConflictKind.horaire =>
      'Piste : espacer les deux soutenances ou les placer dans des salles '
          'différentes.',
  };

  /// Carte d'un conflit : type, description, soutenances et actions.
  Widget _carte(ConflitItem item, List<Defense> all) {
    final concernees = _concernees(item, all);
    final tone = item.kind == ConflictKind.salle
        ? SgTone.warning
        : SgTone.danger;
    final (fg, bg) = sgTones(tone);

    return SgCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bandeau coloré du type de conflit.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            color: bg,
            child: Row(
              children: [
                Icon(
                  item.kind == ConflictKind.salle
                      ? Icons.meeting_room_outlined
                      : Icons.warning_amber_rounded,
                  size: 17,
                  color: fg,
                ),
                const SizedBox(width: 8),
                Text(
                  item.typeLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.etudiant,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.grey,
                    height: 1.5,
                  ),
                ),
                if (concernees.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const SgOverline('Soutenances concernées'),
                  const SizedBox(height: 8),
                  for (final d in concernees)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          pushPage(context, DefenseDetailScreen(defense: d)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_rounded,
                              size: 15,
                              color: AppColors.greyLight,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${d.studentName} · '
                                '${parseDefenseDate(d.date) == null ? d.date : shortDate(parseDefenseDate(d.date)!)}'
                                ' · ${d.startTime}–${d.endTime} · ${d.roomName}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 17,
                              color: AppColors.greyLight,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                // Piste de résolution (aide, sans action automatique).
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 17,
                        color: AppColors.goldDeep,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _piste(item.kind),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.grey,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (concernees.isNotEmpty)
                      SgButton(
                        'Ouvrir la soutenance',
                        icon: Icons.open_in_new_rounded,
                        dense: true,
                        onPressed: () => pushPage(
                          context,
                          DefenseDetailScreen(defense: concernees.first),
                        ),
                      ),
                    SgButton(
                      'Masquer pour cette session',
                      icon: Icons.visibility_off_outlined,
                      variant: SgBtnVariant.ghost,
                      dense: true,
                      onPressed: () => setState(() => _masques.add(item.key)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
