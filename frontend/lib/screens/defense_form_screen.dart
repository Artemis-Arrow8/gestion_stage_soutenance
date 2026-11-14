import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/planning_store.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

const _etudiantsDemo = [
  'Awa Traoré', 'Ibrahim Sissoko', 'Fatoumata Koné',
  'Moussa Keïta', 'Aïcha Diop', 'Souleymane Cissé',
];

class DefenseFormScreen extends StatefulWidget {
  const DefenseFormScreen({super.key, this.initial});

  final Defense? initial;

  @override
  State<DefenseFormScreen> createState() => _DefenseFormScreenState();
}

class _DefenseFormScreenState extends State<DefenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();

  String? _etudiant;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  String? _salle;
  String? _president;
  final Set<String> _membres = {};

  bool get _duplication => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i == null) return;
    _etudiant = i.studentName;
    _subjectController.text = i.subject;
    _date = parseDefenseDate(i.date);
    _start = _toTime(i.startTime);
    _end = _toTime(i.endTime);
    _salle = i.roomName;
    final membres = i.juryName
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (membres.isNotEmpty) _president = membres.first;
    _membres.addAll(
        membres.skip(1).where((m) => PlanningStore.juryMembers.contains(m)));
  }

  TimeOfDay? _toTime(String h) {
    final p = h.split(':');
    if (p.length != 2) return null;
    final hh = int.tryParse(p[0]);
    final mm = int.tryParse(p[1]);
    if (hh == null || mm == null) return null;
    return TimeOfDay(hour: hh, minute: mm);
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  bool get _complet =>
      _etudiant != null &&
      _date != null &&
      _start != null &&
      _end != null &&
      _salle != null &&
      _president != null;

  Defense _candidate() {
    final jury = [_president!, ..._membres].join(', ');
    return Defense(
      id: PlanningStore.nextId,
      studentName: _etudiant!,
      subject: _subjectController.text.trim(),
      date: isoDate(_date!),
      startTime: hhmm(_start!),
      endTime: hhmm(_end!),
      roomName: _salle!,
      juryName: jury,
      status: 'En attente',
    );
  }

  List<String> get _conflitsActuels =>
      _complet ? PlanningStore.findConflicts(_candidate()) : const [];

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _pickTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ??
          (start
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 10, minute: 0)),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_complet) {
      SgToast.show(
          context,
          'Complétez l’étudiant, le créneau, la salle et le président.',
          tone: SgTone.danger);
      return;
    }
    final startMin = _start!.hour * 60 + _start!.minute;
    final endMin = _end!.hour * 60 + _end!.minute;
    if (endMin <= startMin) {
      SgToast.show(context,
          'L’heure de fin doit être après l’heure de début.',
          tone: SgTone.danger);
      return;
    }

    final candidate = _candidate();
    final conflits = PlanningStore.findConflicts(candidate);
    if (conflits.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conflit de planning'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Cette soutenance entre en conflit avec le planning existant :',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.grey, height: 1.5)),
              const SizedBox(height: 12),
              for (final c in conflits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(c,
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Modifier')),
            SgButton('Enregistrer quand même',
                variant: SgBtnVariant.danger, onPressed: () {
              Navigator.pop(ctx);
              _enregistrer(candidate);
            }),
          ],
        ),
      );
      return;
    }
    _enregistrer(candidate);
  }

  void _enregistrer(Defense candidate) {
    PlanningStore.nextId++;
    PlanningStore.addDefense(candidate);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final conflits = _conflitsActuels;

    return SgPage(
      section: AppSection.planning,
      title: _duplication ? 'Dupliquer la soutenance' : 'Nouvelle soutenance',
      subtitle: _duplication
          ? 'Ajustez les informations puis enregistrez une nouvelle soutenance.'
          : 'Programmez une soutenance ; les conflits sont vérifiés avant validation.',
      actions: [
        SgButton('Annuler',
            variant: SgBtnVariant.outline,
            onPressed: () => Navigator.pop(context)),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _groupe('IDENTIFICATION', Icons.person_outline_rounded, [
              SgSelect<String>(
                value: _etudiant ?? '',
                icon: Icons.school_outlined,
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('Sélectionner un étudiant')),
                  for (final e in _etudiantsDemo)
                    DropdownMenuItem(value: e, child: Text(e)),
                ],
                onChanged: (v) => setState(
                    () => _etudiant = (v != null && v.isNotEmpty) ? v : null),
              ),
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Sujet de soutenance',
                  prefixIcon: Icon(Icons.menu_book_outlined, size: 20),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
            ]),
            const SizedBox(height: 14),
            _groupe('CRÉNEAU', Icons.schedule_outlined, [
              _pickerTile(
                icon: Icons.calendar_month_outlined,
                label: _date == null ? 'Choisir la date' : shortDate(_date!),
                onTap: _pickDate,
              ),
              Row(children: [
                Expanded(
                    child: _pickerTile(
                        icon: Icons.login_outlined,
                        label: _start == null ? 'Début' : hhmm(_start!),
                        onTap: () => _pickTime(start: true))),
                const SizedBox(width: 10),
                Expanded(
                    child: _pickerTile(
                        icon: Icons.logout_outlined,
                        label: _end == null ? 'Fin' : hhmm(_end!),
                        onTap: () => _pickTime(start: false))),
              ]),
            ]),
            const SizedBox(height: 14),
            _groupe('SALLE & JURY', Icons.meeting_room_outlined, [
              SgSelect<String>(
                value: _salle ?? '',
                icon: Icons.meeting_room_outlined,
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('Sélectionner une salle')),
                  for (final r in PlanningStore.rooms)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) =>
                    setState(() => _salle = (v != null && v.isNotEmpty) ? v : null),
              ),
              SgSelect<String>(
                value: _president ?? '',
                icon: Icons.workspace_premium_outlined,
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('Président du jury')),
                  for (final m in PlanningStore.juryMembers)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(
                    () => _president = (v != null && v.isNotEmpty) ? v : null),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MEMBRES DU JURY',
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: .7,
                          fontWeight: FontWeight.w700,
                          color: AppColors.greyLight)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in PlanningStore.juryMembers)
                        SgChip(
                          label: m,
                          selected: _membres.contains(m),
                          onTap: () => setState(() {
                            if (_membres.contains(m)) {
                              _membres.remove(m);
                            } else {
                              _membres.add(m);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 14),
            _apercuConflits(conflits),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 430;
                final enregistrer = SgButton(
                  _duplication
                      ? 'Enregistrer la copie'
                      : 'Enregistrer la soutenance',
                  icon: Icons.check_rounded,
                  expand: !wide,
                  onPressed: _save,
                );
                final annuler = SgButton('Annuler',
                    variant: SgBtnVariant.outline,
                    expand: !wide,
                    onPressed: () => Navigator.pop(context));
                if (wide) {
                  return Row(children: [
                    Expanded(child: enregistrer),
                    const SizedBox(width: 10),
                    SizedBox(width: 140, child: annuler),
                  ]);
                }
                return Column(children: [
                  enregistrer,
                  const SizedBox(height: 8),
                  annuler,
                ]);
              },
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'Les conflits de salle, de jury et d’horaires sont vérifiés automatiquement.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupe(String titre, IconData icon, List<Widget> enfants) {
    final items = <Widget>[];
    for (var i = 0; i < enfants.length; i++) {
      items.add(enfants[i]);
      if (i < enfants.length - 1) items.add(const SizedBox(height: 12));
    }
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: AppColors.gold),
            const SizedBox(width: 8),
            Text(titre,
                style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey)),
          ]),
          const SizedBox(height: 14),
          ...items,
        ],
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              const Icon(Icons.edit_calendar_outlined,
                  size: 15, color: AppColors.greyLight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _apercuConflits(List<String> conflits) {
    if (!_complet) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded,
              size: 17, color: AppColors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                'Renseignez tous les champs : la vérification des conflits s’affichera ici.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.grey, height: 1.45)),
          ),
        ]),
      );
    }

    final (fg, bg) =
        conflits.isEmpty ? sgTones(SgTone.success) : sgTones(SgTone.danger);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                conflits.isEmpty
                    ? Icons.verified_outlined
                    : Icons.warning_amber_rounded,
                size: 17,
                color: fg),
            const SizedBox(width: 9),
            Text(
              conflits.isEmpty
                  ? 'Aucun conflit détecté'
                  : '${conflits.length} conflit(s) détecté(s)',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
            ),
          ]),
          const SizedBox(height: 8),
          if (conflits.isEmpty)
            Text('La salle et le jury sont libres sur ce créneau.',
                style: TextStyle(fontSize: 11.5, color: fg, height: 1.4))
          else ...[
            for (final c in conflits)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child:
                            Icon(Icons.circle, size: 5, color: fg)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(c,
                            style: TextStyle(
                                fontSize: 12, color: fg, height: 1.4))),
                  ],
                ),
              ),
            Text(
                'Vous pouvez enregistrer malgré tout ; le conflit restera visible dans l’écran Conflits.',
                style: TextStyle(
                    fontSize: 11, color: fg, height: 1.4)),
          ],
        ],
      ),
    );
  }
}