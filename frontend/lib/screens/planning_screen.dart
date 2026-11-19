/// Planning des soutenances : calendrier mensuel, liste hebdomadaire ou
/// journalière, avec filtres (étudiant, année, salle, membre du jury).
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../providers/planning_store.dart';
import '../services/planning_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';
import 'defense_form_screen.dart';

/// Granularité d'affichage du planning.
enum PlanningView { jour, semaine, mois }

/// Écran du planning.
class PlanningScreen extends StatefulWidget {
  /// Crée l'écran du planning.
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

/// État du planning : vue, période affichée et filtres.
class _PlanningScreenState extends State<PlanningScreen> {
  late final PlanningService _service;
  late final bool _peutGerer;

  /// Vue courante (mois par défaut).
  PlanningView _view = PlanningView.mois;

  /// Date de référence de la période affichée.
  DateTime _cursor = DateTime.now();

  /// Jour sélectionné dans la vue mensuelle.
  DateTime _selected = DateTime.now();

  // Filtres actifs (null = aucun filtre).
  String? _salle;
  String? _jury;
  String _annee = 'Toutes';
  String _q = '';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _service = PlanningService(auth.api);
    _peutGerer = auth.canManage;
    // Chaque ouverture de l'écran resynchronise le planning.
    _charger();
  }

  /// Recharge le planning (et le catalogue pour le personnel).
  Future<void> _charger() async {
    try {
      await PlanningStore.refresh(_service, loadCatalog: _peutGerer);
    } catch (_) {
      // Erreur publiée dans PlanningStore.error et affichée par l'écran.
    }
  }

  /// Années universitaires proposées dans le filtre.
  List<String> _annees(List<Defense> all) {
    final set = <String>{anneeScolaire(DateTime.now())};
    for (final d in all) {
      final p = parseDefenseDate(d.date);
      if (p != null) set.add(anneeScolaire(p));
    }
    final list = set.toList()..sort();
    return ['Toutes', ...list.reversed];
  }

