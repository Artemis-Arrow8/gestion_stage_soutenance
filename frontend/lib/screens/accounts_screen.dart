import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/administration.dart';
import '../providers/auth_provider.dart';
import '../services/administration_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Gère les comptes, leurs rôles et les profils requis par l'API.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, this.service});

  final AdministrationService? service;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late final AdministrationService _service;
  List<AccountRecord> _accounts = [];
  List<StudentOption> _students = [];
  List<JuryMemberOption> _juryMembers = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _query = '';

  bool _initialized = false;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await _service.loadAccounts();
      final students = await _service.loadStudents();
      final juryMembers = await _service.loadJuryMembers();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _students = students;
        _juryMembers = juryMembers;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AccountRecord> get _visibleAccounts {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _accounts;
    return _accounts.where((account) {
      return [
        account.displayName,
        account.username,
        account.email,
        _roleLabel(account.role),
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _editAccount({AccountRecord? account}) async {
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
        if (account == null) {
          _accounts = [..._accounts, saved];
        } else {
          _accounts = _accounts
              .map((item) => item.id == saved.id ? saved : item)
              .toList();
        }
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
    final visible = _visibleAccounts;
    return SgPage(
      section: AppSection.accounts,
      title: 'Comptes et rôles',
      subtitle: 'Créez les accès, attribuez un rôle et reliez les profils étudiants ou jury.',
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
          onPressed: _saving ? null : () => _editAccount(),
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
              title: 'Impossible de charger les comptes',
              message: _error,
              action: SgButton(
                'Réessayer',
                icon: Icons.refresh_rounded,
                onPressed: _load,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SgCard(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText:
                          'Rechercher par nom, identifiant, e-mail ou rôle',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
                  Column(
                    children: [
                      for (final account in visible)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SgCard(
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.neutralBg,
                                  child: Text(
                                    _initials(account.displayName),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          SgBadge(
                                            _roleLabel(account.role),
                                            tone: SgTone.info,
                                          ),
                                          SgBadge(
                                            account.isActive
                                                ? 'Actif'
                                                : 'Désactivé',
                                            tone: account.isActive
                                                ? SgTone.success
                                                : SgTone.danger,
                                          ),
                                          if (account.studentProfile != null)
                                            SgBadge(
                                              'Étudiant · ${account.studentProfile!['student_number'] ?? ''}',
                                              tone: SgTone.neutral,
                                            ),
                                          if (account.juryProfile != null)
                                            SgBadge(
                                              'Jury · ${account.juryProfile!['name'] ?? ''}',
                                              tone: SgTone.neutral,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                SgIconBtn(
                                  icon: Icons.edit_outlined,
                                  tooltip: 'Modifier le compte',
                                  onPressed: _saving
                                      ? null
                                      : () => _editAccount(account: account),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

String _roleLabel(String role) => switch (role) {
  'admin' => 'Administrateur',
  'responsible' => 'Responsable',
  'supervisor' => 'Encadreur',
  'jury' => 'Membre du jury',
  'student' => 'Étudiant',
  _ => 'Non défini',
};

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
  final String password;
  final int? studentId;
  final int? juryMemberId;

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

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.account,
    required this.students,
    required this.juryMembers,
    required this.isCurrentAccount,
  });

  final AccountRecord? account;
  final List<StudentOption> students;
  final List<JuryMemberOption> juryMembers;
  final bool isCurrentAccount;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  final _password = TextEditingController();
  late String _role;
  late bool _isActive;
  int? _studentId;
  int? _juryMemberId;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _username = TextEditingController(text: account?.username ?? '');
    _email = TextEditingController(text: account?.email ?? '');
    _firstName = TextEditingController(text: account?.firstName ?? '');
    _lastName = TextEditingController(text: account?.lastName ?? '');
    _role = account?.role ?? 'responsible';
    _isActive = account?.isActive ?? true;
    _studentId = int.tryParse(account?.studentProfile?['id']?.toString() ?? '');
    _juryMemberId = int.tryParse(account?.juryProfile?['id']?.toString() ?? '');
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _required(String? value, String label) {
    return value == null || value.trim().isEmpty ? '$label est requis.' : null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'student' &&
        !widget.students.any((student) => student.id == _studentId)) {
      return;
    }
    if (_role == 'jury' &&
        !widget.juryMembers.any((member) => member.id == _juryMemberId)) {
      return;
    }
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
    return AlertDialog(
      title: Text(
        widget.account == null ? 'Créer un compte' : 'Modifier le compte',
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Identifiant'),
                  validator: (value) => _required(value, 'L’identifiant'),
                ),
                TextFormField(
                  controller: _firstName,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                ),
                TextFormField(
                  controller: _lastName,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return value.contains('@')
                        ? null
                        : 'Adresse e-mail invalide.';
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rôle'),
                  items: const [
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Administrateur'),
                    ),
                    DropdownMenuItem(
                      value: 'responsible',
                      child: Text('Responsable pédagogique'),
                    ),
                    DropdownMenuItem(
                      value: 'supervisor',
                      child: Text('Encadreur'),
                    ),
                    DropdownMenuItem(value: 'student', child: Text('Étudiant')),
                    DropdownMenuItem(
                      value: 'jury',
                      child: Text('Membre du jury'),
                    ),
                  ],
                  onChanged: widget.isCurrentAccount
                      ? null
                      : (value) {
                          if (value != null) setState(() => _role = value);
                        },
                ),
                if (widget.isCurrentAccount)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Votre rôle ne peut pas être modifié depuis votre propre compte.',
                        style: TextStyle(fontSize: 12, color: AppColors.grey),
                      ),
                    ),
                  ),
                if (_role == 'student') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _studentId,
                    decoration: const InputDecoration(
                      labelText: 'Fiche étudiant associée',
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
                    initialValue: _juryMemberId,
                    decoration: const InputDecoration(
                      labelText: 'Membre du jury associé',
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
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.account == null
                        ? 'Mot de passe'
                        : 'Nouveau mot de passe (facultatif)',
                  ),
                  validator: (value) {
                    if (widget.account == null &&
                        (value == null || value.isEmpty)) {
                      return 'Le mot de passe initial est requis.';
                    }
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
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _StudentDraft {
  const _StudentDraft(this.studentNumber, this.fullName, this.email);

  final String studentNumber;
  final String fullName;
  final String email;
}

class _StudentDialog extends StatefulWidget {
  const _StudentDialog();

  @override
  State<_StudentDialog> createState() => _StudentDialogState();
}

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer une fiche étudiant'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _number,
                decoration: const InputDecoration(labelText: 'Matricule'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le matricule est requis.'
                    : null,
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le nom complet est requis.'
                    : null,
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
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
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _StudentDraft(
                _number.text.trim(),
                _name.text.trim(),
                _email.text.trim(),
              ),
            );
          },
          child: const Text('Créer la fiche'),
        ),
      ],
    );
  }
}
