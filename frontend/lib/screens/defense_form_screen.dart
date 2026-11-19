/// Formulaire de création (ou de duplication) d'une soutenance.
///
/// Le formulaire charge les référentiels (dossiers, salles, jurys), aide
/// l'utilisateur en signalant localement les conflits probables, puis
/// soumet la réservation au serveur, seul juge final des conflits (EXG01).
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

/// Écran de formulaire de soutenance.
class DefenseFormScreen extends StatefulWidget {
  /// Crée le formulaire ; [initial] le préremplit (duplication).
  const DefenseFormScreen({super.key, this.initial});

  /// Soutenance servant de modèle, ou `null` pour une création vierge.
  final Defense? initial;

  @override
  State<DefenseFormScreen> createState() => _DefenseFormScreenState();
}

/// État du formulaire : référentiels chargés et valeurs saisies.
class _DefenseFormScreenState extends State<DefenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final PlanningService _service;

  /// Vrai pendant le chargement des référentiels.
  bool _loading = true;

  /// Vrai pendant l'envoi au serveur.
  bool _saving = false;

  /// Erreur de chargement des référentiels.
  String? _error;

  /// Erreur renvoyée par le serveur à l'enregistrement (ex. conflit).
  String? _submitError;

  // Référentiels renvoyés par l'API.
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _juries = [];

  // Valeurs sélectionnées.
  int? _folderId;
  int? _juryId;
  String? _roomName;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;

  /// Vrai si le formulaire duplique une soutenance existante.
  bool get _duplication => widget.initial != null;

  /// Vrai si tous les champs obligatoires sont renseignés.
  bool get _complet =>
      _folderId != null &&
      _juryId != null &&
      _roomName != null &&
      _date != null &&
      _start != null &&
      _end != null;

  @override
  void initState() {
    super.initState();
    _service = PlanningService(context.read<AuthProvider>().api);
    _initialiserChamps();
    _chargerReferences();
  }

  /// Préremplit les champs à partir de la soutenance dupliquée.
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

  /// Convertit une heure `HH:MM` en [TimeOfDay] (ou `null` si invalide).
  TimeOfDay? _toTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Charge en parallèle dossiers, salles et jurys.
  Future<void> _chargerReferences() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resultats = await Future.wait([
        _service.loadFolders(),
        _service.loadRooms(),
        _service.loadJuries(),
      ]);
      if (!mounted) return;
      setState(() {
        _folders = resultats[0];
        // Seules les salles actives sont proposées.
        _rooms = resultats[1].where((r) => r['is_active'] != false).toList();
        _juries = resultats[2];
        // Une valeur préremplie absente des listes ferait échouer le menu
        // déroulant : on l'efface plutôt que de planter.
        if (!_folders.any((f) => _id(f) == _folderId)) _folderId = null;
        if (!_juries.any((j) => _id(j) == _juryId)) _juryId = null;
        if (!_rooms.any((r) => r['name']?.toString() == _roomName)) {
          _roomName = null;
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      _echecChargement(e.message);
    } catch (e) {
      _echecChargement('Impossible de charger les référentiels.');
    }
  }

  /// Publie une erreur de chargement si l'écran est toujours affiché.
  void _echecChargement(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  /// Lit l'identifiant entier d'un objet JSON.
  int? _id(Map<String, dynamic> item) => int.tryParse(item['id']?.toString() ?? '');

  /// Ouvre le sélecteur de date (dates passées interdites).
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // La date initiale doit être ≥ firstDate, sinon le sélecteur plante
    // (cas d'une duplication d'une soutenance passée).
    final initial = _date == null || _date!.isBefore(today) ? today : _date!;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
    );
    if (selected != null) setState(() => _date = selected);
  }

  /// Ouvre le sélecteur d'heure de début ([start]) ou de fin.
  Future<void> _pickTime({required bool start}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime:
          (start ? _start : _end) ??
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

  /// Conflits probables détectés localement avec le planning connu.
  ///
  /// Simple aide à la saisie : le serveur refusera de toute façon une
  /// réservation en conflit.
  List<String> get _conflitsLocaux {
    if (!_complet) return const [];
    final jury = _juries.firstWhere(
      (j) => _id(j) == _juryId,
      orElse: () => const {},
    );
    final candidate = Defense(
      id: -1,
      studentName: '',
      subject: '',
      date: isoDate(_date!),
      startTime: hhmm(_start!),
      endTime: hhmm(_end!),
      roomName: _roomName!,
      juryName: jury['name']?.toString() ?? '',
      status: 'planifie',
    );
    return PlanningStore.findConflicts(candidate);
  }

  /// Valide la saisie puis envoie la réservation au serveur.
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
    final debut = DateTime(
      date.year,
      date.month,
      date.day,
      _start!.hour,
      _start!.minute,
    );
    final fin = DateTime(
      date.year,
      date.month,
      date.day,
      _end!.hour,
      _end!.minute,
    );
    if (!fin.isAfter(debut)) {
      SgToast.show(
        context,
        'L’heure de fin doit être après l’heure de début.',
        tone: SgTone.danger,
      );
      return;
    }

    setState(() {
      _saving = true;
      _submitError = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      await _service.createDefense(
        folderId: _folderId!,
        juryId: _juryId!,
        roomName: _roomName!,
        start: debut,
        end: fin,
      );
      // Le planning partagé est rafraîchi pour tous les écrans.
      try {
        await PlanningStore.refresh(_service, loadCatalog: auth.canManage);
      } catch (_) {
        // Échec non bloquant : l'erreur est publiée dans PlanningStore.error.
      }
      if (!mounted) return;
      SgToast.show(context, 'Soutenance enregistrée.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      // Erreur métier lisible (conflit EXG01, dossier non recevable…).
      if (mounted) setState(() => _submitError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _submitError = 'L’enregistrement a échoué.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Libellé d'un dossier : « entreprise — sujet ».
  String _folderLabel(Map<String, dynamic> folder) {
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
      maxWidth: 960,
      actions: [
        SgButton(
          'Annuler',
          variant: SgBtnVariant.outline,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: _loading
          ? const SgLoading(message: 'Chargement des dossiers, salles et jurys…')
          : _error != null
          ? SgErrorState(
              title: 'Impossible de charger les référentiels',
              message: _error!,
              onRetry: _chargerReferences,
            )
          : _formulaire(),
    );
  }

  /// Corps du formulaire : deux cartes côte à côte sur grand écran.
  Widget _formulaire() {
    final conflits = _conflitsLocaux;
    return SgFormulaire(
      formKey: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final carteDossier = _carteDossier();
              final carteCreneau = _carteCreneau();
              if (c.maxWidth < 720) {
                return Column(
                  children: [
                    carteDossier,
                    const SizedBox(height: 16),
                    carteCreneau,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: carteDossier),
                  const SizedBox(width: 16),
                  Expanded(child: carteCreneau),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          // Aide à la saisie : conflits probables avec le planning connu.
          for (final conflit in conflits) ...[
            SgBanner(message: conflit, tone: SgTone.warning),
            const SizedBox(height: 8),
          ],
          // Refus du serveur (message métier explicite).
          if (_submitError != null) ...[
            SgBanner(
              message: _submitError!,
              tone: SgTone.danger,
              onClose: () => setState(() => _submitError = null),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          SgButton(
            'Enregistrer la soutenance',
            icon: Icons.check_rounded,
            expand: true,
            loading: _saving,
            onPressed: _enregistrer,
          ),
          const SizedBox(height: 10),
          const Text(
            'Tout conflit de salle ou de jury est vérifié et bloqué par le serveur.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.grey),
          ),
        ],
      ),
    );
  }

  /// Carte « Dossier et jury ».
  Widget _carteDossier() {
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SgOverline('Dossier et jury'),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _folderId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Dossier de stage',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
            items: [
              for (final folder in _folders)
                if (_id(folder) != null)
                  DropdownMenuItem<int>(
                    value: _id(folder),
                    child: Text(
                      _folderLabel(folder),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            validator: (value) =>
                value == null ? 'Sélectionnez un dossier.' : null,
            onChanged: (value) => setState(() => _folderId = value),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _juryId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Jury',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
            items: [
              for (final jury in _juries)
                if (_id(jury) != null)
                  DropdownMenuItem<int>(
                    value: _id(jury),
                    child: Text(jury['name']?.toString() ?? ''),
                  ),
            ],
            validator: (value) =>
                value == null ? 'Sélectionnez un jury.' : null,
            onChanged: (value) => setState(() => _juryId = value),
          ),
        ],
      ),
    );
  }

  /// Carte « Créneau et salle ».
  Widget _carteCreneau() {
    return SgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SgOverline('Créneau et salle'),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _roomName,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Salle',
              prefixIcon: Icon(Icons.meeting_room_outlined),
            ),
            items: [
              for (final room in _rooms)
                if (room['name'] != null)
                  DropdownMenuItem<String>(
                    value: room['name'].toString(),
                    child: Text(room['name'].toString()),
                  ),
            ],
            validator: (value) =>
                value == null ? 'Sélectionnez une salle.' : null,
            onChanged: (value) => setState(() => _roomName = value),
          ),
          const SizedBox(height: 14),
          _pickerTile(
            icon: Icons.calendar_month_outlined,
            label: _date == null ? 'Choisir la date' : longDate(_date!),
            filled: _date != null,
            onTap: _pickDate,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _pickerTile(
                  icon: Icons.schedule_rounded,
                  label: _start == null ? 'Début' : hhmm(_start!),
                  filled: _start != null,
                  onTap: () => _pickTime(start: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _pickerTile(
                  icon: Icons.schedule_outlined,
                  label: _end == null ? 'Fin' : hhmm(_end!),
                  filled: _end != null,
                  onTap: () => _pickTime(start: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Champ cliquable ouvrant un sélecteur (date ou heure).
  ///
  /// [filled] distingue visuellement une valeur saisie d'un texte indicatif.
  Widget _pickerTile({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppColors.greyLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: filled ? AppColors.ink : AppColors.grey,
                  fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
