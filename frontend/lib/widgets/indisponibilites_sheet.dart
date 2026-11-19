/// Panneau des indisponibilités récurrentes d'une ressource (complément F04,
/// STA09) : un membre de jury ou une salle.
///
/// Une règle dit « chaque <jour> de <heure> à <heure>, du <date> au <date> »
/// dans le fuseau métier ; des dates d'exception rendent la ressource
/// disponible certains jours. Le serveur refuse ensuite tout créneau qui
/// tombe sur une occurrence. Une règle ajoutée APRÈS publication ne déplace
/// aucune soutenance : le serveur renvoie seulement des alertes, affichées
/// ici, pour que le planificateur décide (report ou maintien).
library;

import 'package:material_ui/material_ui.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../services/planning_service.dart';
import 'ui_kit.dart';

/// Jours de la semaine, dans l'ordre du serveur (0 = lundi).
const _jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

/// Ouvre le panneau des indisponibilités de [ressource].
///
/// [typeRessource] : `membre` (nom du membre de jury) ou `salle`.
Future<void> ouvrirIndisponibilites(
  BuildContext context, {
  required PlanningService service,
  required String typeRessource,
  required String ressource,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _IndisponibilitesSheet(
      service: service,
      typeRessource: typeRessource,
      ressource: ressource,
    ),
  );
}

class _IndisponibilitesSheet extends StatefulWidget {
  const _IndisponibilitesSheet({
    required this.service,
    required this.typeRessource,
    required this.ressource,
  });

  final PlanningService service;
  final String typeRessource;
  final String ressource;

  @override
  State<_IndisponibilitesSheet> createState() => _IndisponibilitesSheetState();
}

/// État du panneau : règles existantes et formulaire d'ajout.
class _IndisponibilitesSheetState extends State<_IndisponibilitesSheet> {
  late Future<List<Map<String, dynamic>>> _regles;

  // Formulaire d'une nouvelle règle.
  int _jour = 0;
  TimeOfDay _debut = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _fin = const TimeOfDay(hour: 12, minute: 0);
  DateTime _du = DateTime.now();
  DateTime _au = DateTime.now().add(const Duration(days: 30));
  final List<DateTime> _exceptions = [];
  final TextEditingController _motif = TextEditingController();
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  void _charger() {
    setState(() => _regles = widget.service.indisponibilites(ressource: widget.ressource));
  }

  static String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Enregistre la règle et affiche les éventuelles alertes.
  Future<void> _ajouter() async {
    setState(() => _envoi = true);
    try {
      final reponse = await widget.service.creerIndisponibilite({
        'type_ressource': widget.typeRessource,
        'ressource': widget.ressource,
        'jour_semaine': _jour,
        'heure_debut': _hhmm(_debut),
        'heure_fin': _hhmm(_fin),
        'valide_du': isoDate(_du),
        'valide_au': isoDate(_au),
        'motif': _motif.text.trim(),
        'exceptions': [for (final d in _exceptions) isoDate(d)],
      });
      if (!mounted) return;
      final alertes = (reponse['alertes'] as List?) ?? const [];
      SgToast.show(
        context,
        alertes.isEmpty
            ? 'Indisponibilité enregistrée.'
            : 'Enregistrée. ${alertes.length} soutenance(s) déjà publiée(s) concernée(s) : '
                  'à reporter ou à maintenir (rien n’est déplacé automatiquement).',
        tone: alertes.isEmpty ? SgTone.success : SgTone.warning,
      );
      _exceptions.clear();
      _motif.clear();
      _charger();
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _supprimer(int id) async {
    try {
      await widget.service.supprimerIndisponibilite(id);
      _charger();
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  Future<DateTime?> _choisirDate(DateTime initiale) => showDatePicker(
    context: context,
    initialDate: initiale,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Indisponibilités — ${widget.ressource}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'Règles hebdomadaires dans le fuseau métier ; une exception libère '
                'une date précise.',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _regles,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SgLoading();
                  }
                  final regles = snapshot.data ?? const [];
                  if (regles.isEmpty) {
                    return const Text(
                      'Aucune indisponibilité enregistrée.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                    );
                  }
                  return Column(
                    children: [
                      for (final r in regles)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_busy_rounded, color: AppColors.goldDeep),
                          title: Text(
                            '${r['jour_libelle']} ${r['heure_debut'].toString().substring(0, 5)}'
                            '–${r['heure_fin'].toString().substring(0, 5)}',
                          ),
                          subtitle: Text(
                            'Du ${r['valide_du']} au ${r['valide_au']} · ${r['fuseau']}'
                            '${(r['exceptions'] as List?)?.isNotEmpty == true ? ' · exceptions : ${(r['exceptions'] as List).join(', ')}' : ''}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          trailing: SgIconBtn(
                            icon: Icons.delete_outline_rounded,
                            tooltip: 'Supprimer',
                            tone: SgTone.danger,
                            onPressed: () => _supprimer(int.parse(r['id'].toString())),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(height: 28),
              const SgOverline('Nouvelle indisponibilité'),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _jour,
                decoration: const InputDecoration(labelText: 'Jour'),
                items: [
                  for (var i = 0; i < _jours.length; i++)
                    DropdownMenuItem(value: i, child: Text(_jours[i])),
                ],
                onChanged: (v) => setState(() => _jour = v ?? 0),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: _debut);
                      if (t != null) setState(() => _debut = t);
                    },
                    child: Text('De ${_hhmm(_debut)}'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: _fin);
                      if (t != null) setState(() => _fin = t);
                    },
                    child: Text('À ${_hhmm(_fin)}'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await _choisirDate(_du);
                      if (d != null) setState(() => _du = d);
                    },
                    child: Text('Du ${shortDate(_du)}'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await _choisirDate(_au);
                      if (d != null) setState(() => _au = d);
                    },
                    child: Text('Au ${shortDate(_au)}'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_available_rounded, size: 16),
                    onPressed: () async {
                      final d = await _choisirDate(_du);
                      if (d != null) setState(() => _exceptions.add(d));
                    },
                    label: Text(
                      _exceptions.isEmpty
                          ? 'Ajouter une exception'
                          : 'Exceptions : ${_exceptions.map(shortDate).join(', ')}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _motif,
                decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
              ),
              const SizedBox(height: 12),
              SgButton(
                'Enregistrer l’indisponibilité',
                icon: Icons.add_rounded,
                variant: SgBtnVariant.dark,
                expand: true,
                loading: _envoi,
                onPressed: _ajouter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
