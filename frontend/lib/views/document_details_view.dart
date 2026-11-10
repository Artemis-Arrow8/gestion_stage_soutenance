import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/document_version_model.dart';
import '../providers/document_provider.dart';
import 'document_history_view.dart';

class DocumentDetailsView extends StatelessWidget {
  final DocumentVersion document;
  final String accessToken;

  const DocumentDetailsView({
    super.key,
    required this.document,
    required this.accessToken,
  });

  Future<void> _download(BuildContext context) async {
    final provider = context.read<DocumentProvider>();

    final bytes = await provider.downloadDocument(
      documentId: document.id,
      accessToken: accessToken,
    );

    if (!context.mounted) return;

    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Téléchargement impossible.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Document téléchargé en mémoire. Préparez son ouverture ou son enregistrement.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocumentProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Détails du document')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Icon(
                Icons.picture_as_pdf,
                size: 85,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 25),
            Text(
              'Document ${document.id}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 30),
            _info('Identifiant', document.id.toString()),
            _info('Dossier', document.folderId.toString()),
            _info('Version', document.versionNumber.toString()),
            _info('Fichier', document.filePath.split('/').last),
            _info(
              'Date de dépôt',
              document.uploadedAt?.toString() ?? 'Non renseignée',
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: provider.isLoading ? null : () => _download(context),
                icon: const Icon(Icons.download),
                label: const Text('Télécharger le document'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DocumentHistoryView(
                        documents: [document],
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.history),
                label: const Text('Voir l’historique'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }
}