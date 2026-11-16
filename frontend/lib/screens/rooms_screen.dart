/// Gestion des salles de soutenance (catalogue `/api/salles/`).
///
/// Affiche les salles réelles du serveur, leur capacité, leur état
/// (active / inactive) et leur occupation du jour, calculée à partir du
/// planning partagé. Le personnel peut ajouter, modifier et supprimer des
/// salles : chaque opération est enregistrée par l'API.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../models/defense.dart';
import '../models/planning_refs.dart';
import '../providers/auth_provider.dart';
import '../providers/planning_store.dart';
import '../services/planning_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Filtres d'affichage des salles.
enum _FiltreSalle { toutes, disponibles, occupees, inactives }

/// Écran des salles.
class RoomsScreen extends StatefulWidget {
  /// Crée l'écran des salles.
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

/// État de l'écran : liste chargée, filtres et indicateurs de chargement.
class _RoomsScreenState extends State<RoomsScreen> {
  late final PlanningService _service;
  late final bool _peutGerer;

  /// Salles renvoyées par l'API.
  List<Room> _rooms = const [];

  /// Vrai pendant le chargement.
  bool _loading = true;

  /// Erreur de chargement éventuelle.
  String? _error;

  /// Texte de recherche.
  String _q = '';

  /// Filtre actif.
  _FiltreSalle _filtre = _FiltreSalle.toutes;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _service = PlanningService(auth.api);
    _peutGerer = auth.canManage;
    _charger();
    // Le planning sert à calculer l'occupation du jour.
    PlanningStore.ensureLoaded(_service, loadCatalog: _peutGerer);
  }

