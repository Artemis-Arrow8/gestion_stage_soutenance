/// Modèle d'une soutenance planifiée, tel qu'affiché par l'application.
///
/// L'API renvoie un créneau sous forme d'instants ISO 8601 en UTC
/// (`slot_start`, `slot_end`). Le modèle les convertit en heure locale et
/// les découpe en une date `AAAA-MM-JJ` et des heures `HH:MM`, plus
/// pratiques pour l'affichage et les comparaisons dans le calendrier.
library;

/// Soutenance de stage.
class Defense {
  /// Identifiant de la soutenance.
  final int id;

  /// Identifiant du dossier de stage concerné (peut être absent).
  final int? folderId;

  /// Identifiant du jury affecté (peut être absent).
  final int? juryId;

  /// Nom complet de l'étudiant.
  final String studentName;

  /// Sujet du stage.
  final String subject;

  /// Date locale au format `AAAA-MM-JJ` (vide si inconnue).
  final String date;

  /// Heure locale de début au format `HH:MM`.
  final String startTime;

  /// Heure locale de fin au format `HH:MM`.
  final String endTime;

  /// Nom de la salle.
  final String roomName;

  /// Nom du jury (ou liste de membres séparés par des virgules).
  final String juryName;

  /// Statut (planifie, confirme, annule…).
  final String status;

  /// Crée une soutenance.
  Defense({
    required this.id,
    this.folderId,
    this.juryId,
    required this.studentName,
    required this.subject,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.roomName,
    required this.juryName,
    required this.status,
  });

  /// Construit une soutenance depuis le JSON de `/api/soutenances/`.
  ///
  /// Les champs absents ou mal formés sont remplacés par des valeurs vides
  /// afin qu'une donnée incomplète ne bloque pas l'affichage du planning.
  factory Defense.fromJson(Map<String, dynamic> json) {
    // Conversion des instants UTC du serveur en heure locale de l'appareil.
    final debut = DateTime.tryParse(
      json['slot_start']?.toString() ?? '',
    )?.toLocal();
    final fin = DateTime.tryParse(json['slot_end']?.toString() ?? '')?.toLocal();
    final juryDetail = json['jury_detail'];

    return Defense(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      folderId: int.tryParse(json['folder']?.toString() ?? ''),
      juryId: int.tryParse(json['jury']?.toString() ?? ''),
      studentName: json['student_name']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '',
      date: debut == null
          ? ''
          : '${debut.year.toString().padLeft(4, '0')}-'
                '${_deuxChiffres(debut.month)}-${_deuxChiffres(debut.day)}',
      startTime: debut == null ? '' : _heure(debut),
      endTime: fin == null ? '' : _heure(fin),
      roomName: json['room_name']?.toString() ?? '',
      // Nom du jury : champ dénormalisé, sinon détail imbriqué.
      juryName:
          json['jury_name']?.toString() ??
          (juryDetail is Map ? juryDetail['name']?.toString() : null) ??
          '',
      status: json['status']?.toString() ?? '',
    );
  }

  /// Copie la soutenance en remplaçant les champs fournis.
  ///
  /// Utilisée pour préremplir le formulaire lors d'une duplication.
  Defense copier({
    String? studentName,
    String? subject,
    String? date,
    String? startTime,
    String? endTime,
    String? roomName,
    String? juryName,
    String? status,
  }) {
    return Defense(
      id: id,
      folderId: folderId,
      juryId: juryId,
      studentName: studentName ?? this.studentName,
      subject: subject ?? this.subject,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      roomName: roomName ?? this.roomName,
      juryName: juryName ?? this.juryName,
      status: status ?? this.status,
    );
  }

  /// Formate un entier sur deux chiffres (5 → « 05 »).
  static String _deuxChiffres(int valeur) => valeur.toString().padLeft(2, '0');

  /// Formate l'heure d'un instant au format `HH:MM`.
  static String _heure(DateTime instant) =>
      '${_deuxChiffres(instant.hour)}:${_deuxChiffres(instant.minute)}';
}
