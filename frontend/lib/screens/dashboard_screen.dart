import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../services/conflict_report.dart';
import '../services/planning_store.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/defense_tile.dart';
import '../widgets/ui_kit.dart';
import 'conflicts_screen.dart';
import 'defense_detail_screen.dart';
import 'defense_form_screen.dart';
import 'documents_screen.dart';
import 'planning_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.user?['full_name']?.toString() ??
        auth.user?['username']?.toString() ??
        'Utilisateur';
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, defenses, _) {
        final conflits = ConflictScanner.scan(defenses);
        final tri = [...defenses]
          ..sort((a, b) => '${a.date}${a.startTime}'
              .compareTo('${b.date}${b.startTime}'));
        final today = DateTime.now();
        final prochaines = tri
            .where((d) {
              final p = parseDefenseDate(d.date);
              return p != null && !p.isBefore(DateTime(today.year, today.month, today.day));
            })
            .take(4)
            .toList();

        return SgPage(
          section: AppSection.dashboard,
          title: 'Bonjour, $name',
          subtitle:
              'Voici l’état de vos soutenances pour l’année ${anneeScolaire(today)}.',
          actions: [
            if (Session.peutGerer(context))
              SgButton('Nouvelle soutenance',
                  icon: Icons.add_rounded,
                  onPressed: () => _push(context, const DefenseFormScreen())),
            SgButton('Planning',
                icon: Icons.calendar_month_outlined,
                variant: SgBtnVariant.outline,
                onPressed: () => _push(context, const PlanningScreen())),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _banner(context),
              const SizedBox(height: 22),
              _stats(defenses.length, PlanningStore.rooms.length,
                  PlanningStore.juryMembers.length, conflits.length),
              const SizedBox(height: 26),
              SgSectionTitle(
                'Prochaines soutenances',
                subtitle: 'Les échéances les plus proches du calendrier.',
                action: SgButton('Tout voir',
                    variant: SgBtnVariant.ghost,
                    dense: true,
                    onPressed: () => _push(context, const PlanningScreen())),
              ),
              const SizedBox(height: 12),
              if (prochaines.isEmpty)
                SgEmpty(
                  icon: Icons.event_available_outlined,
                  title: 'Aucune soutenance à venir',
                  message:
                      'Créez une première soutenance pour alimenter votre planning.',
                  action: Session.peutGerer(context)
                      ? SgButton('Créer une soutenance',
                          icon: Icons.add_rounded,
                          onPressed: () =>
                              _push(context, const DefenseFormScreen()))
                      : null,
                )
              else
                Column(
                  children: [
                    for (final d in prochaines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DefenseTile(
                          defense: d,
                          onTap: () => _push(
                              context, DefenseDetailScreen(defense: d)),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 26),
              const SgSectionTitle('Aperçu du planning',
                  subtitle: 'Charge des 7 prochains jours.'),
              const SizedBox(height: 12),
              _semaine(defenses),
              const SizedBox(height: 26),
              const SgSectionTitle('Actions rapides',
                  subtitle: 'Accès direct aux modules de gestion.'),
              const SizedBox(height: 12),
              _actions(context, conflits.length),
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'SGSUS — Gestion des stages et des soutenances universitaires',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('© ${DateTime.now().year} — Tous droits réservés',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.greyLight)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _banner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ESPACE DE PLANIFICATION',
                      style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6)),
                  const SizedBox(height: 12),
                  const Text(
                    'Organisez vos soutenances avec précision.',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Horaires, salles, jurys et documents réunis dans un seul espace de travail.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12.5,
                        height: 1.55),
                  ),
                ],
              ),
            ),
            if (c.maxWidth > 520) ...[
              const SizedBox(width: 16),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Icon(Icons.school_rounded,
                    color: AppColors.gold, size: 28),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stats(int soutenances, int salles, int jurys, int conflits) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = c.maxWidth >= 1020 ? 4 : (c.maxWidth >= 520 ? 2 : 2);
        final w = (c.maxWidth - (n - 1) * 14) / n;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
                width: w,
                child: SgStatCard(
                    label: 'Soutenances',
                    value: '$soutenances',
                    icon: Icons.event_available_rounded,
                    tone: SgTone.info,
                    foot: 'année ${anneeScolaire(DateTime.now())}')),
            SizedBox(
                width: w,
                child: SgStatCard(
                    label: 'Membres du jury',
                    value: '$jurys',
                    icon: Icons.groups_2_rounded,
                    tone: SgTone.gold)),
            SizedBox(
                width: w,
                child: SgStatCard(
                    label: 'Salles',
                    value: '$salles',
                    icon: Icons.meeting_room_rounded,
                    tone: SgTone.success)),
            SizedBox(
                width: w,
                child: SgStatCard(
                    label: 'Conflits détectés',
                    value: '$conflits',
                    icon: Icons.report_gmailerrorred_rounded,
                    tone: conflits > 0 ? SgTone.danger : SgTone.success,
                    foot: conflits > 0 ? 'action requise' : 'planning sain')),
          ],
        );
      },
    );
  }

  Widget _semaine(List<Defense> defenses) {
    final today = DateTime.now();
    final jours = List.generate(7, (i) => today.add(Duration(days: i)));
    return SgCard(
      child: LayoutBuilder(
        builder: (context, c) {
          final compact = c.maxWidth < 620;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final j in jours)
                Expanded(
                  child: Column(
                    children: [
                      Builder(builder: (context) {
                        final count = defenses.where((d) {
                          final p = parseDefenseDate(d.date);
                          return p != null && sameDay(p, j);
                        }).length;
                        const maxCount = 3;
                        final h = 14.0 + (count / maxCount).clamp(0.0, 1.0) * 46;
                        return Container(
                          height: h,
                          margin: EdgeInsets.symmetric(
                              horizontal: compact ? 3 : 6),
                          decoration: BoxDecoration(
                            color: count == 0
                                ? AppColors.neutralBg
                                : (sameDay(j, today)
                                    ? AppColors.gold
                                    : AppColors.ink),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              count == 0 ? '' : '$count',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: sameDay(j, today)
                                    ? AppColors.ink
                                    : Colors.white,
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Text(
                        compact
                            ? joursCourts[j.weekday - 1].substring(0, 1)
                            : joursCourts[j.weekday - 1],
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: sameDay(j, today)
                              ? AppColors.ink
                              : AppColors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('${j.day}',
                          style: const TextStyle(
                              fontSize: 9.5, color: AppColors.greyLight)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _actions(BuildContext context, int conflits) {
    final items = <_Action>[
      if (Session.peutGerer(context)) ...[
        _Action('Nouvelle soutenance', 'Programmer une soutenance.',
            Icons.add_circle_outline_rounded, const DefenseFormScreen()),
        _Action('Planning', 'Vues jour, semaine et mois.',
            Icons.calendar_month_rounded, const PlanningScreen()),
        _Action('Conflits', '$conflits à traiter.', Icons.report_gmailerrorred_rounded,
            const ConflictsScreen()),
      ] else if (context.read<AuthProvider>().role == 'jury') ...[
        _Action('Mon planning de jury', 'Soutenances affectées à votre jury.',
            Icons.calendar_month_rounded, const PlanningScreen()),
      ] else if (context.read<AuthProvider>().role == 'student') ...[
        _Action('Mes documents', 'Dossiers et versions.',
            Icons.folder_open_rounded, const DocumentsScreen()),
      ] else if (context.read<AuthProvider>().role == 'supervisor') ...[
        _Action('Dossiers affectés', 'Consulter les rapports et donner un avis.',
            Icons.folder_open_rounded, const DocumentsScreen()),
      ],
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final n = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
        final w = (c.maxWidth - (n - 1) * 12) / n;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final a in items)
              SizedBox(width: w, child: _actionCard(context, a)),
          ],
        );
      },
    );
  }

  Widget _actionCard(BuildContext context, _Action a) {
    return SgCard(
      padding: const EdgeInsets.all(15),
      onTap: () => _push(context, a.page),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.goldSoft,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(a.icon, size: 19, color: AppColors.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(a.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.grey)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.greyLight),
        ],
      ),
    );
  }
}

class _Action {
  _Action(this.title, this.sub, this.icon, this.page);
  final String title;
  final String sub;
  final IconData icon;
  final Widget page;
}