  /// Charge (ou recharge) le catalogue des salles.
  Future<void> _charger() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await _service.loadRoomRecords();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } on ApiException catch (e) {
      _echec(e.message);
    } catch (_) {
      _echec('Impossible de charger les salles.');
    }
  }

  /// Publie une erreur de chargement.
  void _echec(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  /// Rafraîchit aussi la liste des noms de salles du planning partagé.
  Future<void> _synchroniserPlanning() async {
    try {
      await PlanningStore.refresh(_service, loadCatalog: _peutGerer);
    } catch (_) {
      // Non bloquant : l'erreur est publiée dans PlanningStore.error.
    }
  }

  /// Ouvre le formulaire d'ajout ([room] null) ou de modification.
  Future<void> _editer({Room? room}) async {
    final saisie = await showDialog<_RoomInput>(
      context: context,
      builder: (_) => _RoomDialog(initial: room),
    );
    if (saisie == null || !mounted) return;
    try {
      if (room == null) {
        await _service.createRoom(
          name: saisie.name,
          capacity: saisie.capacity,
          isActive: saisie.isActive,
        );
      } else {
        await _service.updateRoom(
          room.id,
          name: saisie.name,
          capacity: saisie.capacity,
          isActive: saisie.isActive,
        );
      }
      if (!mounted) return;
      SgToast.show(context, room == null ? 'Salle ajoutée.' : 'Salle modifiée.');
      await _charger();
      await _synchroniserPlanning();
    } on ApiException catch (e) {
      // Ex. nom déjà utilisé, capacité invalide : message du serveur.
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  /// Demande confirmation puis supprime [room] côté serveur.
  Future<void> _supprimer(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la salle'),
        content: Text(
          'Confirmez-vous la suppression de « ${room.name} » ? '
          'Les soutenances existantes conservent le nom de la salle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          SgButton(
            'Supprimer',
            variant: SgBtnVariant.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteRoom(room.id);
      if (!mounted) return;
      SgToast.show(context, 'Salle supprimée.');
      await _charger();
      await _synchroniserPlanning();
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  /// Applique la recherche et le filtre actif.
  List<Room> _visibles(Set<String> occupees) => _rooms.where((r) {
    final filtreOk = switch (_filtre) {
      _FiltreSalle.toutes => true,
      _FiltreSalle.disponibles => r.isActive && !occupees.contains(r.name),
      _FiltreSalle.occupees => r.isActive && occupees.contains(r.name),
      _FiltreSalle.inactives => !r.isActive,
    };
    if (!filtreOk) return false;
    return _q.isEmpty || r.name.toLowerCase().contains(_q.toLowerCase());
  }).toList();

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.rooms,
      title: 'Gestion des salles',
      subtitle: 'Capacités, disponibilité et occupation du jour.',
      onRefresh: _charger,
      actions: [
        SgButton(
          'Actualiser',
          icon: Icons.refresh_rounded,
          variant: SgBtnVariant.outline,
          onPressed: _charger,
        ),
        if (_peutGerer)
          SgButton(
            'Ajouter une salle',
            icon: Icons.add_rounded,
            onPressed: () => _editer(),
          ),
      ],
      child: _loading
          ? const SgLoading(message: 'Chargement des salles…')
          : _error != null
          ? SgErrorState(
              title: 'Impossible de charger les salles',
              message: _error!,
              onRetry: _charger,
            )
          // L'occupation suit le planning partagé en temps réel.
          : ValueListenableBuilder<List<Defense>>(
              valueListenable: PlanningStore.defenses,
              builder: (context, defenses, _) {
                final now = DateTime.now();
                final occupees = <String>{
                  for (final d in defenses)
                    if (parseDefenseDate(d.date) case final p?
                        when sameDay(p, now))
                      d.roomName,
                };
                return _contenu(occupees);
              },
            ),
    );
  }

  /// Indicateurs, filtres puis liste (tableau ou cartes selon la largeur).
  Widget _contenu(Set<String> occupees) {
    final actives = _rooms.where((r) => r.isActive).toList();
    final rooms = _visibles(occupees);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatsRow(
          cards: [
            SgStatCard(
              label: 'Salles',
              value: '${_rooms.length}',
              icon: Icons.meeting_room_rounded,
            ),
            SgStatCard(
              label: 'Disponibles aujourd’hui',
              value:
                  '${actives.where((r) => !occupees.contains(r.name)).length}',
              icon: Icons.check_circle_outline_rounded,
              tone: SgTone.success,
            ),
            SgStatCard(
              label: 'Occupées aujourd’hui',
              value: '${actives.where((r) => occupees.contains(r.name)).length}',
              icon: Icons.lock_clock_outlined,
              tone: SgTone.warning,
            ),
            SgStatCard(
              label: 'Inactives',
              value: '${_rooms.length - actives.length}',
              icon: Icons.block_rounded,
              tone: SgTone.danger,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SgCard(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SgSearch(
                width: 240,
                hint: 'Rechercher une salle…',
                onChanged: (v) => setState(() => _q = v),
              ),
              for (final f in _FiltreSalle.values)
                SgChip(
                  label: switch (f) {
                    _FiltreSalle.toutes => 'Toutes',
                    _FiltreSalle.disponibles => 'Disponibles',
                    _FiltreSalle.occupees => 'Occupées',
                    _FiltreSalle.inactives => 'Inactives',
                  },
                  selected: _filtre == f,
                  onTap: () => setState(() => _filtre = f),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (rooms.isEmpty)
          SgEmpty(
            icon: Icons.meeting_room_outlined,
            title: _rooms.isEmpty ? 'Aucune salle enregistrée' : 'Aucun résultat',
            message: _rooms.isEmpty && _peutGerer
                ? 'Ajoutez une première salle pour planifier des soutenances.'
                : 'Modifiez la recherche ou les filtres.',
          )
        else
          LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 760
                ? _tableau(rooms, occupees)
                : _cartes(rooms, occupees),
          ),
      ],
    );
  }

  /// Libellé et tonalité de l'état d'une salle.
  (String, SgTone) _etat(Room r, Set<String> occupees) {
    if (!r.isActive) return ('Inactive', SgTone.danger);
    if (occupees.contains(r.name)) return ('Occupée aujourd’hui', SgTone.warning);
    return ('Disponible', SgTone.success);
  }

  /// Boutons modifier / supprimer (réservés au personnel).
  Widget _actions(Room r) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SgIconBtn(
        icon: Icons.edit_outlined,
        tooltip: 'Modifier',
        tone: SgTone.info,
        onPressed: _peutGerer ? () => _editer(room: r) : null,
      ),
      const SizedBox(width: 6),
      SgIconBtn(
        icon: Icons.delete_outline_rounded,
        tooltip: 'Supprimer',
        tone: SgTone.danger,
        onPressed: _peutGerer ? () => _supprimer(r) : null,
      ),
    ],
  );

  /// Pastille d'icône de salle.
  Widget _icone(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.goldSoft,
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    child: Icon(
      Icons.meeting_room_rounded,
      size: size * 0.5,
      color: AppColors.gold,
    ),
  );

  /// Affichage en tableau (écran large).
  Widget _tableau(List<Room> rooms, Set<String> occupees) {
    return SgCard(
      padding: EdgeInsets.zero,
      child: SgTable(
        minWidth: 700,
        columns: const [
          SgCol('Salle', flex: 4),
          SgCol('Capacité', flex: 2),
          SgCol('État', flex: 3),
          SgCol('Actions', flex: 2, align: Alignment.centerRight),
        ],
        rows: [
          for (final r in rooms)
            [
              Row(
                children: [
                  _icone(30),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '${r.capacity} places',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              SgBadge(_etat(r, occupees).$1, tone: _etat(r, occupees).$2),
              _actions(r),
            ],
        ],
      ),
    );
  }

  /// Affichage en cartes (téléphone).
  Widget _cartes(List<Room> rooms, Set<String> occupees) {
    return Column(
      children: [
        for (final r in rooms)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SgCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _icone(40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${r.capacity} places',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SgBadge(
                          _etat(r, occupees).$1,
                          tone: _etat(r, occupees).$2,
                        ),
                      ],
                    ),
                  ),
                  if (_peutGerer) _actions(r),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Grille d'indicateurs : 4 par ligne sur grand écran, 2 sinon.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.cards});

  /// Cartes à disposer.
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final perRow = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 440 ? 2 : 1);
        final w = (c.maxWidth - (perRow - 1) * gap) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }
}

/// Valeurs saisies dans le formulaire de salle.
class _RoomInput {
  const _RoomInput(this.name, this.capacity, this.isActive);

  /// Nom de la salle.
  final String name;

  /// Capacité en places.
  final int capacity;

  /// Salle utilisable pour des soutenances.
  final bool isActive;
}

/// Boîte de dialogue d'ajout / modification d'une salle.
class _RoomDialog extends StatefulWidget {
  const _RoomDialog({this.initial});

  /// Salle modifiée, ou `null` pour un ajout.
  final Room? initial;

  @override
  State<_RoomDialog> createState() => _RoomDialogState();
}

/// État du formulaire de salle.
class _RoomDialogState extends State<_RoomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _cap = TextEditingController(
    text: '${widget.initial?.capacity ?? 30}',
  );
  late bool _active = widget.initial?.isActive ?? true;

  @override
  void dispose() {
    _nom.dispose();
    _cap.dispose();
    super.dispose();
  }

  /// Valide la saisie puis renvoie les valeurs à l'écran appelant.
  void _valider() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _RoomInput(_nom.text.trim(), int.parse(_cap.text.trim()), _active),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Ajouter une salle' : 'Modifier la salle',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nom,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la salle',
                    prefixIcon: Icon(Icons.meeting_room_outlined),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _cap,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Capacité (places)',
                    prefixIcon: Icon(Icons.event_seat_outlined),
                  ),
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n <= 0) {
                      return 'Nombre strictement positif requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Salle active'),
                  subtitle: const Text(
                    'Une salle inactive n’est plus proposée à la planification.',
                  ),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        SgButton('Enregistrer', onPressed: _valider),
      ],
    );
  }
}
