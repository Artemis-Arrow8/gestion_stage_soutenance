class FolderTrackingModel {
  final int folderId;
  final String studentName;
  final String academicYear;
  final String status;
  final int progress;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FolderTrackingModel({
    required this.folderId,
    required this.studentName,
    required this.academicYear,
    required this.status,
    required this.progress,
    this.createdAt,
    this.updatedAt,
  });

  factory FolderTrackingModel.fromJson(Map<String, dynamic> json) {
    return FolderTrackingModel(
      folderId: json['id'] as int,
      studentName: json['student_name']?.toString() ?? '',
      academicYear: json['academic_year']?.toString() ?? '',
      status: json['status']?.toString() ?? 'en_attente',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': folderId,
      'student_name': studentName,
      'academic_year': academicYear,
      'status': status,
      'progress': progress,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}