  /// Applique les filtres actifs et trie chronologiquement.
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
    }).toList()..sort(
      (a, b) => '${a.date}${a.startTime}'.compareTo('${b.date}${b.startTime}'),
    );
  }

  /// Avance ou recule d'une période ([delta] = +1 / -1).
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

  /// Libellé de la période affichée (ex. « Juillet 2026 »).
  String get _periodLabel {
    if (_view == PlanningView.jour) return longDate(_cursor);
    if (_view == PlanningView.semaine) {
      final monday = _cursor.subtract(Duration(days: _cursor.weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      return '${monday.day} ${moisLongs[monday.month - 1]} – '
          '${sunday.day} ${moisLongs[sunday.month - 1]} ${sunday.year}';
    }
    return '${moisLongs[_cursor.month - 1]} ${_cursor.year}';
  }

  /// Ouvre le formulaire de création puis recharge si besoin.
  Future<void> _nouvelle() async {
    final created = await pushPage<bool>(context, const DefenseFormScreen());
    if (created == true) await _charger();
  }

  /// Publie les soutenances confirmées dans une nouvelle version du
  /// planning (F05). Le serveur revérifie toutes les règles dans une seule
  /// transaction : au moindre problème, rien n'est publié et la liste des
  /// soutenances à corriger est affichée.
  Future<void> _publier() async {
    final aPublier = PlanningStore.defenses.value
        .where((d) => d.status == 'confirme' || d.status == 'reporte')
        .length;
    final commentaire = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publier le planning'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                aPublier == 0
                    ? 'Aucune soutenance confirmée n’attend de publication.'
                    : '$aPublier soutenance(s) confirmée(s) seront publiées dans une '
                          'nouvelle version figée du planning ; les convocations '
                          'seront produites pour l’étudiant et chaque membre du jury.',
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentaire,
                decoration: const InputDecoration(labelText: 'Commentaire (facultatif)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          SgButton(
            'Publier',
            icon: Icons.campaign_rounded,
            onPressed: aPublier == 0 ? null : () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Une clé par action : relancer après une coupure ne publie pas deux fois.
    final cle = ApiService.nouvelleCleIdempotence();
    try {
      final version = await _service.publier(commentaire: commentaire.text.trim(), cle: cle);
      if (!mounted) return;
      SgToast.show(
        context,
        'Planning publié : version ${version['numero']} '
        '(${version['nombre_soutenances']} soutenance(s)).',
      );
      await _charger();
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.planning,
      title: 'Planning des soutenances',
      subtitle: _peutGerer
          ? 'Toutes les soutenances, synchronisées avec le serveur.'
          : 'Les soutenances de vos jurys.',
      onRefresh: _charger,
      actions: [
        SgButton(
          'Actualiser',
          icon: Icons.refresh_rounded,
          variant: SgBtnVariant.outline,
          onPressed: _charger,
        ),
        if (_peutGerer) ...[
          SgButton(
            'Publier le planning',
            icon: Icons.campaign_rounded,
            variant: SgBtnVariant.dark,
            onPressed: _publier,
          ),
          SgButton(
            'Nouvelle soutenance',
            icon: Icons.add_rounded,
            onPressed: _nouvelle,
          ),
        ],
      ],
      // Observation des trois états partagés du planning.
      child: ValueListenableBuilder<bool>(
        valueListenable: PlanningStore.loading,
        builder: (context, loading, _) => ValueListenableBuilder<String?>(
          valueListenable: PlanningStore.error,
          builder: (context, error, _) => ValueListenableBuilder<List<Defense>>(
            valueListenable: PlanningStore.defenses,
            builder: (context, all, _) {
              if (loading && all.isEmpty) {
                return const SgLoading(message: 'Chargement du planning…');
              }
              if (error != null && all.isEmpty) {
                return SgErrorState(
                  title: 'Impossible de charger le planning',
                  message: error,
                  onRetry: _charger,
                );
              }
              return _contenu(all, error);
            },
          ),
        ),
      ),
    );
  }

  /// Contenu principal : barre d'outils puis vue sélectionnée.
  Widget _contenu(List<Defense> all, String? error) {
    final data = _apply(all);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Données affichées mais dernier rechargement en échec.
        if (error != null) ...[
          SgBanner(message: error, tone: SgTone.warning),
          const SizedBox(height: 14),
        ],
        _toolbar(all),
        const SizedBox(height: 18),
        if (_view == PlanningView.mois) ...[
          _monthGrid(data),
          const SizedBox(height: 22),
          SgSectionTitle(
            'Soutenances du ${shortDate(_selected)}',
            subtitle:
                '${_pour(_selected, data).length} soutenance(s) programmée(s).',
          ),
          const SizedBox(height: 12),
          _dayList(_pour(_selected, data)),
        ] else if (_view == PlanningView.semaine)
          _weekList(data)
        else
          _dayList(_pour(_cursor, data)),
      ],
    );
  }

  /// Soutenances d'un jour [day], triées par heure de début.
  List<Defense> _pour(DateTime day, List<Defense> data) =>
      data.where((d) {
        final p = parseDefenseDate(d.date);
        return p != null && sameDay(p, day);
      }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));

  /// Barre d'outils : choix de vue, navigation temporelle et filtres.
  Widget _toolbar(List<Defense> all) {
    return SgCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 640;
              // Boutons précédent / aujourd'hui / suivant.
              final nav = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SgIconBtn(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Précédent',
                    onPressed: () => _shift(-1),
                  ),
                  const SizedBox(width: 6),
                  SgButton(
                    'Aujourd’hui',
                    variant: SgBtnVariant.outline,
                    dense: true,
                    onPressed: () => setState(() {
                      _cursor = DateTime.now();
                      _selected = DateTime.now();
                    }),
                  ),
                  const SizedBox(width: 6),
                  SgIconBtn(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Suivant',
                    onPressed: () => _shift(1),
                  ),
                ],
              );
              // Puces de choix de la vue.
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
              final periode = Text(
                _periodLabel,
                textAlign: wide ? TextAlign.left : TextAlign.right,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
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
                        const SizedBox(width: 10),
                        Expanded(child: periode),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  views,
                  const Spacer(),
                  periode,
                  const SizedBox(width: 16),
                  nav,
                ],
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(),
          ),
          // Filtres (passent à la ligne sur petit écran).
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SgSearch(
                width: 220,
                hint: 'Rechercher un étudiant…',
                onChanged: (v) => setState(() => _q = v),
              ),
              SgSelect<String>(
                width: 160,
                icon: Icons.school_outlined,
                value: _annee,
                items: [
                  for (final a in _annees(all))
                    DropdownMenuItem(value: a, child: Text(a)),
                ],
                onChanged: (v) => setState(() => _annee = v ?? 'Toutes'),
              ),
              // Filtres de catalogue : réservés au personnel.
              if (PlanningStore.rooms.isNotEmpty)
                SgSelect<String?>(
                  width: 180,
                  icon: Icons.meeting_room_outlined,
                  value: _salle,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Toutes les salles'),
                    ),
                    for (final r in PlanningStore.rooms)
                      DropdownMenuItem<String?>(value: r, child: Text(r)),
                  ],
                  onChanged: (v) => setState(() => _salle = v),
                ),
              if (PlanningStore.juryMembers.isNotEmpty)
                SgSelect<String?>(
                  width: 200,
                  icon: Icons.groups_2_outlined,
                  value: _jury,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous les jurys'),
                    ),
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

  /// Grille mensuelle (lignes de 7 jours, lundi en premier).
  Widget _monthGrid(List<Defense> data) {
    final first = DateTime(_cursor.year, _cursor.month, 1);
    // Nombre de cases vides avant le 1er (lundi = 0).
    final offset = first.weekday - 1;
    final daysInMonth = DateTime(_cursor.year, _cursor.month + 1, 0).day;
    final rows = ((offset + daysInMonth) / 7).ceil();

    return SgCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // En-tête des jours de la semaine.
          Row(
            children: [
              for (final j in joursCourts)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(child: SgOverline(j)),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < rows; r++)
            SizedBox(
              height: 78,
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

  /// Case d'un jour de la grille mensuelle.
  ///
  /// [index] est la position dans la grille ; la case est vide si elle
  /// tombe hors du mois affiché.
  Widget _cell(int index, int offset, int daysInMonth, List<Defense> data) {
    final dayNum = index - offset + 1;
    final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
    final date = inMonth ? DateTime(_cursor.year, _cursor.month, dayNum) : null;
    final count = date == null ? 0 : _pour(date, data).length;
    final selected = date != null && sameDay(date, _selected);
    final today = date != null && sameDay(date, DateTime.now());

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: inMonth ? () => setState(() => _selected = date!) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ink
              : (inMonth ? AppColors.white : AppColors.surfaceAlt),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: today && !selected ? AppColors.gold : AppColors.line,
            width: today && !selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              inMonth ? '$dayNum' : '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : (inMonth ? AppColors.ink : AppColors.greyLight),
              ),
            ),
            const Spacer(),
            // Pastille du nombre de soutenances du jour.
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? AppColors.gold : AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Vue semaine : une carte par jour, du lundi au dimanche.
  Widget _weekList(List<Defense> data) {
    final monday = _cursor.subtract(Duration(days: _cursor.weekday - 1));
    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final day = monday.add(Duration(days: i));
              final items = _pour(day, data);
              final today = sameDay(day, DateTime.now());
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SgCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            joursLongs[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: today ? AppColors.ink : AppColors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${day.day} ${moisLongs[day.month - 1]}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.greyLight,
                            ),
                          ),
                          const Spacer(),
                          SgBadge(
                            '${items.length}',
                            tone: items.isEmpty ? SgTone.neutral : SgTone.gold,
                          ),
                        ],
                      ),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Aucune soutenance',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.greyLight,
                            ),
                          ),
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
            },
          ),
      ],
    );
  }

  /// Liste des soutenances d'un jour (ou état vide).
  Widget _dayList(List<Defense> items) {
    if (items.isEmpty) {
      return SgEmpty(
        icon: Icons.event_busy_outlined,
        title: 'Aucune soutenance ce jour',
        message: _peutGerer
            ? 'Sélectionnez une autre date ou créez une nouvelle soutenance.'
            : 'Sélectionnez une autre date.',
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

  /// Ligne compacte d'une soutenance (ouvre sa fiche au clic).
  Widget _ligne(BuildContext context, Defense d) {
    return SgCard(
      padding: const EdgeInsets.all(12),
      onTap: () => pushPage(context, DefenseDetailScreen(defense: d)),
      child: Row(
        children: [
          // Pavé horaire début / fin.
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  d.startTime,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  d.endTime,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  d.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _mini(Icons.meeting_room_outlined, d.roomName),
                    _mini(Icons.groups_2_outlined, d.juryName),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SgStatusBadge(d.status),
        ],
      ),
    );
  }

  /// Petite métadonnée « icône + texte ».
  Widget _mini(IconData i, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(i, size: 12, color: AppColors.greyLight),
      const SizedBox(width: 4),
      Text(t, style: const TextStyle(fontSize: 11.5, color: AppColors.grey)),
    ],
  );
}
