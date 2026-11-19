/// Administration des comptes utilisateurs (ressource `/api/accounts/`).
///
/// Un administrateur crée les accès, attribue un rôle et relie chaque
/// compte étudiant à une fiche étudiante, ou chaque compte jury à un
/// membre de jury. Les mots de passe sont validés par le serveur.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../models/administration.dart';
import '../providers/auth_provider.dart';
import '../services/administration_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Écran des comptes et rôles.
class AccountsScreen extends StatefulWidget {
  /// Crée l'écran ; [service] est injectable pour les tests.
  const AccountsScreen({super.key, this.service});

  /// Service à utiliser (sinon, construit à partir de la session).
  final AdministrationService? service;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

/// État de l'écran : comptes, référentiels de liaison et recherche.
class _AccountsScreenState extends State<AccountsScreen> {
  late final AdministrationService _service;

  /// Comptes existants.
  List<AccountRecord> _accounts = [];

  /// Fiches étudiantes disponibles pour la liaison.
  List<StudentOption> _students = [];

  /// Membres de jury disponibles pour la liaison.
  List<JuryMemberOption> _juryMembers = [];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Texte de recherche.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ??
        AdministrationService(context.read<AuthProvider>().api);
    _load();
  }

  /// Charge en parallèle comptes, fiches étudiantes et membres de jury.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Requêtes lancées en parallèle ; la première erreur est relancée.
      final results = await Future.wait<List<Object>>([
        _service.loadAccounts(),
        _service.loadStudents(),
        _service.loadJuryMembers(),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = results[0].cast<AccountRecord>();
        _students = results[1].cast<StudentOption>();
        _juryMembers = results[2].cast<JuryMemberOption>();
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Comptes correspondant à la recherche (nom, identifiant, e-mail, rôle).
  List<AccountRecord> get _visibleAccounts {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _accounts;
    return _accounts.where((account) {
      return [
        account.displayName,
        account.username,
        account.email,
        AuthProvider.roleLabel(account.role),
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  /// Ouvre le formulaire de création ([account] null) ou de modification,
  /// puis enregistre la saisie côté serveur.
  Future<void> _editAccount({AccountRecord? account}) async {
    // Un administrateur ne peut ni changer son propre rôle ni se désactiver.
    final currentUserId = int.tryParse(
      context.read<AuthProvider>().user?['id']?.toString() ?? '',
    );
    final draft = await showDialog<_AccountDraft>(
      context: context,
      builder: (_) => _AccountDialog(
        account: account,
        students: _students,
        juryMembers: _juryMembers,
        isCurrentAccount: account?.id == currentUserId,
      ),
    );
    if (draft == null) return;

    setState(() => _saving = true);
    try {
      final saved = account == null
          ? await _service.createAccount(draft.toJson())
          : await _service.updateAccount(account.id, draft.toJson());
      if (!mounted) return;
      setState(() {
        _accounts = account == null
            ? [..._accounts, saved]
            : _accounts
                  .map((item) => item.id == saved.id ? saved : item)
                  .toList();
      });
      SgToast.show(
        context,
        account == null ? 'Compte créé.' : 'Compte mis à jour.',
      );
    } on ApiException catch (error) {
      if (mounted) SgToast.show(context, error.message, tone: SgTone.danger);
    } on FormatException catch (error) {
      if (mounted) SgToast.show(context, error.message, tone: SgTone.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Ouvre le formulaire de fiche étudiante puis l'enregistre.
  Future<void> _createStudentProfile() async {
    final draft = await showDialog<_StudentDraft>(
      context: context,
      builder: (_) => const _StudentDialog(),
    );
    if (draft == null) return;

    setState(() => _saving = true);
    try {
      final student = await _service.createStudent(
        studentNumber: draft.studentNumber,
        fullName: draft.fullName,
        email: draft.email,
      );
      if (!mounted) return;
      setState(() => _students = [..._students, student]);
      SgToast.show(context, 'Fiche étudiant créée.');
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
      section: AppSection.accounts,
      title: 'Comptes et rôles',
      subtitle:
          'Créez les accès, attribuez un rôle et reliez les profils étudiants ou jury.',
      onRefresh: _load,
      actions: [
        SgButton(
          'Fiche étudiant',
          icon: Icons.school_outlined,
          variant: SgBtnVariant.outline,
          onPressed: _saving ? null : _createStudentProfile,
        ),
        SgButton(
          'Nouveau compte',
          icon: Icons.person_add_alt_1_rounded,
          loading: _saving,
          onPressed: () => _editAccount(),
        ),
      ],
      child: _loading
          ? const SgLoading(message: 'Chargement des comptes…')
          : _error != null
          ? SgErrorState(
              title: 'Impossible de charger les comptes',
              message: _error!,
              onRetry: _load,
            )
          : _contenu(),
    );
  }

  /// Recherche puis liste des comptes (tableau ou cartes).
  Widget _contenu() {
    final visible = _visibleAccounts;
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
                width: 340,
                hint: 'Nom, identifiant, e-mail ou rôle…',
                onChanged: (value) => setState(() => _query = value),
              ),
              SgBadge('${_accounts.length} compte(s)', tone: SgTone.gold),
              SgBadge('${_students.length} fiche(s) étudiant', tone: SgTone.info),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          SgEmpty(
            icon: Icons.people_outline_rounded,
            title: _accounts.isEmpty
                ? 'Aucun compte enregistré'
                : 'Aucun compte correspondant',
            message: _accounts.isEmpty
                ? 'Créez un premier compte ou une fiche étudiant.'
                : 'Modifiez la recherche pour afficher d’autres comptes.',
            action: _accounts.isEmpty
                ? SgButton(
                    'Créer un compte',
                    icon: Icons.add_rounded,
                    onPressed: () => _editAccount(),
                  )
                : null,
          )
        else
          LayoutBuilder(
            builder: (context, c) =>
                c.maxWidth >= 860 ? _tableau(visible) : _cartes(visible),
          ),
      ],
    );
  }

  /// Badges décrivant l'état et les liaisons d'un compte.
  List<Widget> _badges(AccountRecord account) => [
    SgBadge(
      account.isActive ? 'Actif' : 'Désactivé',
      tone: account.isActive ? SgTone.success : SgTone.danger,
    ),
    if (account.studentProfile != null)
      SgBadge(
        'Étudiant · ${account.studentProfile!['student_number'] ?? ''}',
        dot: false,
      ),
    if (account.juryProfile != null)
      SgBadge('Jury · ${account.juryProfile!['name'] ?? ''}', dot: false),
  ];

  /// Bouton de modification d'un compte.
  Widget _modifier(AccountRecord account) => SgIconBtn(
    icon: Icons.edit_outlined,
    tooltip: 'Modifier le compte',
    tone: SgTone.info,
    onPressed: _saving ? null : () => _editAccount(account: account),
  );

  /// Affichage en tableau (écran large).
  Widget _tableau(List<AccountRecord> accounts) {
    return SgCard(
      padding: EdgeInsets.zero,
      child: SgTable(
        columns: const [
          SgCol('Utilisateur', flex: 4),
          SgCol('Rôle', flex: 2),
          SgCol('État et liaisons', flex: 4),
          SgCol('', flex: 1, align: Alignment.centerRight),
        ],
        rows: [
          for (final account in accounts)
            [
              Row(
                children: [
                  SgAvatar(
                    initials: initiales(account.displayName),
                    size: 34,
                    tone: SgTone.info,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '@${account.username}'
                          '${account.email.isEmpty ? '' : ' · ${account.email}'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SgBadge(
                AuthProvider.roleLabel(account.role),
                tone: SgTone.info,
                dot: false,
              ),
              Wrap(spacing: 6, runSpacing: 6, children: _badges(account)),
              _modifier(account),
            ],
        ],
      ),
    );
  }

  /// Affichage en cartes (téléphone).
  Widget _cartes(List<AccountRecord> accounts) {
    return Column(
      children: [
        for (final account in accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SgCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SgAvatar(
                    initials: initiales(account.displayName),
                    size: 40,
                    tone: SgTone.info,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${account.username}'
                          '${account.email.isEmpty ? '' : ' · ${account.email}'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            SgBadge(
                              AuthProvider.roleLabel(account.role),
                              tone: SgTone.info,
                              dot: false,
                            ),
                            ..._badges(account),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _modifier(account),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Valeurs saisies dans le formulaire de compte.
class _AccountDraft {
  const _AccountDraft({
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isActive,
    required this.password,
    required this.studentId,
    required this.juryMemberId,
  });

  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final bool isActive;

  /// Mot de passe ; vide = inchangé (en modification).
  final String password;

  /// Fiche étudiante liée (rôle étudiant uniquement).
  final int? studentId;

  /// Membre de jury lié (rôle jury uniquement).
  final int? juryMemberId;

  /// Corps JSON attendu par `/api/accounts/`.
  ///
  /// Le mot de passe n'est envoyé que s'il est renseigné, et chaque
  /// liaison seulement pour le rôle correspondant.
  Map<String, dynamic> toJson() => {
    'username': username,
    'email': email,
    'first_name': firstName,
    'last_name': lastName,
    'role': role,
    'is_active': isActive,
    if (password.isNotEmpty) 'password': password,
    if (role == 'student') 'student_id': studentId,
    if (role == 'jury') 'jury_member_id': juryMemberId,
  };
}

/// Boîte de dialogue de création / modification d'un compte.
class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.account,
    required this.students,
    required this.juryMembers,
    required this.isCurrentAccount,
  });

  /// Compte modifié, ou `null` pour une création.
  final AccountRecord? account;

  /// Fiches étudiantes proposées.
  final List<StudentOption> students;

  /// Membres de jury proposés.
  final List<JuryMemberOption> juryMembers;

  /// Vrai si l'administrateur modifie son propre compte.
  final bool isCurrentAccount;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

/// État du formulaire de compte.
class _AccountDialogState extends State<_AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(
    text: widget.account?.username ?? '',
  );
  late final _email = TextEditingController(text: widget.account?.email ?? '');
  late final _firstName = TextEditingController(
    text: widget.account?.firstName ?? '',
  );
  late final _lastName = TextEditingController(
    text: widget.account?.lastName ?? '',
  );
  final _password = TextEditingController();
  late String _role = widget.account?.role ?? 'responsible';
  late bool _isActive = widget.account?.isActive ?? true;
  late int? _studentId = int.tryParse(
    widget.account?.studentProfile?['id']?.toString() ?? '',
  );
  late int? _juryMemberId = int.tryParse(
    widget.account?.juryProfile?['id']?.toString() ?? '',
  );

  /// Vrai pour masquer le mot de passe saisi.
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Validateur générique de champ obligatoire.
  String? _required(String? value, String label) {
    return value == null || value.trim().isEmpty ? '$label est requis.' : null;
  }

  /// Valide la saisie puis la renvoie à l'écran appelant.
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _AccountDraft(
        username: _username.text.trim(),
        email: _email.text.trim(),
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        role: _role,
        isActive: _isActive,
        password: _password.text,
        studentId: _studentId,
        juryMemberId: _juryMemberId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Une liaison préremplie absente des listes ferait échouer le menu.
    final studentValue = widget.students.any((s) => s.id == _studentId)
        ? _studentId
        : null;
    final juryValue = widget.juryMembers.any((m) => m.id == _juryMemberId)
        ? _juryMemberId
        : null;

    return AlertDialog(
      title: Text(
        widget.account == null ? 'Créer un compte' : 'Modifier le compte',
      ),
      content: SizedBox(
        width: 500,
        child: SgFormulaire(
          formKey: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SgOverline('Identité'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Identifiant de connexion',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: (value) => _required(value, 'L’identifiant'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstName,
                        decoration: const InputDecoration(labelText: 'Prénom'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastName,
                        decoration: const InputDecoration(labelText: 'Nom'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return value.contains('@') ? null : 'Adresse e-mail invalide.';
                  },
                ),
                const SizedBox(height: 18),
                const SgOverline('Rôle et liaison'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Rôle',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: [
                    for (final role in const [
                      'admin',
                      'responsible',
                      'supervisor',
                      'student',
                      'jury',
                    ])
                      DropdownMenuItem(
                        value: role,
                        child: Text(AuthProvider.roleLabel(role)),
                      ),
                  ],
                  onChanged: widget.isCurrentAccount
                      ? null
                      : (value) {
                          if (value != null) setState(() => _role = value);
                        },
                ),
                if (widget.isCurrentAccount)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Votre rôle ne peut pas être modifié depuis votre propre compte.',
                      style: TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                  ),
                if (_role == 'student') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: studentValue,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Fiche étudiant associée',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                    items: [
                      for (final student in widget.students)
                        DropdownMenuItem(
                          value: student.id,
                          child: Text(
                            student.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    validator: (value) => value == null
                        ? 'Créez ou sélectionnez une fiche étudiant.'
                        : null,
                    onChanged: (value) => setState(() => _studentId = value),
                  ),
                ],
                if (_role == 'jury') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: juryValue,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Membre du jury associé',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    items: [
                      for (final member in widget.juryMembers)
                        DropdownMenuItem(
                          value: member.id,
                          child: Text(
                            member.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    validator: (value) => value == null
                        ? 'Sélectionnez un membre de jury existant.'
                        : null,
                    onChanged: (value) => setState(() => _juryMemberId = value),
                  ),
                ],
                const SizedBox(height: 18),
                const SgOverline('Sécurité'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: widget.account == null
                        ? 'Mot de passe initial'
                        : 'Nouveau mot de passe (facultatif)',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Afficher' : 'Masquer',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (value) {
                    if (widget.account == null &&
                        (value == null || value.isEmpty)) {
                      return 'Le mot de passe initial est requis.';
                    }
                    // Contrôle minimal ; le serveur applique ses validateurs.
                    if (value != null && value.isNotEmpty && value.length < 8) {
                      return 'Utilisez au moins 8 caractères.';
                    }
                    return null;
                  },
                ),
                if (widget.account != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Compte actif'),
                    subtitle: const Text(
                      'Un compte désactivé ne peut plus se connecter.',
                    ),
                    value: _isActive,
                    onChanged: widget.isCurrentAccount
                        ? null
                        : (value) => setState(() => _isActive = value),
                  ),
              ],
            ),
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

/// Valeurs saisies dans le formulaire de fiche étudiante.
class _StudentDraft {
  const _StudentDraft(this.studentNumber, this.fullName, this.email);

  final String studentNumber;
  final String fullName;
  final String email;
}

/// Boîte de dialogue de création d'une fiche étudiante.
class _StudentDialog extends StatefulWidget {
  const _StudentDialog();

  @override
  State<_StudentDialog> createState() => _StudentDialogState();
}

/// État du formulaire de fiche étudiante.
class _StudentDialogState extends State<_StudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Valide la saisie puis la renvoie à l'écran appelant.
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _StudentDraft(_number.text.trim(), _name.text.trim(), _email.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer une fiche étudiant'),
      content: SizedBox(
        width: 420,
        child: SgFormulaire(
          formKey: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Matricule',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le matricule est requis.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le nom complet est requis.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) => value == null || !value.contains('@')
                    ? 'Saisissez une adresse e-mail valide.'
                    : null,
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
        SgButton('Créer la fiche', onPressed: _save),
      ],
    );
  }
}
