/// Fiche détaillée d'une soutenance : étudiant, créneau, salle, jury et
/// accès aux documents du dossier. Le personnel peut aussi y changer le
/// statut de la soutenance (confirmée, terminée, annulée…) ou la supprimer.
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
              SgBadge(defense.status, tone: sgToneForStatus(defense.status)),
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

/// Statuts possibles d'une soutenance, dans leur ordre logique.
const _statutsSoutenance = ['planifie', 'confirme', 'termine', 'annule'];

/// Carte de gestion d'une soutenance (personnel) : changement de statut
/// et suppression définitive.
class _GestionSoutenance extends StatefulWidget {
  const _GestionSoutenance({required this.defense});

  /// Soutenance gérée.
  final Defense defense;

  @override
  State<_GestionSoutenance> createState() => _GestionSoutenanceState();
}

/// État de la carte : opération en cours.
class _GestionSoutenanceState extends State<_GestionSoutenance> {
  /// Vrai pendant un appel au serveur (boutons désactivés).
  bool _occupe = false;

  /// Service de planification construit à partir de la session.
  PlanningService get _service =>
      PlanningService(context.read<AuthProvider>().api);

  /// Recharge le planning partagé (non bloquant en cas d'erreur).
  Future<void> _rafraichirPlanning() async {
    try {
      await PlanningStore.refresh(_service);
    } catch (_) {
      // Erreur publiée dans PlanningStore.error.
    }
  }

  /// Change le statut puis rouvre la fiche avec le statut à jour.
  Future<void> _changerStatut(String statut) async {
    setState(() => _occupe = true);
    try {
      await _service.updateDefenseStatus(widget.defense.id, statut);
      await _rafraichirPlanning();
      if (!mounted) return;
      SgToast.show(context, 'Soutenance : ${libelleStatut(statut)}.');
      await replacePage(
        context,
        DefenseDetailScreen(defense: widget.defense.copier(status: statut)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _occupe = false);
        SgToast.show(context, e.message, tone: SgTone.danger);
      }
    }
  }

  /// Demande confirmation puis supprime la soutenance.
  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la soutenance'),
        content: Text(
          'Supprimer définitivement la soutenance de '
          '${widget.defense.studentName} ? Son évaluation éventuelle sera '
          'également supprimée.',
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
    setState(() => _occupe = true);
    try {
      await _service.deleteDefense(widget.defense.id);
      await _rafraichirPlanning();
      if (!mounted) return;
      SgToast.show(context, 'Soutenance supprimée.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _occupe = false);
        SgToast.show(context, e.message, tone: SgTone.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SgOverline('Gestion de la soutenance'),
          const SizedBox(height: 12),
          const Text(
            'Statut',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _statutsSoutenance)
                SgChip(
                  label: libelleStatut(s),
                  selected: widget.defense.status == s,
                  onTap: _occupe || widget.defense.status == s
                      ? null
                      : () => _changerStatut(s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SgButton(
            'Supprimer la soutenance',
            icon: Icons.delete_outline_rounded,
            variant: SgBtnVariant.danger,
            dense: true,
            onPressed: _occupe ? null : _supprimer,
          ),
        ],
      ),
    );
  }
}
