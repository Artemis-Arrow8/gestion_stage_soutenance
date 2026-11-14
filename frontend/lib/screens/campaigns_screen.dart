import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/administration.dart';
import '../providers/auth_provider.dart';
import '../services/administration_service.dart';
import '../services/api_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Permet au personnel habilité de créer et d'activer les campagnes académiques.
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key, this.service});

  final AdministrationService? service;

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  late final AdministrationService _service;
  List<CampaignRecord> _campaigns = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final auth = context.read<AuthProvider>();
    _service =
        widget.service ??
        AdministrationService(
          accessToken: auth.accessToken,
          accessTokenProvider: () => auth.accessToken,
          refreshAccessToken: auth.refreshAccessToken,
        );
    _load();
  }

  bool _initialized = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final campaigns = await _service.loadCampaigns();
      campaigns.sort((a, b) {
        final activeOrder = (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0);
        return activeOrder != 0
            ? activeOrder
            : b.academicYear.compareTo(a.academicYear);
      });
      if (!mounted) return;
      setState(() => _campaigns = campaigns);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
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
      setState(() {
        if (campaign == null) {
          _campaigns = [..._campaigns, saved];
        } else {
          _campaigns = _campaigns
              .map((item) => item.id == saved.id ? saved : item)
              .toList();
        }
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
      subtitle:
          'Créez les années académiques et choisissez la campagne active.',
      actions: [
        SgButton(
          'Nouvelle campagne',
          icon: Icons.add_rounded,
          onPressed: _saving ? null : () => _editCampaign(),
        ),
      ],
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          : _error != null
          ? SgEmpty(
              icon: Icons.cloud_off_outlined,
              title: 'Impossible de charger les campagnes',
              message: _error,
              action: SgButton(
                'Réessayer',
                icon: Icons.refresh_rounded,
                onPressed: _load,
              ),
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
          : Column(
              children: [
                for (final campaign in _campaigns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SgCard(
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 22),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  campaign.academicYear,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                SgBadge(
                                  campaign.isActive ? 'Active' : 'Archivée',
                                  tone: campaign.isActive
                                      ? SgTone.success
                                      : SgTone.neutral,
                                ),
                              ],
                            ),
                          ),
                          SgIconBtn(
                            icon: Icons.edit_outlined,
                            tooltip: 'Modifier la campagne',
                            onPressed: _saving
                                ? null
                                : () => _editCampaign(campaign: campaign),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CampaignDraft {
  const _CampaignDraft(this.academicYear, this.isActive);

  final String academicYear;
  final bool isActive;
}

class _CampaignDialog extends StatefulWidget {
  const _CampaignDialog({this.campaign});

  final CampaignRecord? campaign;

  @override
  State<_CampaignDialog> createState() => _CampaignDialogState();
}

class _CampaignDialogState extends State<_CampaignDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _yearController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(
      text: widget.campaign?.academicYear ?? '',
    );
    _isActive = widget.campaign?.isActive ?? true;
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context)
        .pop(_CampaignDraft(_yearController.text.trim(), _isActive));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.campaign == null ? 'Créer une campagne' : 'Modifier la campagne',
      ),
      content: Form(
        key: _formKey,
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
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Saisissez une année académique.'
                    : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Campagne active'),
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
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
