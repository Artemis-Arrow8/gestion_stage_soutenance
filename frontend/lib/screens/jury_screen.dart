import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../services/planning_store.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';

class _Member {
  _Member({
    required this.nom,
    required this.specialite,
    required this.fonction,
    required this.dispos,
  });
  String nom;
  String specialite;
  String fonction;
  String dispos;
}

class JuryScreen extends StatefulWidget {
  const JuryScreen({super.key});

  @override
  State<JuryScreen> createState() => _JuryScreenState();
}

class _JuryScreenState extends State<JuryScreen> {
  static const _specialites = [
    'Génie logiciel', 'Réseaux & systèmes', 'Data science',
    'Sécurité informatique', 'Gestion de projet'
  ];
  static const _fonctions = ['Président', 'Rapporteur', 'Examinateur', 'Membre'];

  late List<_Member> _membres;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _membres = [
      for (var i = 0; i < PlanningStore.juryMembers.length; i++)
        _Member(
          nom: PlanningStore.juryMembers[i],
          specialite: _specialites[i % _specialites.length],
          fonction: _fonctions[i % _fonctions.length],
          dispos: ['Lun–Jeu · 08h–16h', 'Mar–Ven · 09h–17h', 'Lun–Ven · 08h–12h'][i % 3],
        ),
    ];
  }

  List<Defense> _affectations(String nom, List<Defense> all) => all
      .where((d) => d.juryName.toLowerCase().contains(nom.toLowerCase()))
      .toList();

  Future<void> _editer({_Member? membre}) async {
    final res = await showDialog<_Member>(
      context: context,
      builder: (_) => _MemberDialog(
        initial: membre,
        specialites: _specialites,
        fonctions: _fonctions,
      ),
    );
    if (res == null) return;
    setState(() {
      if (membre == null) {
        _membres.add(res);
      } else {
        membre
          ..nom = res.nom
          ..specialite = res.specialite
          ..fonction = res.fonction
          ..dispos = res.dispos;
      }
    });
    if (!mounted) return;
    SgToast.show(
        context, membre == null ? 'Membre ajouté.' : 'Membre mis à jour.');
  }

  void _voirAffectations(_Member m, List<Defense> all) {
    final list = _affectations(m.nom, all);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Affectations — ${m.nom}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${list.length} soutenance(s)',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.grey)),
              const SizedBox(height: 14),
              if (list.isEmpty)
                const Text('Aucune soutenance affectée.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.grey))
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_rounded,
                              size: 18, color: AppColors.gold),
                          title: Text(d.studentName,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${d.date} · ${d.startTime} · ${d.roomName}',
                              style: const TextStyle(fontSize: 11.5)),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              size: 18),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        DefenseDetailScreen(defense: d)));
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
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, all, _) {
        final membres = _membres.where((m) {
          if (_q.isEmpty) return true;
          final v = _q.toLowerCase();
          return m.nom.toLowerCase().contains(v) ||
              m.specialite.toLowerCase().contains(v) ||
              m.fonction.toLowerCase().contains(v);
        }).toList();

        return SgPage(
          section: AppSection.jury,
          title: 'Gestion des jurys',
          subtitle:
              'Membres, spécialités, disponibilités et affectations aux soutenances.',
          actions: [
            if (Session.peutGerer(context))
              SgButton('Ajouter un membre',
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: () => _editer()),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SgCard(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SgSearch(
                        width: 250,
                        hint: 'Nom, spécialité, fonction…',
                        onChanged: (v) => setState(() => _q = v)),
                    SgBadge('${_membres.length} membres', tone: SgTone.gold),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (membres.isEmpty)
                const SgEmpty(
                    icon: Icons.groups_2_outlined,
                    title: 'Aucun membre',
                    message: 'Ajoutez un membre du jury pour commencer.')
              else
                LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth >= 860) {
                      return SgCard(
                        padding: EdgeInsets.zero,
                        child: SgTable(
                          columns: const [
                            SgCol('Membre', flex: 4),
                            SgCol('Spécialité', flex: 3),
                            SgCol('Fonction', flex: 2),
                            SgCol('Disponibilités', flex: 3),
                            SgCol('Soutenances', flex: 2),
                            SgCol('Actions', flex: 2, align: Alignment.centerRight),
                          ],
                          rows: [
                            for (final m in membres)
                              [
                                Row(children: [
                                  SgAvatar(
                                      initials: initiales(m.nom), size: 32),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(m.nom,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                                Text(m.specialite,
                                    style: const TextStyle(
                                        fontSize: 12.5, color: AppColors.grey)),
                                SgBadge(m.fonction, tone: SgTone.neutral),
                                Text(m.dispos,
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.grey)),
                                SgBadge('${_affectations(m.nom, all).length}',
                                    tone: SgTone.info),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    SgIconBtn(
                                        icon: Icons.visibility_outlined,
                                        tooltip: 'Affectations',
                                        tone: SgTone.info,
                                        onPressed: () =>
                                            _voirAffectations(m, all)),
                                    const SizedBox(width: 6),
                                    SgIconBtn(
                                        icon: Icons.edit_outlined,
                                        tooltip: 'Modifier',
                                        tone: SgTone.gold,
                                        onPressed: Session.peutGerer(context)
                                            ? () => _editer(membre: m)
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
                        for (final m in membres)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SgCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    SgAvatar(
                                        initials: initiales(m.nom), size: 38),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(m.nom,
                                              style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 3),
                                          Text('${m.specialite} · ${m.fonction}',
                                              style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: AppColors.grey)),
                                        ],
                                      ),
                                    ),
                                    SgBadge(
                                        '${_affectations(m.nom, all).length}',
                                        tone: SgTone.info),
                                  ]),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    const Icon(Icons.schedule_rounded,
                                        size: 14, color: AppColors.greyLight),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(m.dispos,
                                          style: const TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.grey)),
                                    ),
                                    SgIconBtn(
                                        icon: Icons.visibility_outlined,
                                        tooltip: 'Affectations',
                                        tone: SgTone.info,
                                        onPressed: () =>
                                            _voirAffectations(m, all)),
                                    const SizedBox(width: 6),
                                    SgIconBtn(
                                        icon: Icons.edit_outlined,
                                        tooltip: 'Modifier',
                                        tone: SgTone.gold,
                                        onPressed: Session.peutGerer(context)
                                            ? () => _editer(membre: m)
                                            : null),
                                  ]),
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

class _MemberDialog extends StatefulWidget {
  const _MemberDialog({
    this.initial,
    required this.specialites,
    required this.fonctions,
  });
  final _Member? initial;
  final List<String> specialites;
  final List<String> fonctions;

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nom =
      TextEditingController(text: widget.initial?.nom ?? '');
  late final TextEditingController _dispos =
      TextEditingController(text: widget.initial?.dispos ?? 'Lun–Ven · 08h–16h');
  late String _spec =
      widget.initial?.specialite ?? widget.specialites.first;
  late String _fonc = widget.initial?.fonction ?? widget.fonctions.first;

  @override
  void dispose() {
    _nom.dispose();
    _dispos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null
          ? 'Ajouter un membre du jury'
          : 'Modifier le membre'),
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
                  decoration:
                      const InputDecoration(labelText: 'Nom et prénom'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
                ),
                const SizedBox(height: 12),
                SgSelect<String>(
                  value: _spec,
                  icon: Icons.science_outlined,
                  items: [
                    for (final s in widget.specialites)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() => _spec = v ?? _spec),
                ),
                const SizedBox(height: 12),
                SgSelect<String>(
                  value: _fonc,
                  icon: Icons.badge_outlined,
                  items: [
                    for (final f in widget.fonctions)
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) => setState(() => _fonc = v ?? _fonc),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dispos,
                  decoration: const InputDecoration(
                      labelText: 'Disponibilités (ex. Lun–Jeu · 08h–16h)'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
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
            _Member(
              nom: _nom.text.trim(),
              specialite: _spec,
              fonction: _fonc,
              dispos: _dispos.text.trim(),
            ),
          );
        }),
      ],
    );
  }
}