import 'document_version_model.dart';

class DocumentModel {
  final int id;
  final int folderId;
  final String title;
  final String? description;
  final String status;
  final List<DocumentVersion> versions;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DocumentModel({
    required this.id,
    required this.folderId,
    required this.title,
    this.description,
    required this.status,
    this.versions = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as int,
      folderId: json['folder'] as int,
      title: json['title']?.toString() ?? 'Document',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'en_attente',
      versions: (json['versions'] as List<dynamic>?)
              ?.map((item) => DocumentVersion.fromJson(
                    item as Map<String, dynamic>,
                  ))
              .toList() ??
          [],
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
      'id': id,
      'folder': folderId,
      'title': title,
      'description': description,
      'status': status,
      'versions': versions.map((version) => version.toJson()).toList(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}