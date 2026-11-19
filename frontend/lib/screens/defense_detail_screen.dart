/// Fiche détaillée d'une soutenance : étudiant, créneau, salle, jury et
/// accès aux documents du dossier. Le personnel y fait évoluer la
/// soutenance selon son cycle de vie (confirmer, reporter, marquer comme
/// tenue, annuler) et consulte ses convocations par version du planning.
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
import 'defense_form_screen.dart';

/// Écran de détail d'une soutenance.
class DefenseDetailScreen extends StatelessWidget {
  /// Crée la fiche de [defense].
  const DefenseDetailScreen({super.key, required this.defense});

  /// Soutenance affichée.
  final Defense defense;

  /// Membres du jury extraits du nom de jury (« A, B, C »).
  List<String> get _membresJury => defense.juryName
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final d = parseDefenseDate(defense.date);
    final auth = context.read<AuthProvider>();

    return SgPage(
      section: AppSection.planning,
      title: 'Détails de la soutenance',
      subtitle: 'Fiche complète : étudiant, créneau, salle et jury.',
      actions: [
        // Dupliquer = ouvrir le formulaire prérempli avec cette soutenance.
        if (auth.canManage)
          SgButton(
            'Dupliquer',
            icon: Icons.copy_rounded,
            variant: SgBtnVariant.outline,
            onPressed: () =>
                pushPage(context, DefenseFormScreen(initial: defense)),
          ),
        SgButton(
          'Retour au planning',
          icon: Icons.calendar_month_outlined,
          variant: SgBtnVariant.outline,
          onPressed: () => navigateToSection(context, AppSection.planning),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _entete(d),
          const SizedBox(height: 16),
          _infos(d),
          const SizedBox(height: 16),
          _jury(),
          // Gestion réservée au personnel : statut et suppression.
          if (auth.canManage) ...[
            const SizedBox(height: 16),
            _GestionSoutenance(defense: defense),
          ],
          // Le jury n'a pas accès à la gestion documentaire.
          if (auth.role != 'jury') ...[
            const SizedBox(height: 16),
            _documents(context),
          ],
        ],
      ),
    );
  }

  /// En-tête sombre : étudiant, sujet, statut, date et horaires.
  Widget _entete(DateTime? d) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.inkGradient,
        borderRadius: BorderRadius.circular(AppTheme.radius + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppTheme.goldLine,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  size: 23,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      defense.studentName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      defense.subject,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SgStatusBadge(defense.status),
              SgBadge(
                d == null ? 'Date invalide' : shortDate(d),
                tone: SgTone.gold,
                icon: Icons.calendar_month_rounded,
                dot: false,
              ),
              SgBadge(
                '${defense.startTime} – ${defense.endTime}',
                tone: SgTone.info,
                icon: Icons.schedule_rounded,
                dot: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Carte des informations clés, disposées en grille adaptative.
  Widget _infos(DateTime? d) {
    final fiches = <SgKv>[
      SgKv(label: 'Étudiant', value: defense.studentName),
      SgKv(label: 'Sujet', value: defense.subject),
      SgKv(label: 'Date', value: d == null ? defense.date : longDate(d)),
      SgKv(
        label: 'Horaires',
        value: '${defense.startTime} – ${defense.endTime}',
      ),
      SgKv(label: 'Salle', value: defense.roomName),
      SgKv(label: 'Statut', value: libelleStatut(defense.status)),
    ];

    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SgOverline('Informations'),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              // 3 colonnes sur grand écran, 2 sinon.
              final parLigne = c.maxWidth >= 640 ? 3 : 2;
              final lignes = <List<SgKv>>[];
              for (var i = 0; i < fiches.length; i += parLigne) {
                lignes.add(fiches.skip(i).take(parLigne).toList());
              }
              return Column(
                children: [
                  for (final ligne in lignes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < parLigne; i++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: i < parLigne - 1 ? 12 : 0,
                                ),
                                // Cellule vide pour aligner la dernière ligne.
                                child: i < ligne.length
                                    ? ligne[i]
                                    : const SizedBox.shrink(),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Carte de composition du jury (le premier membre préside).
  Widget _jury() {
    final membres = _membresJury;
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SgOverline('Jury'),
          const SizedBox(height: 14),
          if (membres.isEmpty)
            const Text(
              'Aucun jury affecté.',
              style: TextStyle(fontSize: 13, color: AppColors.grey),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < membres.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SgAvatar(initials: initiales(membres[i]), size: 28),
                        const SizedBox(width: 9),
                        Text(
                          membres[i],
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (i == 0) ...[
                          const SizedBox(width: 8),
                          const SgBadge('Président', tone: SgTone.gold),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// Carte de renvoi vers la gestion documentaire du dossier.
  Widget _documents(BuildContext context) {
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SgOverline('Documents associés'),
          const SizedBox(height: 12),
          const Text(
            'Les rapports et versions liés à ce dossier de stage sont '
            'centralisés dans la gestion documentaire.',
            style: TextStyle(fontSize: 13, color: AppColors.grey, height: 1.5),
          ),
          const SizedBox(height: 14),
          SgButton(
            'Consulter la gestion documentaire',
            icon: Icons.folder_open_rounded,
            variant: SgBtnVariant.outline,
            onPressed: () => navigateToSection(context, AppSection.documents),
          ),
        ],
      ),
    );
  }
}

/// Carte de gestion d'une soutenance (personnel) selon son cycle de vie
/// (F04, F05) : le statut ne se choisit pas librement, il évolue par des
/// actions contrôlées par le serveur.
///
/// * proposée : confirmer (dossier recevable et jury complet exigés) ou
///   supprimer ;
/// * confirmée : en attente de publication (bouton « Publier le planning »
///   de l'écran Planning) ;
/// * publiée : reporter (nouvelle version du planning et nouvelles
///   convocations), marquer comme tenue ou annuler ;
/// * tenue / annulée : plus aucune action.
///
/// La liste des convocations montre les versions successives : une
/// convocation remplacée par un report reste visible (STA07).
class _GestionSoutenance extends StatefulWidget {
  const _GestionSoutenance({required this.defense});

  /// Soutenance gérée.
  final Defense defense;

  @override
  State<_GestionSoutenance> createState() => _GestionSoutenanceState();
}

/// État de la carte : opération en cours et convocations chargées.
class _GestionSoutenanceState extends State<_GestionSoutenance> {
  /// Vrai pendant un appel au serveur (boutons désactivés).
  bool _occupe = false;

  /// Convocations de la soutenance (toutes versions).
  late Future<List<Map<String, dynamic>>> _convocations;

  /// Service de planification construit à partir de la session.
  PlanningService get _service =>
      PlanningService(context.read<AuthProvider>().api);

  @override
  void initState() {
    super.initState();
    _convocations = _service.convocations(soutenance: widget.defense.id);
  }

  /// Exécute une action, rafraîchit le planning et rouvre la fiche à jour.
  Future<void> _executer(
    Future<void> Function() action,
    String succes, {
    bool fermer = false,
  }) async {
    setState(() => _occupe = true);
    try {
      await action();
      try {
        await PlanningStore.refresh(_service);
      } catch (_) {
        // Erreur publiée dans PlanningStore.error.
      }
      if (!mounted) return;
      SgToast.show(context, succes);
      if (fermer) {
        Navigator.of(context).pop();
        return;
      }
      // Fiche rouverte avec la version à jour issue du planning rechargé.
      final ajour = PlanningStore.defenses.value.firstWhere(
        (d) => d.id == widget.defense.id,
        orElse: () => widget.defense,
      );
      await replacePage(context, DefenseDetailScreen(defense: ajour));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _occupe = false);
        SgToast.show(context, e.message, tone: SgTone.danger);
      }
    }
  }

  /// Demande un motif (annulation) ; null si l'utilisateur renonce.
  Future<String?> _demanderMotif(String titre) {
    final controleur = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre),
        content: TextField(
          controller: controleur,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Motif'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Retour'),
          ),
          SgButton(
            'Valider',
            onPressed: () => Navigator.pop(ctx, controleur.text.trim()),
          ),
        ],
      ),
    );
  }

  /// Annule la soutenance après confirmation et motif.
  Future<void> _annuler() async {
    final motif = await _demanderMotif('Annuler la soutenance');
    if (motif == null || !mounted) return;
    await _executer(
      () => _service.annuler(widget.defense.id, motif: motif),
      'Soutenance annulée : salle et jury libérés.',
    );
  }

  /// Ouvre la boîte de report puis publie une nouvelle version.
  Future<void> _reporter() async {
    final saisie = await showDialog<_Report>(
      context: context,
      builder: (_) => _ReportDialog(defense: widget.defense),
    );
    if (saisie == null || !mounted) return;
    // Une clé par action : une relance après coupure ne publie pas deux fois.
    final cle = ApiService.nouvelleCleIdempotence();
    await _executer(
      () => _service.reporter(
        widget.defense.id,
        debut: saisie.debut,
        fin: saisie.fin,
        motif: saisie.motif,
        cle: cle,
      ),
      'Soutenance reportée : nouvelle version du planning publiée.',
    );
  }

  /// Demande confirmation puis supprime une soutenance non publiée.
  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la soutenance'),
        content: Text(
          'Supprimer définitivement la soutenance proposée de '
          '${widget.defense.studentName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
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
    await _executer(
      () => _service.deleteDefense(widget.defense.id),
      'Soutenance supprimée.',
      fermer: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final statut = widget.defense.status;
    final explication = switch (statut) {
      'planifie' =>
        'Proposée : la confirmation exige un dossier recevable et un jury complet.',
      'confirme' =>
        'Confirmée : elle sera publiée avec le planning (écran Planning, '
            '« Publier le planning »).',
      'publie' =>
        'Publiée (version ${widget.defense.versionPubliee ?? '?'}) : les '
            'participants sont convoqués. Un changement passe par un report.',
      'termine' => 'Tenue : la soutenance a eu lieu.',
      'annule' => 'Annulée : salle et jury sont libérés.',
      _ => 'Statut : ${libelleStatut(statut)}.',
    };
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SgOverline('Gestion de la soutenance'),
          const SizedBox(height: 10),
          Text(
            explication,
            style: const TextStyle(fontSize: 13, color: AppColors.grey, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (statut == 'planifie')
                SgButton(
                  'Confirmer',
                  icon: Icons.check_circle_outline_rounded,
                  variant: SgBtnVariant.dark,
                  dense: true,
                  onPressed: _occupe
                      ? null
                      : () => _executer(
                          () => _service.confirmer(widget.defense.id),
                          'Soutenance confirmée.',
                        ),
                ),
              if (statut == 'publie') ...[
                SgButton(
                  'Reporter',
                  icon: Icons.event_repeat_rounded,
                  variant: SgBtnVariant.dark,
                  dense: true,
                  onPressed: _occupe ? null : _reporter,
                ),
                SgButton(
                  'Marquer comme tenue',
                  icon: Icons.task_alt_rounded,
                  variant: SgBtnVariant.outline,
                  dense: true,
                  onPressed: _occupe
                      ? null
                      : () => _executer(
                          () => _service.marquerTenue(widget.defense.id),
                          'Soutenance marquée comme tenue.',
                        ),
                ),
              ],
              if (const {'planifie', 'confirme', 'publie', 'reporte'}.contains(statut))
                SgButton(
                  'Annuler la soutenance',
                  icon: Icons.event_busy_rounded,
                  variant: SgBtnVariant.outline,
                  dense: true,
                  onPressed: _occupe ? null : _annuler,
                ),
              if (statut == 'planifie')
                SgButton(
                  'Supprimer',
                  icon: Icons.delete_outline_rounded,
                  variant: SgBtnVariant.danger,
                  dense: true,
                  onPressed: _occupe ? null : _supprimer,
                ),
            ],
          ),
          const SizedBox(height: 18),
          const SgOverline('Convocations'),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _convocations,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SgLoading();
              }
              final liste = snapshot.data ?? const [];
              if (liste.isEmpty) {
                return const Text(
                  'Aucune convocation : la soutenance n’a pas encore été publiée.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                );
              }
              return Column(
                children: [
                  for (final c in liste)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SgBadge('v${c['version']}', tone: SgTone.gold, dot: false),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${c['destinataire']} · ${c['role_destinataire']}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          SgStatusBadge(c['statut']?.toString() ?? ''),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Saisie d'un report : nouveau créneau et motif.
class _Report {
  const _Report(this.debut, this.fin, this.motif);

  /// Début et fin du nouveau créneau (heure locale).
  final DateTime debut;
  final DateTime fin;

  /// Motif du report (obligatoire).
  final String motif;
}

/// Boîte de dialogue de report : date, heure de début, durée conservée.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.defense});

  /// Soutenance reportée (sa durée est conservée).
  final Defense defense;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

/// État de la boîte de report.
class _ReportDialogState extends State<_ReportDialog> {
  late DateTime _jour;
  late TimeOfDay _heure;
  final TextEditingController _motif = TextEditingController();

  /// Durée actuelle de la soutenance, conservée par le report.
  late Duration _duree;

  @override
  void initState() {
    super.initState();
    _jour = parseDefenseDate(widget.defense.date) ?? DateTime.now();
    TimeOfDay lire(String hhmm) {
      final p = hhmm.split(':');
      return TimeOfDay(
        hour: int.tryParse(p.first) ?? 9,
        minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
      );
    }

    _heure = lire(widget.defense.startTime);
    final fin = lire(widget.defense.endTime);
    final minutes = (fin.hour * 60 + fin.minute) - (_heure.hour * 60 + _heure.minute);
    _duree = Duration(minutes: minutes > 0 ? minutes : 60);
  }

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reporter la soutenance'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Une nouvelle version du planning sera publiée ; les anciennes '
              'convocations resteront visibles, marquées « remplacées ».',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.4),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text('Date : ${shortDate(_jour)}'),
              onPressed: () async {
                final choix = await showDatePicker(
                  context: context,
                  initialDate: _jour,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (choix != null) setState(() => _jour = choix);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(
                'Début : ${_heure.format(context)} '
                '(durée ${_duree.inMinutes} min)',
              ),
              onPressed: () async {
                final choix = await showTimePicker(context: context, initialTime: _heure);
                if (choix != null) setState(() => _heure = choix);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motif,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Motif du report (obligatoire)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
        SgButton(
          'Reporter et publier',
          onPressed: () {
            final motif = _motif.text.trim();
            if (motif.isEmpty) {
              SgToast.show(context, 'Le motif est obligatoire.', tone: SgTone.danger);
              return;
            }
            final debut = DateTime(
              _jour.year, _jour.month, _jour.day, _heure.hour, _heure.minute,
            );
            Navigator.pop(context, _Report(debut, debut.add(_duree), motif));
          },
        ),
      ],
    );
  }
}
