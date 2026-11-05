class UserModel {
  final int id;
  final String studentNumber;
  final String fullName;
  final String email;
  final String role;

  UserModel({
    required this.id,
    required this.studentNumber,
    required this.fullName,
    required this.email,
    required this.role,
  });

  /// Convertit un JSON (provenant de l'API Django) en instance de UserModel
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      studentNumber: json['student_number'] ?? '',
      fullName: json['full_name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'student',
    );
  }

  /// Convertit l'objet UserModel en Map JSON (si besoin d'envoi ultérieur)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_number': studentNumber,
      'full_name': fullName,
      'email': email,
      'role': role,
    };
  }
}
