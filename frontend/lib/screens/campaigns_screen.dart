/// Gestion des campagnes académiques (ressource `/api/campaigns/`).
///
/// Le personnel habilité crée les années académiques et choisit la
/// campagne active ; les dossiers de stage sont rattachés à une campagne.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../models/administration.dart';
import '../providers/auth_provider.dart';
import '../services/administration_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Écran des campagnes.
class CampaignsScreen extends StatefulWidget {
  /// Crée l'écran ; [service] est injectable pour les tests.
  const CampaignsScreen({super.key, this.service});

  /// Service à utiliser (sinon, construit à partir de la session).
  final AdministrationService? service;

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

/// État de l'écran : liste des campagnes et indicateurs d'activité.
class _CampaignsScreenState extends State<CampaignsScreen> {
  late final AdministrationService _service;

  /// Campagnes affichées (actives en premier).
  List<CampaignRecord> _campaigns = [];

  /// Vrai pendant le chargement initial.
  bool _loading = true;

  /// Vrai pendant un enregistrement.
  bool _saving = false;

  /// Erreur de chargement éventuelle.
  String? _error;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        AdministrationService(context.read<AuthProvider>().api);
    _load();
  }

  /// Trie les campagnes : actives d'abord, puis par année décroissante.
  List<CampaignRecord> _trier(List<CampaignRecord> campaigns) {
    return [...campaigns]..sort((a, b) {
      final activeOrder = (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0);
      return activeOrder != 0
          ? activeOrder
          : b.academicYear.compareTo(a.academicYear);
    });
  }

  /// Charge (ou recharge) les campagnes depuis l'API.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final campaigns = await _service.loadCampaigns();
      if (!mounted) return;
      setState(() => _campaigns = _trier(campaigns));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ouvre le formulaire de création ([campaign] null) ou de modification,
  /// puis enregistre la saisie côté serveur.
  /// Importe des étudiants (CSV) dans [campaign] : aperçu sans écriture,
  /// puis import confirmé. Réimporter le même fichier ne crée aucun doublon.
  Future<void> _importer(CampaignRecord campaign) async {
    final fichier = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (fichier == null || !mounted) return;
    final String csv;
    try {
      csv = utf8.decode(await fichier.readAsBytes());
    } on FormatException {
      if (mounted) {
        SgToast.show(context, 'Le fichier doit être encodé en UTF-8.', tone: SgTone.danger);
      }
      return;
    }
    try {
      final apercu = await _service.importerEtudiants(
        campagne: campaign.id,
        csv: csv,
        simulation: true,
      );
      if (!mounted) return;
      final confirme = await showDialog<bool>(
        context: context,
        builder: (_) => _RapportImport(rapport: apercu, apercu: true),
      );
      if (confirme != true || !mounted) return;
      final rapport = await _service.importerEtudiants(
        campagne: campaign.id,
        csv: csv,
        simulation: false,
        cle: ApiService.nouvelleCleIdempotence(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _RapportImport(rapport: rapport, apercu: false),
      );
    } on ApiException catch (e) {
      if (mounted) SgToast.show(context, e.message, tone: SgTone.danger);
    }
  }

  Future<void> _editCampaign({CampaignRecord? campaign}) async {
    final draft = await showDialog<_CampaignDraft>(
      context: context,
      builder: (_) => _CampaignDialog(campaign: campaign),
    );
    if (draft == null) return;

    setState(() => _saving = true);
    try {
      final saved = campaign == null
          ? await _service.createCampaign(
              academicYear: draft.academicYear,
              isActive: draft.isActive,
            )
          : await _service.updateCampaign(
              campaign.id,
              academicYear: draft.academicYear,
              isActive: draft.isActive,
            );
      if (!mounted) return;
      SgToast.show(
        context,
        campaign == null ? 'Campagne créée.' : 'Campagne mise à jour.',
      );
      // Mise à jour locale sans recharger toute la liste.
      setState(() {
        _campaigns = _trier(
          campaign == null
              ? [..._campaigns, saved]
              : _campaigns
                    .map((item) => item.id == saved.id ? saved : item)
                    .toList(),
        );
      });
    } on ApiException catch (error) {
      if (mounted) SgToast.show(context, error.message, tone: SgTone.danger);
    } on FormatException catch (error) {
      if (mounted) SgToast.show(context, error.message, tone: SgTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.campaigns,
      title: 'Campagnes de stage',
      subtitle: 'Créez les années académiques et choisissez la campagne active.',
      onRefresh: _load,
      actions: [
        SgButton(
          'Nouvelle campagne',
          icon: Icons.add_rounded,
          loading: _saving,
          onPressed: () => _editCampaign(),
        ),
      ],
      child: _loading
          ? const SgLoading(message: 'Chargement des campagnes…')
          : _error != null
          ? SgErrorState(
              title: 'Impossible de charger les campagnes',
              message: _error!,
              onRetry: _load,
            )
          : _campaigns.isEmpty
          ? SgEmpty(
              icon: Icons.calendar_month_outlined,
              title: 'Aucune campagne enregistrée',
              message:
                  'Créez une campagne pour ouvrir une nouvelle année de stage.',
              action: SgButton(
                'Créer une campagne',
                icon: Icons.add_rounded,
                onPressed: () => _editCampaign(),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                // Grille : 3 cartes par ligne sur grand écran.
                const gap = 14.0;
                final perRow = c.maxWidth >= 960
                    ? 3
                    : (c.maxWidth >= 600 ? 2 : 1);
                final w = (c.maxWidth - (perRow - 1) * gap) / perRow;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final campaign in _campaigns)
                      SizedBox(width: w, child: _carte(campaign)),
                  ],
                );
              },
            ),
    );
  }

  /// Carte d'une campagne : année, état et bouton de modification.
  Widget _carte(CampaignRecord campaign) {
    return SgCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: campaign.isActive
                  ? AppColors.successBg
                  : AppColors.neutralBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              color: campaign.isActive ? AppColors.success : AppColors.grey,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  campaign.academicYear,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 7),
                SgBadge(
                  campaign.isActive ? 'Active' : 'Archivée',
                  tone: campaign.isActive ? SgTone.success : SgTone.neutral,
                ),
              ],
            ),
          ),
          SgIconBtn(
            icon: Icons.group_add_outlined,
            tooltip: 'Importer des étudiants (CSV)',
            tone: SgTone.gold,
            onPressed: _saving ? null : () => _importer(campaign),
          ),
          const SizedBox(width: 6),
          SgIconBtn(
            icon: Icons.edit_outlined,
            tooltip: 'Modifier la campagne',
            tone: SgTone.info,
            onPressed: _saving
                ? null
                : () => _editCampaign(campaign: campaign),
          ),
        ],
      ),
    );
  }
}

