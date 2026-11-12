import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/planning_store.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

class _Room {
  _Room({
    required this.nom,
    required this.capacite,
    required this.localisation,
    required this.statut,
  });
  String nom;
  int capacite;
  String localisation;
  String statut;
}

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  static const _localisations = [
    'Bâtiment A — 1er étage',
    'Bâtiment B — RDC',
    'Bâtiment A — 2e étage',
    'Amphi central',
  ];

  late List<_Room> _rooms;
  String _q = '';
  String _filtre = 'Toutes';

  @override
  void initState() {
    super.initState();
    _rooms = [
      for (var i = 0; i < PlanningStore.rooms.length; i++)
        _Room(
          nom: PlanningStore.rooms[i],
          capacite: 30 + (i % 4) * 20,
          localisation: _localisations[i % _localisations.length],
          statut: i % 5 == 4 ? 'Indisponible' : 'Disponible',
        ),
    ];
  }

  List<_Room> _visibles() => _rooms.where((r) {
        if (_filtre != 'Toutes' && r.statut != _filtre) return false;
        if (_q.isNotEmpty &&
            !r.nom.toLowerCase().contains(_q.toLowerCase()) &&
            !r.localisation.toLowerCase().contains(_q.toLowerCase())) {
          return false;
        }
        return true;
      }).toList();

  Future<void> _editer({_Room? room}) async {
    final result = await showDialog<_Room>(
      context: context,
      builder: (_) => _RoomDialog(initial: room),
    );
    if (result == null) return;
    setState(() {
      if (room == null) {
        _rooms.add(result);
      } else {
        room
          ..nom = result.nom
          ..capacite = result.capacite
          ..localisation = result.localisation
          ..statut = result.statut;
      }
    });
    if (!mounted) return;
    SgToast.show(context, room == null ? 'Salle ajoutée.' : 'Salle modifiée.');
  }

  Future<void> _supprimer(_Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la salle'),
        content: Text('Confirmez-vous la suppression de « ${room.nom} » ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _rooms.remove(room));
    if (!mounted) return;
    SgToast.show(context, 'Salle supprimée.', tone: SgTone.danger);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, defenses, _) {
        final occupees = <String>{};
        for (final d in defenses) {
          final p = parseDefenseDate(d.date);
          if (p != null && sameDay(p, DateTime.now())) occupees.add(d.roomName);
        }

        final rooms = _visibles();
        return SgPage(
          section: AppSection.rooms,
          title: 'Gestion des salles',
          subtitle: 'Capacités, localisation et disponibilité des espaces.',
          actions: [
            if (Session.peutGerer)
              SgButton('Ajouter une salle',
                  icon: Icons.add_rounded, onPressed: () => _editer()),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final n = c.maxWidth >= 1040 ? 4 : (c.maxWidth >= 560 ? 2 : 2);
                  final w = (c.maxWidth - (n - 1) * 12) / n;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                          width: w,
                          child: SgStatCard(
                              label: 'Salles',
                              value: '${_rooms.length}',
                              icon: Icons.meeting_room_rounded,
                              tone: SgTone.gold)),
                      SizedBox(
                          width: w,
                          child: SgStatCard(
                              label: 'Disponibles',
                              value:
                                  '${_rooms.where((r) => r.statut == 'Disponible').length}',
                              icon: Icons.check_circle_outline_rounded,
                              tone: SgTone.success)),
                      SizedBox(
                          width: w,
                          child: SgStatCard(
                              label: 'Occupées aujourd’hui',
                              value: '${occupees.length}',
                              icon: Icons.lock_clock_outlined,
                              tone: SgTone.warning)),
                      SizedBox(
                          width: w,
                          child: SgStatCard(
                              label: 'Indisponibles',
                              value:
                                  '${_rooms.where((r) => r.statut == 'Indisponible').length}',
                              icon: Icons.block_rounded,
                              tone: SgTone.danger)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              SgCard(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SgSearch(
                        width: 230,
                        hint: 'Rechercher une salle…',
                        onChanged: (v) => setState(() => _q = v)),
                    for (final s in ['Toutes', 'Disponible', 'Occupée', 'Indisponible'])
                      SgChip(
                        label: s,
                        selected: _filtre == s,
                        onTap: () => setState(() => _filtre = s),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (rooms.isEmpty)
                const SgEmpty(
                  icon: Icons.meeting_room_outlined,
                  title: 'Aucune salle',
                  message: 'Ajoutez une salle ou modifiez les filtres.',
                )
              else
                LayoutBuilder(
                  builder: (context, c) {
                    String statut(String s) => s == 'Occupée'
                          ? 'Occupée'
                          : (s == 'Indisponible' ? 'Indisponible' : 'Disponible');
                        if (c.maxWidth >= 820) {
                      return SgCard(
                        padding: EdgeInsets.zero,
                        child: SgTable(
                          columns: const [
                            SgCol('Salle', flex: 3),
                            SgCol('Capacité', flex: 2),
                            SgCol('Localisation', flex: 3),
                            SgCol('Statut', flex: 2),
                            SgCol('Actions', flex: 2, align: Alignment.centerRight),
                          ],
                          rows: [
                            for (final r in rooms)
                              [
                                Row(children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                        color: AppColors.goldSoft,
                                        borderRadius:
                                            BorderRadius.circular(7)),
                                    child: const Icon(Icons.meeting_room_rounded,
                                        size: 15, color: AppColors.gold),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(r.nom,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ]),
                                Text('${r.capacite} places',
                                    style: const TextStyle(
                                        fontSize: 12.5, color: AppColors.grey)),
                                Text(r.localisation,
                                    style: const TextStyle(
                                        fontSize: 12.5, color: AppColors.grey)),
                                SgBadge(
                                  occupees.contains(r.nom) &&
                                          r.statut == 'Disponible'
                                      ? 'Occupée'
                                      : r.statut,
                                  tone: sgToneForStatus(
                                    occupees.contains(r.nom) &&
                                            r.statut == 'Disponible'
                                        ? 'Occupée'
                                        : r.statut,
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    SgIconBtn(
                                        icon: Icons.edit_outlined,
                                        tooltip: 'Modifier',
                                        tone: SgTone.info,
                                        onPressed: Session.peutGerer
                                            ? () => _editer(room: r)
                                            : null),
                                    const SizedBox(width: 6),
                                    SgIconBtn(
                                        icon: Icons.delete_outline_rounded,
                                        tooltip: 'Supprimer',
                                        tone: SgTone.danger,
                                        onPressed: Session.peutGerer
                                            ? () => _supprimer(r)
                                            : null),
                                  ],
                                ),
                              ],
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final r in rooms)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SgCard(
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                        color: AppColors.goldSoft,
                                        borderRadius:
                                            BorderRadius.circular(9)),
                                    child: const Icon(
                                        Icons.meeting_room_rounded,
                                        size: 18,
                                        color: AppColors.gold),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(r.nom,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 3),
                                        Text(
                                            '${r.capacite} places · ${r.localisation}',
                                            style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors.grey)),
                                        const SizedBox(height: 7),
                                        SgBadge(
                                          statut(occupees.contains(r.nom) &&
                                                  r.statut == 'Disponible'
                                              ? 'Occupée'
                                              : r.statut),
                                          tone: sgToneForStatus(
                                              occupees.contains(r.nom) &&
                                                      r.statut ==
                                                          'Disponible'
                                                  ? 'Occupée'
                                                  : r.statut),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SgIconBtn(
                                      icon: Icons.edit_outlined,
                                      tooltip: 'Modifier',
                                      tone: SgTone.info,
                                      onPressed: Session.peutGerer
                                          ? () => _editer(room: r)
                                          : null),
                                  const SizedBox(width: 6),
                                  SgIconBtn(
                                      icon: Icons.delete_outline_rounded,
                                      tooltip: 'Supprimer',
                                      tone: SgTone.danger,
                                      onPressed: Session.peutGerer
                                          ? () => _supprimer(r)
                                          : null),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RoomDialog extends StatefulWidget {
  const _RoomDialog({this.initial});
  final _Room? initial;

  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<_RoomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom =
      TextEditingController(text: widget.initial?.nom ?? '');
  late final TextEditingController _cap =
      TextEditingController(text: '${widget.initial?.capacite ?? 40}');
  late final TextEditingController _loc =
      TextEditingController(text: widget.initial?.localisation ?? '');
  late String _statut = widget.initial?.statut ?? 'Disponible';

  @override
  void dispose() {
    _nom.dispose();
    _cap.dispose();
    _loc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Ajouter une salle' : 'Modifier la salle'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nom,
                  decoration: const InputDecoration(labelText: 'Nom de la salle'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cap,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Capacité'),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null ? 'Nombre requis' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _loc,
                  decoration:
                      const InputDecoration(labelText: 'Localisation'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
                ),
                const SizedBox(height: 14),
                SgSelect<String>(
                  value: _statut,
                  icon: Icons.tune_rounded,
                  items: const [
                    DropdownMenuItem(value: 'Disponible', child: Text('Disponible')),
                    DropdownMenuItem(value: 'Occupée', child: Text('Occupée')),
                    DropdownMenuItem(
                        value: 'Indisponible', child: Text('Indisponible')),
                  ],
                  onChanged: (v) => setState(() => _statut = v ?? 'Disponible'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        SgButton('Enregistrer', onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _Room(
              nom: _nom.text.trim(),
              capacite: int.parse(_cap.text.trim()),
              localisation: _loc.text.trim(),
              statut: _statut,
            ),
          );
        }),
      ],
    );
  }
}