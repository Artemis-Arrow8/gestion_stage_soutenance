class DocumentVersion {
  final int id;
  final int folderId;
  final int versionNumber;
  final String filePath;
  final DateTime? uploadedAt;

  const DocumentVersion({
    required this.id,
    required this.folderId,
    required this.versionNumber,
    required this.filePath,
    this.uploadedAt,
  });

  factory DocumentVersion.fromJson(Map<String, dynamic> json) {
    return DocumentVersion(
      id: json['id'] as int,
      folderId: json['folder'] as int,
      versionNumber: json['version_number'] as int,
      filePath: json['file_path'] as String,
      uploadedAt: json['uploaded_at'] != null
          ? DateTime.tryParse(json['uploaded_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'folder': folderId,
      'version_number': versionNumber,
      'file_path': filePath,
      'uploaded_at': uploadedAt?.toIso8601String(),
    };
  }
}