/// Rapport d'import (aperçu ou résultat définitif).
class _RapportImport extends StatelessWidget {
  const _RapportImport({required this.rapport, required this.apercu});

  /// Rapport renvoyé par le serveur.
  final Map<String, dynamic> rapport;

  /// Vrai pour l'aperçu (bouton « Importer ») ; faux pour le résultat.
  final bool apercu;

  @override
  Widget build(BuildContext context) {
    final erreurs = (rapport['erreurs'] as List?) ?? const [];
    Widget ligne(String libelle, Object? valeur) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(libelle, style: const TextStyle(fontSize: 13))),
          Text('$valeur', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return AlertDialog(
      title: Text(apercu ? 'Aperçu de l’import' : 'Import terminé'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (apercu)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Rien n’est encore enregistré. Les étudiants déjà connus ne '
                    'sont ni recréés ni modifiés.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                  ),
                ),
              ligne('Étudiants créés', rapport['etudiants_crees']),
              ligne('Étudiants déjà connus', rapport['etudiants_existants']),
              ligne('Dossiers créés (brouillon)', rapport['dossiers_crees']),
              ligne('Dossiers déjà existants', rapport['dossiers_existants']),
              if (erreurs.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '${erreurs.length} ligne(s) en erreur (non importées) :',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
                ),
                for (final e in erreurs)
                  Text(
                    'Ligne ${(e as Map)['ligne']} : ${e['erreur']}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(apercu ? 'Annuler' : 'Fermer'),
        ),
        if (apercu) SgButton('Importer', onPressed: () => Navigator.pop(context, true)),
      ],
    );
  }
}

/// Valeurs saisies dans le formulaire de campagne.
class _CampaignDraft {
  const _CampaignDraft(this.academicYear, this.isActive);

  /// Année académique saisie (ex. « 2026-2027 »).
  final String academicYear;

  /// Campagne active ou archivée.
  final bool isActive;
}

/// Boîte de dialogue de création / modification d'une campagne.
class _CampaignDialog extends StatefulWidget {
  const _CampaignDialog({this.campaign});

  /// Campagne modifiée, ou `null` pour une création.
  final CampaignRecord? campaign;

  @override
  State<_CampaignDialog> createState() => _CampaignDialogState();
}

/// État du formulaire de campagne.
class _CampaignDialogState extends State<_CampaignDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _yearController = TextEditingController(
    text: widget.campaign?.academicYear ?? '',
  );
  late bool _isActive = widget.campaign?.isActive ?? true;

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  /// Valide la saisie puis la renvoie à l'écran appelant.
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(
      context,
    ).pop(_CampaignDraft(_yearController.text.trim(), _isActive));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.campaign == null ? 'Créer une campagne' : 'Modifier la campagne',
      ),
      content: SgFormulaire(
        formKey: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _yearController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Année académique',
                  hintText: '2026-2027',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                onFieldSubmitted: (_) => _save(),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Saisissez une année académique.'
                    : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Campagne active'),
                subtitle: const Text(
                  'Les nouveaux dossiers sont rattachés à la campagne active.',
                ),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        SgButton('Enregistrer', onPressed: _save),
      ],
    );
  }
}
