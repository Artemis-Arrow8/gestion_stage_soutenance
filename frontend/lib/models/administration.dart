/// Modèles fortement typés pour les écrans d'administration SGSUS.
class CampaignRecord {
  const CampaignRecord({
    required this.id,
    required this.academicYear,
    required this.isActive,
  });

  final int id;
  final String academicYear;
  final bool isActive;

  factory CampaignRecord.fromJson(Map<String, dynamic> json) {
    return CampaignRecord(
      id: _requiredId(json['id'], 'campagne'),
      academicYear: json['academic_year']?.toString() ?? '',
      isActive: json['is_active'] == true,
    );
  }
}

class StudentOption {
  const StudentOption({
    required this.id,
    required this.studentNumber,
    required this.fullName,
    required this.email,
  });

  final int id;
  final String studentNumber;
  final String fullName;
  final String email;

  factory StudentOption.fromJson(Map<String, dynamic> json) {
    return StudentOption(
      id: _requiredId(json['id'], 'étudiant'),
      studentNumber: json['student_number']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }

  String get label => '$studentNumber — $fullName';
}

class JuryMemberOption {
  const JuryMemberOption({
    required this.id,
    required this.juryId,
    required this.name,
    required this.role,
  });

  final int id;
  final int juryId;
  final String name;
  final String role;

  factory JuryMemberOption.fromJson(Map<String, dynamic> json) {
    return JuryMemberOption(
      id: _requiredId(json['id'], 'membre de jury'),
      juryId: _requiredId(json['jury'], 'jury'),
      name: json['member_name']?.toString() ?? '',
      role: json['role_in_jury']?.toString() ?? '',
    );
  }

  String get label => '$name — $role';
}

class AccountRecord {
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

  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String role;
  final bool isActive;
  final Map<String, dynamic>? studentProfile;
  final Map<String, dynamic>? juryProfile;

  String get displayName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? username : name;
  }

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

int _requiredId(dynamic value, String label) {
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw FormatException('Identifiant $label invalide.');
  }
  return parsed;
}

Map<String, dynamic>? _mapValue(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
