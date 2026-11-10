import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/document_provider.dart';
import '../views/document_upload_view.dart';

class UploadDocumentWidget extends StatelessWidget {
  final int folderId;
  final String accessToken;

  const UploadDocumentWidget({
    super.key,
    required this.folderId,
    required this.accessToken,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.upload_file),
      label: const Text('Déposer un document'),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
              value: context.read<DocumentProvider>(),
              child: DocumentUploadView(
                folderId: folderId,
                accessToken: accessToken,
              ),
            ),
          ),
        );
      },
    );
  }
}