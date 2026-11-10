import 'package:flutter/material.dart';

import '../models/document_version_model.dart';

class DocumentHistoryView extends StatelessWidget {
  final List<DocumentVersion> documents;

  const DocumentHistoryView({
    super.key,
    required this.documents,
  });

  @override
  Widget build(BuildContext context) {
    final history = [...documents]
      ..sort((a, b) => b.versionNumber.compareTo(a.versionNumber));

    return Scaffold(
      appBar: AppBar(title: const Text('Historique des documents')),
      body: history.isEmpty
          ? const Center(child: Text('Aucun historique disponible.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final document = history[index];

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.history),
                    ),
                    title: Text('Version ${document.versionNumber}'),
                    subtitle: Text(
                      document.uploadedAt?.toString() ??
                          'Date non disponible',
                    ),
                    trailing: const Icon(Icons.picture_as_pdf),
                  ),
                );
              },
            ),
    );
  }
}