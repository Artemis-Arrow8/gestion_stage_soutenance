import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../services/planning_service.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

class DefenseFormScreen extends StatefulWidget {
  const DefenseFormScreen({super.key, this.initial});

  final Defense? initial;

  @override
  State<DefenseFormScreen> createState() => _DefenseFormScreenState();
}

class _DefenseFormScreenState extends State<DefenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late PlanningService _service;
  bool _initialise = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<dynamic> _folders = [];
  List<dynamic> _rooms = [];
  List<dynamic> _juries = [];
  int? _folderId;
  int? _juryId;
  String? _roomName;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;

  bool get _duplication => widget.initial != null;

  bool get _complet =>
      _folderId != null &&
      _juryId != null &&
      _roomName != null &&
      _date != null &&
      _start != null &&
      _end != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialise) return;
    _initialise = true;
    final auth = context.read<AuthProvider>();
    _service = PlanningService(
      accessToken: auth.accessToken,
      accessTokenProvider: () => auth.accessToken,
      refreshAccessToken: auth.refreshAccessToken,
    );
    _initialiserChamps();
    _chargerReferences();
  }

  void _initialiserChamps() {
    final initial = widget.initial;
    if (initial == null) return;
    _folderId = initial.folderId;
    _juryId = initial.juryId;
    _roomName = initial.roomName;
    _date = parseDefenseDate(initial.date);
    _start = _toTime(initial.startTime);
    _end = _toTime(initial.endTime);
  }

  TimeOfDay? _toTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _chargerReferences() async {
    try {
      final resultats = await Future.wait<dynamic>([
        _service.loadFolders(),
        _service.loadRooms(),
        _service.loadJuries(),
      ]);
      if (!mounted) return;
      setState(() {
        _folders = resultats[0] as List<dynamic>;
        _rooms = resultats[1] as List<dynamic>;
        _juries = resultats[2] as List<dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _pickTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ??
          (start
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 10, minute: 0)),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_complet) {
      SgToast.show(
        context,
        'Sélectionnez un dossier, un jury, une salle et un créneau.',
        tone: SgTone.danger,
      );
      return;
    }
    final date = _date!;
    final start = _start!;
    final end = _end!;
    final debut = DateTime(
      date.year,
      date.month,
      date.day,
      start.hour,
      start.minute,
    );
    final fin = DateTime(
      date.year,
      date.month,
      date.day,
      end.hour,
      end.minute,
    );
    if (!fin.isAfter(debut)) {
      SgToast.show(
        context,
        'L’heure de fin doit être après l’heure de début.',
        tone: SgTone.danger,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.createDefense(
        folderId: _folderId!,
        juryId: _juryId!,
        roomName: _roomName!,
        start: debut,
        end: fin,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      SgToast.show(context, e.toString(), tone: SgTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _folderLabel(Map folder) {
    final company = folder['company_name']?.toString() ?? 'Entreprise';
    final subject = folder['subject']?.toString() ?? 'Sujet non renseigné';
    return '$company — $subject';
  }

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.planning,
      title: _duplication ? 'Dupliquer la soutenance' : 'Nouvelle soutenance',
      subtitle: 'Le serveur valide chaque réservation et rejette les conflits.',
      actions: [
        SgButton(
          'Annuler',
          variant: SgBtnVariant.outline,
          onPressed: () => Navigator.pop(context),
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
              ? SgCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Impossible de charger les référentiels.'),
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 12),
                      SgButton(
                        'Réessayer',
                        icon: Icons.refresh_rounded,
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _chargerReferences();
                        },
                      ),
                    ],
                  ),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SgSectionTitle('DOSSIER ET JURY'),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: _folderId,
                        decoration: const InputDecoration(
                          labelText: 'Dossier de stage',
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                        items: [
                          for (final folder in _folders.whereType<Map>())
                            DropdownMenuItem<int>(
                              value: int.tryParse(
                                folder['id']?.toString() ?? '',
                              ),
                              child: Text(
                                _folderLabel(folder),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        validator: (value) =>
                            value == null ? 'Sélectionnez un dossier.' : null,
                        onChanged: (value) =>
                            setState(() => _folderId = value),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: _juryId,
                        decoration: const InputDecoration(
                          labelText: 'Jury',
                          prefixIcon: Icon(Icons.groups_outlined),
                        ),
                        items: [
                          for (final jury in _juries.whereType<Map>())
                            DropdownMenuItem<int>(
                              value: int.tryParse(
                                jury['id']?.toString() ?? '',
                              ),
                              child: Text(jury['name']?.toString() ?? ''),
                            ),
                        ],
                        validator: (value) =>
                            value == null ? 'Sélectionnez un jury.' : null,
                        onChanged: (value) => setState(() => _juryId = value),
                      ),
                      const SizedBox(height: 16),
                      const SgSectionTitle('CRÉNEAU ET SALLE'),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _roomName,
                        decoration: const InputDecoration(
                          labelText: 'Salle',
                          prefixIcon: Icon(Icons.meeting_room_outlined),
                        ),
                        items: [
                          for (final room in _rooms.whereType<Map>())
                            DropdownMenuItem<String>(
                              value: room['name']?.toString(),
                              child: Text(room['name']?.toString() ?? ''),
                            ),
                        ],
                        validator: (value) =>
                            value == null ? 'Sélectionnez une salle.' : null,
                        onChanged: (value) =>
                            setState(() => _roomName = value),
                      ),
                      const SizedBox(height: 10),
                      _pickerTile(
                        icon: Icons.calendar_month_outlined,
                        label: _date == null
                            ? 'Choisir la date'
                            : shortDate(_date!),
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _pickerTile(
                              icon: Icons.login_outlined,
                              label: _start == null ? 'Début' : hhmm(_start!),
                              onTap: () => _pickTime(start: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _pickerTile(
                              icon: Icons.logout_outlined,
                              label: _end == null ? 'Fin' : hhmm(_end!),
                              onTap: () => _pickTime(start: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SgButton(
                        _saving ? 'Enregistrement…' : 'Enregistrer la soutenance',
                        icon: Icons.check_rounded,
                        expand: true,
                        onPressed: _saving ? null : _enregistrer,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Tout conflit de salle ou de jury est vérifié et bloqué par le serveur.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.grey),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
