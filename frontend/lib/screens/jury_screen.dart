/// Gestion des jurys de soutenance (ressources `/api/jurys/` et
/// `/api/jury-members/`).
///
/// Chaque jury est présenté sous forme de carte : composition (membres et
/// rôles), état « complet » et nombre de soutenances affectées. Le
/// personnel peut créer un jury, ajouter ou retirer des membres et déclarer
/// la composition complète ; tout est enregistré par l'API.
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
import '../widgets/indisponibilites_sheet.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';

/// Écran des jurys.
class JuryScreen extends StatefulWidget {
  /// Crée l'écran des jurys.
  const JuryScreen({super.key});

  @override
  State<JuryScreen> createState() => _JuryScreenState();
}

/// État de l'écran : jurys chargés et recherche.
class _JuryScreenState extends State<JuryScreen> {
  late final PlanningService _service;
  late final bool _peutGerer;

  /// Jurys renvoyés par l'API.
  List<Jury> _juries = const [];

  /// Vrai pendant le chargement.
  bool _loading = true;

  /// Erreur de chargement éventuelle.
  String? _error;

  /// Texte de recherche (nom de jury ou de membre).
  String _q = '';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _service = PlanningService(auth.api);
    _peutGerer = auth.canManage;
    _charger();
    // Le planning permet de compter les soutenances de chaque jury.
    PlanningStore.ensureLoaded(_service, loadCatalog: _peutGerer);
  }

  /// Charge (ou recharge) les jurys et leurs membres.
  Future<void> _charger() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final juries = await _service.loadJuryRecords();
      if (!mounted) return;
      setState(() {
        _juries = juries;
        _loading = false;
      });
    } on ApiException catch (e) {
      _echec(e.message);
    } catch (_) {
      _echec('Impossible de charger les jurys.');
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

  /// Exécute une écriture [action], affiche [succes] puis recharge.
  ///
  /// Les erreurs de l'API (validation, droits) sont affichées en toast.
  Future<void> _ecrire(Future<void> Function() action, String succes) async {
    try {
      await action();
      if (!mounted) return;
      SgToast.show(context, succes);
      await _charger();
      // Les noms de membres alimentent les filtres du planning.
      try {
        await PlanningStore.refresh(_service, loadCatalog: _peutGerer);
      } catch (_) {
        // Non bloquant : publié dans PlanningStore.error.
      }
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  /// Demande un nom puis crée un nouveau jury.
  Future<void> _creerJury() async {
    final nom = await showDialog<String>(
      context: context,
      builder: (_) => const _JuryNameDialog(),
    );
    if (nom == null) return;
    await _ecrire(() => _service.createJury(nom), 'Jury « $nom » créé.');
  }

  /// Ouvre le formulaire d'ajout d'un membre au [jury].
  Future<void> _ajouterMembre(Jury jury) async {
    final saisie = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _MemberDialog(juryName: jury.name),
    );
    if (saisie == null) return;
    final (nom, role) = saisie;
    await _ecrire(
      () => _service.addJuryMember(juryId: jury.id, name: nom, role: role),
      'Membre ajouté au ${jury.name}.',
    );
  }

  /// Demande confirmation puis retire [membre] de son jury.
  Future<void> _retirerMembre(JuryMember membre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer le membre'),
        content: Text(
          'Retirer « ${membre.name} » du jury ? Un éventuel compte utilisateur '
          'lié à ce membre perdra son accès au planning du jury.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          SgButton(
            'Retirer',
            variant: SgBtnVariant.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _ecrire(
      () => _service.deleteJuryMember(membre.id),
      'Membre retiré du jury.',
    );
  }

  /// Soutenances affectées au [jury] (par identifiant).
  List<Defense> _affectations(Jury jury, List<Defense> all) =>
      all.where((d) => d.juryId == jury.id).toList();

  /// Affiche, dans un panneau inférieur, les soutenances du [jury].
  void _voirAffectations(Jury jury, List<Defense> all) {
    final list = _affectations(jury, all);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Soutenances — ${jury.name}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${list.length} soutenance(s) affectée(s)',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              const SizedBox(height: 14),
              if (list.isEmpty)
                const Text(
                  'Aucune soutenance affectée à ce jury.',
                  style: TextStyle(fontSize: 13, color: AppColors.grey),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.event_rounded,
                            size: 20,
                            color: AppColors.goldDeep,
                          ),
                          title: Text(
                            d.studentName,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          subtitle: Text(
                            '${parseDefenseDate(d.date) == null ? d.date : shortDate(parseDefenseDate(d.date)!)}'
                            ' · ${d.startTime} · ${d.roomName}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            pushPage(context, DefenseDetailScreen(defense: d));
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.jury,
      title: 'Gestion des jurys',
      subtitle: 'Composition des jurys et soutenances qui leur sont affectées.',
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
            'Nouveau jury',
            icon: Icons.group_add_rounded,
            onPressed: _creerJury,
          ),
      ],
      child: _loading
          ? const SgLoading(message: 'Chargement des jurys…')
          : _error != null
          ? SgErrorState(
              title: 'Impossible de charger les jurys',
              message: _error!,
              onRetry: _charger,
            )
          : ValueListenableBuilder<List<Defense>>(
              valueListenable: PlanningStore.defenses,
              builder: (context, all, _) => _contenu(all),
            ),
    );
  }

  /// Barre de recherche puis grille de cartes de jurys.
  Widget _contenu(List<Defense> all) {
    final q = _q.toLowerCase();
    final juries = _juries.where((j) {
      if (q.isEmpty) return true;
      return j.name.toLowerCase().contains(q) ||
          j.members.any((m) => m.name.toLowerCase().contains(q));
    }).toList();
    final nbMembres = _juries.fold<int>(0, (n, j) => n + j.members.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SgCard(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SgSearch(
                width: 260,
                hint: 'Jury ou membre…',
                onChanged: (v) => setState(() => _q = v),
              ),
              SgBadge('${_juries.length} jury(s)', tone: SgTone.gold),
              SgBadge('$nbMembres membre(s)', tone: SgTone.info),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (juries.isEmpty)
          SgEmpty(
            icon: Icons.groups_2_outlined,
            title: _juries.isEmpty ? 'Aucun jury' : 'Aucun résultat',
            message: _juries.isEmpty && _peutGerer
                ? 'Créez un premier jury puis ajoutez-y ses membres.'
                : 'Modifiez votre recherche.',
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              const gap = 14.0;
              final perRow = c.maxWidth >= 900 ? 2 : 1;
              final w = (c.maxWidth - (perRow - 1) * gap) / perRow;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final j in juries)
                    SizedBox(width: w, child: _carteJury(j, all)),
                ],
              );
            },
          ),
      ],
    );
  }

  /// Carte d'un jury : en-tête, membres et actions.
  Widget _carteJury(Jury jury, List<Defense> all) {
    final nbSoutenances = _affectations(jury, all).length;
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups_2_rounded, color: AppColors.goldDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      jury.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${jury.members.length} membre(s) · '
                      '$nbSoutenances soutenance(s)',
                      style: const TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
              SgBadge(
                jury.isComplete ? 'Complet' : 'Incomplet',
                tone: jury.isComplete ? SgTone.success : SgTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          if (jury.members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Aucun membre pour l’instant.',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            )
          else
            for (final m in jury.members)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SgAvatar(initials: initiales(m.name), size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SgBadge(
                      m.roleLabel,
                      tone: m.role == 'president' ? SgTone.gold : SgTone.neutral,
                      dot: false,
                    ),
                    if (_peutGerer) ...[
                      const SizedBox(width: 6),
                      // Indisponibilités récurrentes du membre (STA09).
                      SgIconBtn(
                        icon: Icons.event_busy_rounded,
                        tooltip: 'Indisponibilités',
                        tone: SgTone.info,
                        onPressed: () => ouvrirIndisponibilites(
                          context,
                          service: _service,
                          typeRessource: 'membre',
                          ressource: m.name,
                        ),
                      ),
                      const SizedBox(width: 6),
                      SgIconBtn(
                        icon: Icons.person_remove_outlined,
                        tooltip: 'Retirer du jury',
                        tone: SgTone.danger,
                        onPressed: () => _retirerMembre(m),
                      ),
                    ],
                  ],
                ),
              ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SgButton(
                'Soutenances',
                icon: Icons.event_note_outlined,
                variant: SgBtnVariant.outline,
                dense: true,
                onPressed: () => _voirAffectations(jury, all),
              ),
              if (_peutGerer) ...[
                SgButton(
                  'Ajouter un membre',
                  icon: Icons.person_add_alt_1_rounded,
                  variant: SgBtnVariant.outline,
                  dense: true,
                  onPressed: () => _ajouterMembre(jury),
                ),
                SgButton(
                  jury.isComplete ? 'Marquer incomplet' : 'Marquer complet',
                  icon: jury.isComplete
                      ? Icons.remove_done_rounded
                      : Icons.done_all_rounded,
                  variant: SgBtnVariant.ghost,
                  dense: true,
                  onPressed: () => _ecrire(
                    () => _service.setJuryComplete(
                      jury.id,
                      isComplete: !jury.isComplete,
                    ),
                    'Jury mis à jour.',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Boîte de dialogue de saisie du nom d'un nouveau jury.
class _JuryNameDialog extends StatefulWidget {
  const _JuryNameDialog();

  @override
  State<_JuryNameDialog> createState() => _JuryNameDialogState();
}

/// État de la saisie du nom de jury.
class _JuryNameDialogState extends State<_JuryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  /// Valide et renvoie le nom saisi.
  void _valider() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _nom.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau jury'),
      content: SizedBox(
        width: 380,
        child: SgFormulaire(
          formKey: _formKey,
          child: TextFormField(
            controller: _nom,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nom du jury',
              hintText: 'ex. Jury Informatique A',
              prefixIcon: Icon(Icons.groups_2_outlined),
            ),
            onFieldSubmitted: (_) => _valider(),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        SgButton('Créer', onPressed: _valider),
      ],
    );
  }
}

/// Boîte de dialogue d'ajout d'un membre (nom + rôle).
class _MemberDialog extends StatefulWidget {
  const _MemberDialog({required this.juryName});

  /// Nom du jury, rappelé dans le titre.
  final String juryName;

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

/// État du formulaire de membre.
class _MemberDialogState extends State<_MemberDialog> {
  /// Rôles acceptés par l'API, avec leur libellé.
  static const _roles = {
    'president': 'Président',
    'rapporteur': 'Rapporteur',
    'examinateur': 'Examinateur',
  };

  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  String _role = 'examinateur';

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  /// Valide et renvoie le couple (nom, rôle).
  void _valider() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (_nom.text.trim(), _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ajouter un membre — ${widget.juryName}'),
      content: SizedBox(
        width: 420,
        child: SgFormulaire(
          formKey: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nom,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom et prénom',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 14),
              SgSelect<String>(
                value: _role,
                icon: Icons.badge_outlined,
                items: [
                  for (final e in _roles.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _role = v ?? _role),
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
        SgButton('Ajouter', onPressed: _valider),
      ],
    );
  }
}
