/// Module « Évaluations » (F06) : notes des soutenances, approbation et
/// procès-verbaux.
///
/// * Personnel et membres du jury saisissent les notes du rapport et de
///   l'oral (sur 20). Une note laissée vide reste ABSENTE : elle n'est
///   jamais comptée comme zéro et bloque l'approbation.
/// * La moyenne est calculée par le serveur selon la grille de la campagne
///   (règle fictive de démonstration : rapport 40 %, oral 60 %, arrondi au
///   centième) ; l'écran n'en montre qu'un aperçu.
/// * L'approbation (personnel ou président du jury) fige les notes dans un
///   procès-verbal. Une note approuvée ne se modifie plus : seul le
///   responsable la corrige par une RECTIFICATION motivée, qui crée une
///   nouvelle version du procès-verbal (l'ancienne reste consultable).
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../models/defense.dart';
import '../models/evaluation.dart';
import '../providers/auth_provider.dart';
import '../services/evaluation_service.dart';
import '../services/planning_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Filtres de la liste des soutenances.
enum _Filtre { toutes, aEvaluer, evaluees, approuvees }

/// Écran des évaluations.
class EvaluationsScreen extends StatefulWidget {
  /// Crée l'écran des évaluations.
  const EvaluationsScreen({super.key});

  @override
  State<EvaluationsScreen> createState() => _EvaluationsScreenState();
}

/// État de l'écran : soutenances, évaluations associées et filtre.
class _EvaluationsScreenState extends State<EvaluationsScreen> {
  late final PlanningService _planning;
  late final EvaluationService _service;

  /// Vrai pour le personnel (seul autorisé à rectifier une note approuvée).
  late final bool _estPersonnel;

  /// Soutenances (hors soutenances annulées), par ordre chronologique.
  List<Defense> _soutenances = const [];

  /// Évaluations indexées par identifiant de soutenance.
  Map<int, Evaluation> _parSoutenance = const {};

