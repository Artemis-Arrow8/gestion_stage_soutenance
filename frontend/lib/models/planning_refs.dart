/// Modèles des référentiels de planification : salles et jurys.
///
/// Ils correspondent aux ressources `/api/salles/` et `/api/jurys/` de
/// l'API Django.
library;

/// Salle de soutenance.
class Room {
  /// Crée une salle.
  const Room({
    required this.id,
    required this.name,
    required this.capacity,
    required this.isActive,
  });

  /// Identifiant en base.
  final int id;

  /// Nom unique de la salle (ex. « Salle A »).
  final String name;

  /// Nombre de places.
  final int capacity;

  /// Vrai si la salle peut accueillir des soutenances.
  final bool isActive;

  /// Construit une salle depuis le JSON de l'API.
  ///
  /// Lève une [FormatException] si l'identifiant est invalide.
  factory Room.fromJson(Map<String, dynamic> json) {
    final id = int.tryParse(json['id']?.toString() ?? '');
    if (id == null) throw const FormatException('Identifiant de salle invalide.');
    return Room(
      id: id,
      name: json['name']?.toString() ?? '',
      capacity: int.tryParse(json['capacity']?.toString() ?? '') ?? 0,
      isActive: json['is_active'] != false,
    );
  }
}

/// Membre d'un jury.
class JuryMember {
  /// Crée un membre.
  const JuryMember({
    required this.id,
    required this.juryId,
    required this.name,
    required this.role,
  });

  /// Identifiant du membre.
  final int id;

  /// Identifiant du jury d'appartenance.
  final int juryId;

  /// Nom du membre.
  final String name;

  /// Rôle technique : `president`, `rapporteur` ou `examinateur`.
  final String role;

  /// Libellé français du rôle.
  String get roleLabel => switch (role) {
    'president' => 'Président',
    'rapporteur' => 'Rapporteur',
    'examinateur' => 'Examinateur',
    _ => role,
  };

  /// Construit un membre depuis le JSON de l'API.
  factory JuryMember.fromJson(Map<String, dynamic> json) {
    return JuryMember(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      juryId: int.tryParse(json['jury']?.toString() ?? '') ?? 0,
      name: json['member_name']?.toString() ?? '',
      role: json['role_in_jury']?.toString() ?? '',
    );
  }
}

/// Jury de soutenance et ses membres.
class Jury {
  /// Crée un jury.
  const Jury({
    required this.id,
    required this.name,
    required this.isComplete,
    required this.members,
  });

  /// Identifiant du jury.
  final int id;

  /// Nom du jury (ex. « Jury A »).
  final String name;

  /// Vrai si la composition est déclarée complète.
  final bool isComplete;

  /// Membres du jury.
  final List<JuryMember> members;

  /// Construit un jury (membres inclus) depuis le JSON de l'API.
  ///
  /// Lève une [FormatException] si l'identifiant est invalide.
  factory Jury.fromJson(Map<String, dynamic> json) {
    final id = int.tryParse(json['id']?.toString() ?? '');
    if (id == null) throw const FormatException('Identifiant de jury invalide.');
    final members = json['members'] is List ? json['members'] as List : const [];
    return Jury(
      id: id,
      name: json['name']?.toString() ?? '',
      isComplete: json['is_complete'] == true,
      members: members
          .whereType<Map>()
          .map((m) => JuryMember.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}
