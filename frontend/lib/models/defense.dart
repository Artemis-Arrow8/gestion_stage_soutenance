class Defense {
  final int id;
  final int? folderId;
  final int? juryId;
  final String studentName;
  final String subject;
  final String date;
  final String startTime;
  final String endTime;
  final String roomName;
  final String juryName;
  final String status;

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

  factory Defense.fromJson(Map<String, dynamic> json) {
    final debut = DateTime.tryParse(json['slot_start']?.toString() ?? '');
    final fin = DateTime.tryParse(json['slot_end']?.toString() ?? '');
    final juryDetail = json['jury_detail'];

    return Defense(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      folderId: int.tryParse(json['folder']?.toString() ?? ''),
      juryId: int.tryParse(json['jury']?.toString() ?? ''),
      studentName: json['student_name']?.toString() ?? '',
      subject: json['subject'] ?? '',
      date: debut == null
          ? ''
          : '${debut.toLocal().year.toString().padLeft(4, '0')}-'
              '${debut.toLocal().month.toString().padLeft(2, '0')}-'
              '${debut.toLocal().day.toString().padLeft(2, '0')}',
      startTime: debut == null
          ? ''
          : '${debut.toLocal().hour.toString().padLeft(2, '0')}:'
              '${debut.toLocal().minute.toString().padLeft(2, '0')}',
      endTime: fin == null
          ? ''
          : '${fin.toLocal().hour.toString().padLeft(2, '0')}:'
              '${fin.toLocal().minute.toString().padLeft(2, '0')}',
      roomName: json['room_name'] ?? '',
      juryName: json['jury_name']?.toString() ??
          (juryDetail is Map ? juryDetail['name']?.toString() : null) ??
          '',
      status: json['status'] ?? '',
    );
  }

  /// Copie la soutenance en remplaçant les champs fournis.
  /// Utilisée pour la modification d'une soutenance existante.
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
}
