import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import 'defense_form_screen.dart';
import 'documents_screen.dart';
import 'planning_screen.dart';

class DefenseDetailScreen extends StatelessWidget {
  const DefenseDetailScreen({super.key, required this.defense});

  final Defense defense;

  List<String> get _membresJury => defense.juryName
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final d = parseDefenseDate(defense.date);

    return SgPage(
      section: AppSection.planning,
      title: 'Détails de la soutenance',
      subtitle: 'Fiche complète : étudiant, créneau, salle et jury.',
      actions: [
        if (Session.peutGerer)
          SgButton('Dupliquer',
              icon: Icons.copy_rounded,
              variant: SgBtnVariant.outline,
              onPressed: () =>
                  _push(context, DefenseFormScreen(initial: defense))),
        SgButton('Planning',
            icon: Icons.calendar_month_outlined,
            variant: SgBtnVariant.outline,
            onPressed: () => _push(context, const PlanningScreen())),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _entete(d),
          const SizedBox(height: 16),
          _infos(d),
          const SizedBox(height: 16),
          _jury(),
          const SizedBox(height: 16),
          _documents(context),
        ],
      ),
    );
  }

  Widget _entete(DateTime? d) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AppTheme.goldLine,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school_rounded,
                    size: 22, color: AppColors.ink),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(defense.studentName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Text(defense.subject,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12.5,
                            height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SgBadge(defense.status,
                  tone: sgToneForStatus(defense.status)),
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

  Widget _infos(DateTime? d) {
    final fiches = <SgKv>[
      SgKv(label: 'Étudiant', value: defense.studentName),
      SgKv(label: 'Sujet', value: defense.subject),
      SgKv(
          label: 'Date',
          value: d == null ? defense.date : shortDate(d)),
      SgKv(
          label: 'Horaires',
          value: '${defense.startTime} – ${defense.endTime}'),
      SgKv(label: 'Salle', value: defense.roomName),
      SgKv(label: 'Statut', value: defense.status),
    ];

    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('INFORMATIONS',
              style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.greyLight)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final parLigne = c.maxWidth >= 640 ? 3 : 2;
              final lignes = <List<SgKv>>[];
              for (var i = 0; i < fiches.length; i += parLigne) {
                lignes.add(fiches.skip(i).take(parLigne).toList());
              }
              return Column(
                children: [
                  for (final ligne in lignes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < ligne.length; i++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                    right: i < ligne.length - 1 ? 10 : 0),
                                child: ligne[i],
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

  Widget _jury() {
    final membres = _membresJury;
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('JURY',
              style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.greyLight)),
          const SizedBox(height: 12),
          if (membres.isEmpty)
            const Text('Aucun jury affecté.',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < membres.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SgAvatar(initials: initiales(membres[i]), size: 26),
                        const SizedBox(width: 8),
                        Text(membres[i],
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        if (i == 0) ...[
                          const SizedBox(width: 7),
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

  Widget _documents(BuildContext context) {
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DOCUMENTS ASSOCIÉS',
              style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.greyLight)),
          const SizedBox(height: 12),
          const Text(
            'Les rapports et versions liés à ce dossier de stage sont centralisés dans la gestion documentaire.',
            style: TextStyle(
                fontSize: 12, color: AppColors.grey, height: 1.5),
          ),
          const SizedBox(height: 12),
          SgButton(
            'Consulter la gestion documentaire',
            icon: Icons.folder_open_rounded,
            variant: SgBtnVariant.outline,
            onPressed: () => _push(context, const DocumentsScreen()),
          ),
        ],
      ),
    );
  }
}