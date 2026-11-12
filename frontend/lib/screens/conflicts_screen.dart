import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/conflict_report.dart';
import '../services/planning_store.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';

class ConflictsScreen extends StatefulWidget {
  const ConflictsScreen({super.key});

  @override
  State<ConflictsScreen> createState() => _ConflictsScreenState();
}

class _ConflictsScreenState extends State<ConflictsScreen> {
  final Set<String> _resolus = {};

  int _toMin(String h) {
    final p = h.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool _juryOverlap(String a, String b) {
    final x = a.toLowerCase().split(',').map((e) => e.trim()).toSet();
    final y = b.toLowerCase().split(',').map((e) => e.trim()).toSet();
    return x.intersection(y).isNotEmpty;
  }

  List<Defense> _concernees(ConflitItem item, List<Defense> all) {
    final mine = all.where((d) => d.studentName == item.etudiant).toList();
    if (mine.isEmpty) return const [];
    final d0 = mine.first;
    final p0 = parseDefenseDate(d0.date);
    if (p0 == null) return [d0];
    final autres = all.where((d) {
      if (d.id == d0.id) return false;
      final p = parseDefenseDate(d.date);
      if (p == null || !sameDay(p, p0)) return false;
      final overlap = _toMin(d.startTime) < _toMin(d0.endTime) &&
          _toMin(d0.startTime) < _toMin(d.endTime);
      if (!overlap) return false;
      return d.roomName == d0.roomName || _juryOverlap(d.juryName, d0.juryName);
    });
    return [d0, ...autres];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, all, _) {
        final items = ConflictScanner.scan(all)
            .where((c) => !_resolus.contains(c.key))
            .toList();
        final parType = {
          for (final k in ConflictKind.values)
            k: items.where((i) => i.kind == k).length,
        };

        return SgPage(
          section: AppSection.conflicts,
          title: 'Gestion des conflits',
          subtitle:
              'Détection automatique des chevauchements de salles, de jurys et d’horaires.',
          actions: [
            SgButton('Actualiser',
                icon: Icons.refresh_rounded,
                variant: SgBtnVariant.outline,
                onPressed: () => setState(() {})),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final n = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 520 ? 3 : 1);
                  final w = (c.maxWidth - (n - 1) * 12) / n;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                          width: w,
                          child: SgStatCard(
                              label: 'Total à traiter',
                              value: '${items.length}',
                              icon: Icons.report_gmailerrorred_rounded,
                              tone: items.isEmpty ? SgTone.success : SgTone.danger)),
                      SizedBox(
                          width: w,
                          child: SgStatCard(
                              label: 'Conflits de salles',
                              value: '${parType[ConflictKind.salle] ?? 0}',
                              icon: Icons.meeting_room_outlined,
                              tone: SgTone.warning)),
                      SizedBox(
                          width: w,
                          child: SgStatCard(
                              label: 'Conflits de jurys / horaires',
                              value:
                                  '${(parType[ConflictKind.jury] ?? 0) + (parType[ConflictKind.horaire] ?? 0)}',
                              icon: Icons.groups_2_outlined,
                              tone: SgTone.info)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              if (items.isEmpty)
                const SgEmpty(
                  icon: Icons.verified_outlined,
                  title: 'Aucun conflit détecté',
                  message:
                      'Les salles et les membres des jurys ne sont pas réservés deux fois au même moment.',
                )
              else ...[
                Text('${items.length} conflit(s) à traiter',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _carte(item, all),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _carte(ConflitItem item, List<Defense> all) {
    final concernees = _concernees(item, all);
    final tone = item.kind == ConflictKind.salle
        ? SgTone.warning
        : SgTone.danger;
    final (fg, bg) = sgTones(tone);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Icon(
                    item.kind == ConflictKind.salle
                        ? Icons.meeting_room_outlined
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: fg),
                const SizedBox(width: 8),
                Text(item.typeLabel,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg)),
                const Spacer(),
                SgBadge(item.kind == ConflictKind.horaire ? 'Priorité haute' : 'À traiter',
                    tone: tone, dot: false),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.etudiant,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(item.message,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.grey, height: 1.5)),
                if (concernees.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('SOUTENANCES CONCERNÉES',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: .8,
                          fontWeight: FontWeight.w700,
                          color: AppColors.greyLight)),
                  const SizedBox(height: 8),
                  for (final d in concernees)
                    InkWell(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DefenseDetailScreen(defense: d))),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.circle,
                                size: 5, color: AppColors.greyLight),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${d.studentName} · ${d.date} · ${d.startTime}–${d.endTime} · ${d.roomName}',
                                style: const TextStyle(
                                    fontSize: 11.5, color: AppColors.ink),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                size: 16, color: AppColors.greyLight),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          switch (item.kind) {
                            ConflictKind.salle =>
                              'Proposition : affecter une salle libre sur le même créneau, ou décaler la soutenance de 60 minutes.',
                            ConflictKind.jury =>
                              'Proposition : retirer le membre en doublon du jury, ou replanifier la soutenance sur un créneau où il est disponible.',
                            ConflictKind.horaire =>
                              'Proposition : espacer les deux soutenances d’au moins 15 minutes de pause.',
                          },
                          style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.grey,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    SgButton('Résoudre',
                        icon: Icons.build_circle_outlined,
                        dense: true,
                        onPressed: () => _resoudre(item, concernees)),
                    const SizedBox(width: 8),
                    SgButton('Ignorer',
                        variant: SgBtnVariant.ghost,
                        dense: true,
                        onPressed: () {
                          setState(() => _resolus.add(item.key));
                          SgToast.show(context, 'Conflit ignoré.',
                              tone: SgTone.warning);
                        }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  void _resoudre(ConflitItem item, List<Defense> concernees) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Résolution du conflit',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${item.typeLabel} — ${item.etudiant}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.grey)),
              const SizedBox(height: 14),
              const Text('PROPOSITIONS DE RÉSOLUTION',
                  style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700,
                      color: AppColors.greyLight)),
              const SizedBox(height: 10),
              for (final p in _propositions(item))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SgCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () {
                      Navigator.pop(ctx);
                      _appliquer(item, p.titre);
                    },
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.goldSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child:
                              Icon(p.icon, size: 17, color: AppColors.gold),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.titre,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(p.detail,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.grey,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: AppColors.greyLight),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              SgButton('Fermer',
                  variant: SgBtnVariant.outline,
                  expand: true,
                  onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
  }

  List<_Proposition> _propositions(ConflitItem item) {
    switch (item.kind) {
      case ConflictKind.salle:
        return const [
          _Proposition('Affecter une salle libre',
              'Choisir une autre salle disponible sur le même créneau.',
              Icons.meeting_room_outlined),
          _Proposition('Décaler d’une heure',
              'Reporte la soutenance au créneau suivant dans la même salle.',
              Icons.schedule_rounded),
        ];
      case ConflictKind.jury:
        return const [
          _Proposition('Remplacer le membre',
              'Retirer le membre en doublon et le remplacer par un membre disponible.',
              Icons.group_add_outlined),
          _Proposition('Replanifier la soutenance',
              'Choisir un créneau où tous les membres du jury sont disponibles.',
              Icons.event_repeat_rounded),
        ];
      case ConflictKind.horaire:
        return const [
          _Proposition('Espacer les créneaux',
              'Ajouter au moins 15 minutes de pause entre les deux soutenances.',
              Icons.more_time_rounded),
          _Proposition('Déplacer vers une autre salle',
              'Permet d’organiser les deux soutenances en parallèle.',
              Icons.swap_horiz_rounded),
        ];
    }
  }

  void _appliquer(ConflitItem item, String libelle) {
    setState(() => _resolus.add(item.key));
    SgToast.show(context, 'Conflit résolu : $libelle');
  }
}

class _Proposition {
  const _Proposition(this.titre, this.detail, this.icon);
  final String titre;
  final String detail;
  final IconData icon;
}

  