  bool _loading = true;
  String? _error;
  _Filtre _filtre = _Filtre.toutes;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _planning = PlanningService(auth.api);
    _service = EvaluationService(auth.api);
    _estPersonnel = auth.canManage;
    _charger();
  }

  /// Charge en parallèle le planning et les évaluations.
  Future<void> _charger() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _planning.loadDefenses(),
        _service.loadEvaluations(),
      ]);
      if (!mounted) return;
      final soutenances = (results[0] as List<Defense>)
          .where((d) => d.status != 'annule')
          .toList();
      final evaluations = results[1] as List<Evaluation>;
      setState(() {
        _soutenances = soutenances;
        _parSoutenance = {for (final e in evaluations) e.defenseId: e};
        _loading = false;
      });
    } on ApiException catch (e) {
      _echec(e.message);
    } catch (_) {
      _echec('Impossible de charger les évaluations.');
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

  /// Exécute une action serveur puis recharge, avec un message de retour.
  Future<void> _executer(Future<void> Function() action, String succes) async {
    try {
      await action();
      if (!mounted) return;
      SgToast.show(context, succes);
      await _charger();
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  /// Ouvre la saisie des notes de [defense] puis enregistre.
  Future<void> _saisir(Defense defense) async {
    final existante = _parSoutenance[defense.id];
    final saisie = await showDialog<_Saisie>(
      context: context,
      builder: (_) => _NotesDialog(defense: defense, initiale: existante),
    );
    if (saisie == null || !mounted) return;
    await _executer(
      () => existante == null
          ? _service.createEvaluation(
              defenseId: defense.id,
              reportGrade: saisie.rapport,
              oralGrade: saisie.oral,
            )
          : _service.updateEvaluation(
              existante.id,
              reportGrade: saisie.rapport,
              oralGrade: saisie.oral,
            ),
      'Notes de ${defense.studentName} enregistrées.',
    );
  }

  /// Approuve l'évaluation [e] (procès-verbal v1) après confirmation.
  Future<void> _approuver(Evaluation e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approuver les notes'),
        content: Text(
          'Les notes de ${e.studentName} seront figées dans un procès-verbal et '
          'visibles par l’étudiant. Une correction ultérieure exigera une '
          'rectification motivée.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Retour')),
          SgButton('Approuver', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cle = ApiService.nouvelleCleIdempotence();
    await _executer(
      () => _service.approuver(e.id, cle: cle),
      'Notes approuvées : procès-verbal enregistré.',
    );
  }

  /// Rectifie une note approuvée (responsable, motif obligatoire).
  Future<void> _rectifier(Defense d, Evaluation e) async {
    final saisie = await showDialog<_Rectification>(
      context: context,
      builder: (_) => _RectificationDialog(defense: d, evaluation: e),
    );
    if (saisie == null || !mounted) return;
    final cle = ApiService.nouvelleCleIdempotence();
    await _executer(
      () => _service.rectifier(
        e.id,
        reportGrade: saisie.rapport,
        oralGrade: saisie.oral,
        motif: saisie.motif,
        cle: cle,
      ),
      'Rectification enregistrée : nouvelle version du procès-verbal.',
    );
  }

  /// Affiche les versions du procès-verbal de [e].
  Future<void> _ouvrirProcesVerbaux(Evaluation e) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProcesVerbauxSheet(
        titre: e.studentName,
        future: _service.procesVerbaux(e.id),
      ),
    );
  }

  /// Soutenances correspondant au filtre actif.
  List<Defense> get _visibles => _soutenances.where((d) {
    final e = _parSoutenance[d.id];
    return switch (_filtre) {
      _Filtre.toutes => true,
      _Filtre.aEvaluer => e == null,
      _Filtre.evaluees => e != null,
      _Filtre.approuvees => e?.isApproved == true,
    };
  }).toList();

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.evaluations,
      title: 'Évaluations des soutenances',
      subtitle:
          'Moyenne calculée par le serveur : rapport 40 %, oral 60 % (règle '
          'fictive de démonstration). L’approbation fige un procès-verbal.',
      onRefresh: _charger,
      actions: [
        SgButton(
          'Actualiser',
          icon: Icons.refresh_rounded,
          variant: SgBtnVariant.outline,
          onPressed: _charger,
        ),
      ],
      child: _loading
          ? const SgLoading(message: 'Chargement des évaluations…')
          : _error != null
          ? SgErrorState(
              title: 'Impossible de charger les évaluations',
              message: _error!,
              onRetry: _charger,
            )
          : _contenu(),
    );
  }

  /// Indicateurs, filtres puis liste des soutenances.
  Widget _contenu() {
    final evaluations = _parSoutenance.values.toList();
    final approuvees = evaluations.where((e) => e.isApproved).length;
    final moyennes = evaluations.map((e) => e.finalAverage).whereType<double>().toList();
    final moyenneGenerale = moyennes.isEmpty
        ? null
        : moyennes.reduce((a, b) => a + b) / moyennes.length;
    final visibles = _visibles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const gap = 12.0;
            final perRow = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 440 ? 2 : 1);
            final w = (c.maxWidth - (perRow - 1) * gap) / perRow;
            final cartes = [
              SgStatCard(
                label: 'Soutenances',
                value: '${_soutenances.length}',
                icon: Icons.event_available_rounded,
              ),
              SgStatCard(
                label: 'À évaluer',
                value: '${_soutenances.length - evaluations.length}',
                icon: Icons.pending_actions_rounded,
                tone: SgTone.warning,
              ),
              SgStatCard(
                label: 'Notes approuvées',
                value: '$approuvees',
                icon: Icons.verified_rounded,
                tone: SgTone.success,
              ),
              SgStatCard(
                label: 'Moyenne générale',
                value: moyenneGenerale == null
                    ? '—'
                    : moyenneGenerale.toStringAsFixed(2).replaceAll('.', ','),
                icon: Icons.workspace_premium_rounded,
                tone: SgTone.info,
                foot: moyenneGenerale == null ? null : 'sur 20',
              ),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final c in cartes) SizedBox(width: w, child: c)],
            );
          },
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _Filtre.values)
              SgChip(
                label: switch (f) {
                  _Filtre.toutes => 'Toutes',
                  _Filtre.aEvaluer => 'À évaluer',
                  _Filtre.evaluees => 'Évaluées',
                  _Filtre.approuvees => 'Approuvées',
                },
                selected: _filtre == f,
                onTap: () => setState(() => _filtre = f),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (visibles.isEmpty)
          SgEmpty(
            icon: Icons.workspace_premium_outlined,
            title: _soutenances.isEmpty ? 'Aucune soutenance' : 'Aucun résultat',
            message: _soutenances.isEmpty
                ? 'Aucune soutenance à évaluer pour le moment.'
                : 'Aucune soutenance ne correspond à ce filtre.',
          )
        else
          for (final d in visibles)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _carte(d, _parSoutenance[d.id]),
            ),
      ],
    );
  }

  /// Boutons disponibles selon l'état de l'évaluation et le rôle.
  List<Widget> _actions(Defense d, Evaluation? e) {
    if (e == null) {
      return [
        SgButton(
          'Saisir les notes',
          icon: Icons.edit_note_rounded,
          dense: true,
          onPressed: () => _saisir(d),
        ),
      ];
    }
    if (!e.isApproved) {
      return [
        SgButton(
          'Modifier',
          icon: Icons.edit_outlined,
          variant: SgBtnVariant.outline,
          dense: true,
          onPressed: () => _saisir(d),
        ),
        SgButton(
          'Approuver',
          icon: Icons.verified_rounded,
          variant: SgBtnVariant.dark,
          dense: true,
          onPressed: () => _approuver(e),
        ),
      ];
    }
    return [
      if (_estPersonnel)
        SgButton(
          'Rectifier',
          icon: Icons.history_edu_rounded,
          variant: SgBtnVariant.outline,
          dense: true,
          onPressed: () => _rectifier(d, e),
        ),
      SgButton(
        'Procès-verbaux',
        icon: Icons.description_outlined,
        variant: SgBtnVariant.outline,
        dense: true,
        onPressed: () => _ouvrirProcesVerbaux(e),
      ),
    ];
  }

  /// Carte d'une soutenance et de son évaluation éventuelle.
  Widget _carte(Defense d, Evaluation? e) {
    final date = parseDefenseDate(d.date);
    return SgCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final infos = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      d.studentName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SgStatusBadge(d.status),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                d.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              const SizedBox(height: 6),
              Text(
                '${date == null ? d.date : shortDate(date)} · ${d.startTime}'
                ' · ${d.roomName} · ${d.juryName}',
                style: const TextStyle(fontSize: 12, color: AppColors.greyLight),
              ),
            ],
          );
          final notes = _notes(e);
          final boutons = Wrap(spacing: 8, runSpacing: 8, children: _actions(d, e));
          // Téléphone : éléments empilés ; grand écran : sur une ligne.
          if (c.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [infos, const SizedBox(height: 12), notes, const SizedBox(height: 12), boutons],
            );
          }
          return Row(
            children: [
              Expanded(child: infos),
              const SizedBox(width: 16),
              notes,
              const SizedBox(width: 16),
              boutons,
            ],
          );
        },
      ),
    );
  }

  /// Résumé des notes : rapport, oral, moyenne et approbation.
  Widget _notes(Evaluation? e) {
    if (e == null) {
      return const SgBadge('Non évaluée', tone: SgTone.neutral);
    }
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _note('Rapport', e.reportGrade),
        _note('Oral', e.oralGrade),
        _note('Moyenne', e.finalAverage, accent: true),
        SgBadge(
          e.isApproved
              ? 'Approuvée · PV v${e.nombreProcesVerbaux}'
              : 'Non approuvée',
          tone: e.isApproved ? SgTone.success : SgTone.warning,
        ),
      ],
    );
  }

  /// Une note avec son libellé ; [accent] la met en valeur (moyenne).
  Widget _note(String libelle, double? valeur, {bool accent = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SgOverline(libelle),
        const SizedBox(height: 2),
        Text(
          formatNote(valeur),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: accent ? FontWeight.w800 : FontWeight.w600,
            color: accent ? AppColors.goldDeep : AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// Lit une note saisie (`15,5` ou `15.5`) ; `null` si vide ou illisible.
double? _lireNote(String texte) => double.tryParse(texte.trim().replaceAll(',', '.'));

/// Écrit une note dans un champ (vide si absente).
String _texteNote(double? note) =>
    note == null ? '' : note.toStringAsFixed(2).replaceAll('.', ',');

/// Vérifie une note : vide accepté si [facultatif], sinon nombre de 0 à 20.
String? _verifierNote(String? texte, {bool facultatif = true}) {
  final brut = (texte ?? '').trim();
  if (brut.isEmpty) return facultatif ? null : 'Saisissez une note (ex. 15,5).';
  final note = _lireNote(brut);
  if (note == null) return 'Note illisible (ex. 15,5).';
  if (note < 0 || note > 20) return 'La note doit être comprise entre 0 et 20.';
  return null;
}

/// Valeurs saisies dans la boîte de dialogue des notes.
class _Saisie {
  const _Saisie(this.rapport, this.oral);

  /// Note du rapport (sur 20), ou `null` si encore absente.
  final double? rapport;

  /// Note de l'oral (sur 20), ou `null` si encore absente.
  final double? oral;
}

/// Boîte de dialogue de saisie des notes, avec aperçu de la moyenne.
class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.defense, this.initiale});

  /// Soutenance évaluée.
  final Defense defense;

  /// Évaluation existante (modification), ou `null` (première saisie).
  final Evaluation? initiale;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

/// État de la saisie : champs, validation et aperçu de la moyenne.
class _NotesDialogState extends State<_NotesDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _rapport = TextEditingController(text: _texteNote(widget.initiale?.reportGrade));
  late final _oral = TextEditingController(text: _texteNote(widget.initiale?.oralGrade));

  /// Coefficients de la grille (ceux de l'évaluation, sinon 40/60).
  double get _poidsRapport => widget.initiale?.poidsRapport ?? 0.4;
  double get _poidsOral => widget.initiale?.poidsOral ?? 0.6;

  @override
  void dispose() {
    _rapport.dispose();
    _oral.dispose();
    super.dispose();
  }

  /// Aperçu de la moyenne pondérée, ou `null` si une note manque.
  double? get _moyenne {
    final r = _lireNote(_rapport.text);
    final o = _lireNote(_oral.text);
    if (r == null || o == null || r < 0 || r > 20 || o < 0 || o > 20) return null;
    return _poidsRapport * r + _poidsOral * o;
  }

  /// Valide puis renvoie la saisie à l'écran appelant.
  void _enregistrer() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _Saisie(_lireNote(_rapport.text), _lireNote(_oral.text)));
  }

  @override
  Widget build(BuildContext context) {
    final pr = (_poidsRapport * 100).round();
    final po = (_poidsOral * 100).round();
    return AlertDialog(
      title: Text('Notes — ${widget.defense.studentName}'),
      content: SizedBox(
        width: 440,
        child: SgFormulaire(
          formKey: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.defense.subject,
                style: const TextStyle(fontSize: 13, color: AppColors.grey),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rapport,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Rapport ($pr %)',
                        suffixText: '/ 20',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: _verifierNote,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _oral,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Oral ($po %)', suffixText: '/ 20'),
                      onChanged: (_) => setState(() {}),
                      validator: _verifierNote,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Aperçu de la moyenne, recalculée à chaque frappe.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Moyenne (aperçu)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      formatNote(_moyenne),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.goldDeep,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Une note laissée vide reste absente (jamais zéro) et bloque '
                'l’approbation. La moyenne définitive est calculée par le serveur.',
                style: TextStyle(fontSize: 11.5, color: AppColors.grey, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        SgButton('Enregistrer', icon: Icons.check_rounded, onPressed: _enregistrer),
      ],
    );
  }
}

/// Valeurs d'une rectification : nouvelles notes et motif.
class _Rectification {
  const _Rectification(this.rapport, this.oral, this.motif);

  final double rapport;
  final double oral;

  /// Motif obligatoire, conservé dans le procès-verbal.
  final String motif;
}

/// Boîte de dialogue de rectification d'une note approuvée.
class _RectificationDialog extends StatefulWidget {
  const _RectificationDialog({required this.defense, required this.evaluation});

  final Defense defense;
  final Evaluation evaluation;

  @override
  State<_RectificationDialog> createState() => _RectificationDialogState();
}

/// État de la rectification.
class _RectificationDialogState extends State<_RectificationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _rapport = TextEditingController(text: _texteNote(widget.evaluation.reportGrade));
  late final _oral = TextEditingController(text: _texteNote(widget.evaluation.oralGrade));
  final _motif = TextEditingController();

  @override
  void dispose() {
    _rapport.dispose();
    _oral.dispose();
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rectifier — ${widget.defense.studentName}'),
      content: SizedBox(
        width: 440,
        child: SgFormulaire(
          formKey: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'La rectification crée une nouvelle version du procès-verbal ; '
                'la version actuelle reste consultable.',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rapport,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Rapport', suffixText: '/ 20'),
                      validator: (v) => _verifierNote(v, facultatif: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _oral,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Oral', suffixText: '/ 20'),
                      validator: (v) => _verifierNote(v, facultatif: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motif,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Motif (obligatoire)'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Le motif est obligatoire.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        SgButton(
          'Rectifier',
          icon: Icons.history_edu_rounded,
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _Rectification(
                _lireNote(_rapport.text)!,
                _lireNote(_oral.text)!,
                _motif.text.trim(),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Panneau des versions du procès-verbal d'une évaluation.
class _ProcesVerbauxSheet extends StatelessWidget {
  const _ProcesVerbauxSheet({required this.titre, required this.future});

  /// Nom de l'étudiant (titre du panneau).
  final String titre;

  /// Chargement des versions.
  final Future<List<Map<String, dynamic>>> future;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Procès-verbaux — $titre',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SgLoading();
                  }
                  if (snapshot.hasError) {
                    final erreur = snapshot.error;
                    return SgBanner(
                      message: erreur is ApiException ? erreur.message : 'Chargement impossible.',
                      tone: SgTone.danger,
                    );
                  }
                  final versions = (snapshot.data ?? const []).reversed.toList();
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final v in versions)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SgBadge('v${v['version']}', tone: SgTone.gold, dot: false),
                                  const SizedBox(width: 8),
                                  SgStatusBadge(v['statut']?.toString() ?? ''),
                                  const Spacer(),
                                  Text(
                                    'Moyenne ${v['moyenne']}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Rapport ${v['note_rapport']} · Oral ${v['note_oral']} · grille '
                                'v${v['version_grille']} (${v['poids_rapport']} / ${v['poids_oral']})'
                                '${v['approuve_par_nom'] != null ? ' · par ${v['approuve_par_nom']}' : ''}',
                                style: const TextStyle(fontSize: 12, color: AppColors.grey),
                              ),
                              if ((v['motif'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Motif : ${v['motif']}',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
