/// Module « Évaluations » : saisie des notes des soutenances (rapport et
/// oral, sur 20), calcul de la moyenne et validation finale.
///
/// Réservé au personnel (administrateur, responsable pédagogique). Une note
/// validée devient visible par l'étudiant dans son profil.
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
enum _Filtre { toutes, aEvaluer, evaluees, validees }

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
    final api = context.read<AuthProvider>().api;
    _planning = PlanningService(api);
    _service = EvaluationService(api);
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

  /// Ouvre la saisie des notes de [defense] puis enregistre.
  Future<void> _saisir(Defense defense) async {
    final existante = _parSoutenance[defense.id];
    final saisie = await showDialog<_Saisie>(
      context: context,
      builder: (_) => _NotesDialog(defense: defense, initiale: existante),
    );
    if (saisie == null || !mounted) return;
    try {
      if (existante == null) {
        await _service.createEvaluation(
          defenseId: defense.id,
          reportGrade: saisie.rapport,
          oralGrade: saisie.oral,
          isApproved: saisie.validee,
        );
      } else {
        await _service.updateEvaluation(
          existante.id,
          reportGrade: saisie.rapport,
          oralGrade: saisie.oral,
          isApproved: saisie.validee,
        );
      }
      if (!mounted) return;
      SgToast.show(context, 'Notes de ${defense.studentName} enregistrées.');
      await _charger();
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  /// Soutenances correspondant au filtre actif.
  List<Defense> get _visibles => _soutenances.where((d) {
    final e = _parSoutenance[d.id];
    return switch (_filtre) {
      _Filtre.toutes => true,
      _Filtre.aEvaluer => e == null,
      _Filtre.evaluees => e != null,
      _Filtre.validees => e?.isApproved == true,
    };
  }).toList();

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.evaluations,
      title: 'Évaluations des soutenances',
      subtitle:
          'Saisissez les notes du rapport et de l’oral ; validez-les pour '
          'les rendre visibles aux étudiants.',
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
    final validees = evaluations.where((e) => e.isApproved).length;
    final moyennes = evaluations
        .map((e) => e.finalAverage)
        .whereType<double>()
        .toList();
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
                label: 'Notes validées',
                value: '$validees',
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
                  _Filtre.validees => 'Validées',
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
                ? 'Planifiez des soutenances pour pouvoir les évaluer.'
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
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
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
          final bouton = SgButton(
            e == null ? 'Saisir les notes' : 'Modifier',
            icon: e == null ? Icons.edit_note_rounded : Icons.edit_outlined,
            variant: e == null ? SgBtnVariant.primary : SgBtnVariant.outline,
            dense: true,
            onPressed: () => _saisir(d),
          );
          // Téléphone : éléments empilés ; grand écran : sur une ligne.
          if (c.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [infos, const SizedBox(height: 12), notes, const SizedBox(height: 12), bouton],
            );
          }
          return Row(
            children: [
              Expanded(child: infos),
              const SizedBox(width: 16),
              notes,
              const SizedBox(width: 16),
              bouton,
            ],
          );
        },
      ),
    );
  }

  /// Résumé des notes : rapport, oral, moyenne et validation.
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
          e.isApproved ? 'Validée' : 'Non validée',
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

/// Valeurs saisies dans la boîte de dialogue des notes.
class _Saisie {
  const _Saisie(this.rapport, this.oral, this.validee);

  /// Note du rapport (sur 20).
  final double rapport;

  /// Note de l'oral (sur 20).
  final double oral;

  /// Validation de la note (visible par l'étudiant).
  final bool validee;
}

/// Boîte de dialogue de saisie des notes, avec moyenne en direct.
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
  late final _rapport = TextEditingController(
    text: _texte(widget.initiale?.reportGrade),
  );
  late final _oral = TextEditingController(text: _texte(widget.initiale?.oralGrade));
  late bool _validee = widget.initiale?.isApproved ?? false;

  @override
  void dispose() {
    _rapport.dispose();
    _oral.dispose();
    super.dispose();
  }

  /// Valeur initiale d'un champ (vide si pas de note).
  static String _texte(double? note) =>
      note == null ? '' : note.toStringAsFixed(2).replaceAll('.', ',');

  /// Convertit une saisie (`15,5` ou `15.5`) en nombre, ou `null`.
  static double? _lire(String texte) =>
      double.tryParse(texte.trim().replaceAll(',', '.'));

  /// Vérifie qu'une note est un nombre entre 0 et 20.
  String? _verifier(String? texte) {
    final note = _lire(texte ?? '');
    if (note == null) return 'Saisissez une note (ex. 15,5).';
    if (note < 0 || note > 20) return 'La note doit être comprise entre 0 et 20.';
    return null;
  }

  /// Moyenne affichée en direct (ou `null` si une note est invalide).
  double? get _moyenne {
    final r = _lire(_rapport.text);
    final o = _lire(_oral.text);
    if (r == null || o == null || r < 0 || r > 20 || o < 0 || o > 20) return null;
    return (r + o) / 2;
  }

  /// Valide puis renvoie la saisie à l'écran appelant.
  void _enregistrer() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _Saisie(_lire(_rapport.text)!, _lire(_oral.text)!, _validee),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Notes — ${widget.defense.studentName}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
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
                      decoration: const InputDecoration(
                        labelText: 'Note du rapport',
                        suffixText: '/ 20',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: _verifier,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _oral,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Note de l’oral',
                        suffixText: '/ 20',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: _verifier,
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
                        'Moyenne finale',
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Valider la note'),
                subtitle: const Text('Une note validée est visible par l’étudiant.'),
                value: _validee,
                onChanged: (v) => setState(() => _validee = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        SgButton('Enregistrer', icon: Icons.check_rounded, onPressed: _enregistrer),
      ],
    );
  }
}
