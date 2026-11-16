/// Modèles fortement typés des écrans d'administration SGSUS.
///
/// Chaque modèle expose une fabrique `fromJson` qui convertit la réponse
/// de l'API Django en objet Dart sûr : les identifiants obligatoires sont
/// vérifiés et les champs textuels absents remplacés par une chaîne vide.
library;

/// Campagne académique (année universitaire).
class CampaignRecord {
  /// Crée une campagne.
  const CampaignRecord({
    required this.id,
    required this.academicYear,
    required this.isActive,
  });

  /// Identifiant en base.
  final int id;

  /// Année universitaire, ex. « 2026-2027 ».
  final String academicYear;

  /// Vrai si la campagne est en cours.
  final bool isActive;

  /// Construit une campagne depuis le JSON de `/api/campaigns/`.
  ///
  /// Lève une [FormatException] si l'identifiant est absent ou invalide.
  factory CampaignRecord.fromJson(Map<String, dynamic> json) {
    return CampaignRecord(
      id: _requiredId(json['id'], 'campagne'),
      academicYear: json['academic_year']?.toString() ?? '',
      isActive: json['is_active'] == true,
    );
  }
}

/// Fiche étudiante proposée dans les listes de sélection.
class StudentOption {
  /// Crée une option étudiante.
  const StudentOption({
    required this.id,
    required this.studentNumber,
    required this.fullName,
    required this.email,
  });

  /// Identifiant de la fiche.
  final int id;

  /// Numéro d'étudiant (matricule).
  final String studentNumber;

  /// Nom complet.
  final String fullName;

  /// Adresse e-mail.
  final String email;

  /// Construit une fiche depuis le JSON de `/api/students/`.
  factory StudentOption.fromJson(Map<String, dynamic> json) {
    return StudentOption(
      id: _requiredId(json['id'], 'étudiant'),
      studentNumber: json['student_number']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }

  /// Libellé affiché dans les listes : « matricule — nom ».
  String get label => '$studentNumber — $fullName';
}

/// Membre de jury proposé dans les listes de sélection.
class JuryMemberOption {
  /// Crée une option de membre de jury.
  const JuryMemberOption({
    required this.id,
    required this.juryId,
    required this.name,
    required this.role,
  });

  /// Identifiant du membre.
  final int id;

  /// Identifiant du jury auquel il appartient.
  final int juryId;

  /// Nom du membre.
  final String name;

  /// Rôle dans le jury (président, rapporteur, examinateur).
  final String role;

  /// Construit un membre depuis le JSON de `/api/jury-members/`.
  factory JuryMemberOption.fromJson(Map<String, dynamic> json) {
    return JuryMemberOption(
      id: _requiredId(json['id'], 'membre de jury'),
      juryId: _requiredId(json['jury'], 'jury'),
      name: json['member_name']?.toString() ?? '',
      role: json['role_in_jury']?.toString() ?? '',
    );
  }

  /// Libellé affiché dans les listes : « nom — rôle ».
  String get label => '$name — $role';
}

/// Compte utilisateur tel que géré par l'administration.
class AccountRecord {
  /// Crée un compte.
  const AccountRecord({
    required this.id,
    required this.username,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.isActive,
    required this.studentProfile,
    required this.juryProfile,
  });

  /// Identifiant du compte Django.
  final int id;

  /// Identifiant de connexion.
  final String username;

  /// Adresse e-mail.
  final String email;

  /// Prénom.
  final String firstName;

  /// Nom de famille.
  final String lastName;

  /// Rôle SGSUS (admin, responsible, supervisor, jury, student).
  final String role;

  /// Vrai si le compte peut se connecter.
  final bool isActive;

  /// Résumé de la fiche étudiante liée, ou `null`.
  final Map<String, dynamic>? studentProfile;

  /// Résumé du membre de jury lié, ou `null`.
  final Map<String, dynamic>? juryProfile;

  /// Nom affiché : « Prénom Nom », ou l'identifiant à défaut.
  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? username : name;
  }

  /// Construit un compte depuis le JSON de `/api/accounts/`.
  factory AccountRecord.fromJson(Map<String, dynamic> json) {
    return AccountRecord(
      id: _requiredId(json['id'], 'compte'),
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      isActive: json['is_active'] == true,
      studentProfile: _mapValue(json['student_profile']),
      juryProfile: _mapValue(json['jury_profile']),
    );
  }
}

/// Convertit une valeur JSON en identifiant entier obligatoire.
///
/// [label] précise l'objet concerné dans le message d'erreur.
/// Lève une [FormatException] si la conversion échoue.
int _requiredId(dynamic value, String label) {
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw FormatException('Identifiant $label invalide.');
  }
  return parsed;
}

/// Retourne une copie typée d'un objet JSON, ou `null` si ce n'en est pas un.
Map<String, dynamic>? _mapValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
