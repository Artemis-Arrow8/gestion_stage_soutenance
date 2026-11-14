import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../services/planning_service.dart';
import '../services/planning_store.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';
import 'defense_form_screen.dart';

enum PlanningView { jour, semaine, mois }

const _joursLongs = [
  'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
];

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  late PlanningService _service;
  bool _initialise = false;
  bool _loading = true;
  bool _peutGerer = false;
  String? _error;
  PlanningView _view = PlanningView.mois;
  DateTime _cursor = DateTime.now();
  DateTime _selected = DateTime.now();
  String? _salle;
  String? _jury;
  String _annee = 'Toutes';
  String _q = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialise) return;
    _initialise = true;
    final auth = context.read<AuthProvider>();
    _service = PlanningService(
      accessToken: auth.accessToken,
      accessTokenProvider: () => auth.accessToken,
      refreshAccessToken: auth.refreshAccessToken,
    );
    _peutGerer = const {'admin', 'responsible'}.contains(auth.role);
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await PlanningStore.refresh(_service, loadCatalog: _peutGerer);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<String> _annees(List<Defense> all) {
    final set = <String>{anneeScolaire(DateTime.now())};
    for (final d in all) {
      final p = parseDefenseDate(d.date);
      if (p != null) set.add(anneeScolaire(p));
    }
    final list = set.toList()..sort();
    return ['Toutes', ...list.reversed];
  }

  List<Defense> _apply(List<Defense> all) {
    return all.where((d) {
      if (_salle != null && d.roomName != _salle) return false;
      if (_jury != null &&
          !d.juryName.toLowerCase().contains(_jury!.toLowerCase())) {
        return false;
      }
      if (_q.isNotEmpty &&
          !d.studentName.toLowerCase().contains(_q.toLowerCase())) {
        return false;
      }
      final p = parseDefenseDate(d.date);
      if (_annee != 'Toutes' && (p == null || anneeScolaire(p) != _annee)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          '${a.date}${a.startTime}'.compareTo('${b.date}${b.startTime}'));
  }

  void _shift(int delta) {
    setState(() {
      if (_view == PlanningView.jour) {
        _cursor = _cursor.add(Duration(days: delta));
      } else if (_view == PlanningView.semaine) {
        _cursor = _cursor.add(Duration(days: 7 * delta));
      } else {
        _cursor = DateTime(_cursor.year, _cursor.month + delta, 1);
      }
      _selected = _cursor;
    });
  }

  String get _periodLabel {
    if (_view == PlanningView.jour) {
      return '${_joursLongs[_cursor.weekday - 1]} ${_cursor.day} '
          '${moisLongs[_cursor.month - 1]} ${_cursor.year}';
    }
    if (_view == PlanningView.semaine) {
      final monday = _cursor.subtract(Duration(days: _cursor.weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      return '${monday.day} ${moisLongs[monday.month - 1]} – '
          '${sunday.day} ${moisLongs[sunday.month - 1]} ${sunday.year}';
    }
    return '${moisLongs[_cursor.month - 1]} ${_cursor.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, all, _) {
        final data = _apply(all);
        return SgPage(
          section: AppSection.planning,
          title: 'Planning des soutenances',
          subtitle: 'Planning synchronisé avec le serveur.',
          actions: [
            SgButton('Actualiser',
                icon: Icons.refresh_rounded,
                variant: SgBtnVariant.outline,
                onPressed: _charger),
            if (_peutGerer)
              SgButton('Nouvelle soutenance',
                  icon: Icons.add_rounded,
                  onPressed: () async {
                    final created = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DefenseFormScreen(),
                      ),
                    );
                    if (created == true) await _charger();
                  }),
          ],
          child: _loading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _error != null
                  ? SgCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Impossible de charger le planning.'),
                          const SizedBox(height: 8),
                          Text(_error!),
                          const SizedBox(height: 12),
                          SgButton('Réessayer',
                              icon: Icons.refresh_rounded,
                              onPressed: _charger),
                        ],
                      ),
                    )
                  : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _toolbar(all),
              const SizedBox(height: 16),
              if (_view == PlanningView.mois) ...[
                _monthGrid(data),
                const SizedBox(height: 20),
                SgSectionTitle(
                  'Soutenances du ${shortDate(_selected)}',
                  subtitle: '${_pour(_selected, data).length} soutenance(s) programmée(s).',
                ),
                const SizedBox(height: 12),
                _dayList(_pour(_selected, data)),
              ] else if (_view == PlanningView.semaine)
                _weekList(data)
              else
                _dayList(_pour(_cursor, data)),
            ],
          ),
        );
      },
    );
  }

  List<Defense> _pour(DateTime day, List<Defense> data) => data.where((d) {
        final p = parseDefenseDate(d.date);
        return p != null && sameDay(p, day);
      }).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  Widget _toolbar(List<Defense> all) {
    return SgCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 640;
              final nav = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SgIconBtn(
                      icon: Icons.chevron_left_rounded,
                      tooltip: 'Précédent',
                      onPressed: () => _shift(-1)),
                  const SizedBox(width: 6),
                  SgButton('Aujourd’hui',
                      variant: SgBtnVariant.outline,
                      dense: true,
                      onPressed: () => setState(() {
                            _cursor = DateTime.now();
                            _selected = DateTime.now();
                          })),
                  const SizedBox(width: 6),
                  SgIconBtn(
                      icon: Icons.chevron_right_rounded,
                      tooltip: 'Suivant',
                      onPressed: () => _shift(1)),
                ],
              );
              final views = Wrap(
                spacing: 6,
                children: [
                  for (final v in PlanningView.values)
                    SgChip(
                      label: switch (v) {
                        PlanningView.jour => 'Jour',
                        PlanningView.semaine => 'Semaine',
                        PlanningView.mois => 'Mois',
                      },
                      selected: _view == v,
                      onTap: () => setState(() => _view = v),
                    ),
                ],
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    views,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        nav,
                        const Spacer(),
                        Flexible(
                          child: Text(_periodLabel,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                        ),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  views,
                  const Spacer(),
                  Text(_periodLabel,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2)),
                  const SizedBox(width: 14),
                  nav,
                ],
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SgSearch(
                  width: 210,
                  hint: 'Étudiant…',
                  onChanged: (v) => setState(() => _q = v)),
              SgSelect<String>(
                width: 150,
                icon: Icons.school_outlined,
                value: _annee,
                items: [
                  for (final a in _annees(all))
                    DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: (v) => setState(() => _annee = v ?? 'Toutes'),
              ),
              SgSelect<String?>(
                width: 170,
                icon: Icons.meeting_room_outlined,
                value: _salle,
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Toutes les salles')),
                  for (final r in PlanningStore.rooms)
                    DropdownMenuItem<String?>(value: r, child: Text(r)),
                ],
                onChanged: (v) => setState(() => _salle = v),
              ),
              SgSelect<String?>(
                width: 190,
                icon: Icons.groups_2_outlined,
                value: _jury,
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Tous les jurys')),
                  for (final m in PlanningStore.juryMembers)
                    DropdownMenuItem<String?>(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(() => _jury = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthGrid(List<Defense> data) {
    final first = DateTime(_cursor.year, _cursor.month, 1);
    final offset = first.weekday - 1;
    final daysInMonth = DateTime(_cursor.year, _cursor.month + 1, 0).day;
    final rows = ((offset + daysInMonth) / 7).ceil();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final j in joursCourts)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(j.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 9.5,
                            letterSpacing: .8,
                            fontWeight: FontWeight.w700,
                            color: AppColors.grey)),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
          for (var r = 0; r < rows; r++)
            SizedBox(
              height: 76,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: _cell(r * 7 + c, offset, daysInMonth, data),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  Widget _cell(int index, int offset, int daysInMonth, List<Defense> data) {
    final dayNum = index - offset + 1;
    final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
    final date = inMonth ? DateTime(_cursor.year, _cursor.month, dayNum) : null;
    final count = date == null ? 0 : _pour(date, data).length;
    final selected = date != null && sameDay(date, _selected);
    final today = date != null && sameDay(date, DateTime.now());

    return InkWell(
      onTap: inMonth
          ? () => setState(() {
                _selected = DateTime(_cursor.year, _cursor.month, dayNum);
              })
          : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ink
              : (inMonth ? AppColors.white : const Color(0xFFFBFBFB)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: today && !selected ? AppColors.gold : Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inMonth ? '$dayNum' : '',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : (inMonth ? AppColors.ink : AppColors.greyLight),
              ),
            ),
            const Spacer(),
            if (count > 0)
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: selected ? AppColors.gold : AppColors.warning,
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text('$count',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color:
                              selected ? AppColors.gold : AppColors.warning)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _weekList(List<Defense> data) {
    final monday = _cursor.subtract(Duration(days: _cursor.weekday - 1));
    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (context) {
            final day = monday.add(Duration(days: i));
            final items = _pour(day, data);
            final today = sameDay(day, DateTime.now());
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SgCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_joursLongs[i],
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: today ? AppColors.ink : AppColors.grey)),
                        const SizedBox(width: 8),
                        Text('${day.day} ${moisLongs[day.month - 1]}',
                            style: const TextStyle(
                                fontSize: 11.5, color: AppColors.greyLight)),
                        const Spacer(),
                        SgBadge('${items.length}',
                            tone: items.isEmpty
                                ? SgTone.neutral
                                : SgTone.gold),
                      ],
                    ),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Aucune soutenance',
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.greyLight)),
                      )
                    else
                      for (final d in items)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _ligne(context, d),
                        ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _dayList(List<Defense> items) {
    if (items.isEmpty) {
      return const SgEmpty(
        icon: Icons.event_busy_outlined,
        title: 'Aucune soutenance ce jour',
        message:
            'Sélectionnez une autre date ou créez une nouvelle soutenance.',
      );
    }
    return Column(
      children: [
        for (final d in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ligne(context, d),
          ),
      ],
    );
  }

  Widget _ligne(BuildContext context, Defense d) {
    return SgCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => DefenseDetailScreen(defense: d))),
      child: Row(
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: AppColors.goldSoft, borderRadius: BorderRadius.circular(8)),
            child: Column(
              children: [
                Text(d.startTime,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
                Text(d.endTime,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.studentName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(d.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.grey)),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  _mini(Icons.meeting_room_outlined, d.roomName),
                  _mini(Icons.groups_2_outlined, d.juryName),
                ]),
              ],
            ),
          ),
          SgBadge(d.status, tone: sgToneForStatus(d.status)),
        ],
      ),
    );
  }

  Widget _mini(IconData i, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 12, color: AppColors.greyLight),
          const SizedBox(width: 4),
          Text(t,
              style: const TextStyle(fontSize: 11, color: AppColors.grey)),
        ],
      );
}