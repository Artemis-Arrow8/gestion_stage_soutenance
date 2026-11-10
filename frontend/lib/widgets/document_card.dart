import 'package:flutter/material.dart';

import '../models/document_version_model.dart';

class DocumentCard extends StatelessWidget {
  final DocumentVersion document;
  final VoidCallback? onTap;

  const DocumentCard({
    super.key,
    required this.document,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFEBEE),
          child: Icon(Icons.picture_as_pdf, color: Colors.red),
        ),
        title: Text(
          'Document version ${document.versionNumber}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          document.uploadedAt == null
              ? 'Date inconnue'
              : 'Déposé le ${document.uploadedAt!.day.toString().padLeft(2, '0')}/'
                  '${document.uploadedAt!.month.toString().padLeft(2, '0')}/'
                  '${document.uploadedAt!.year}',
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }
}