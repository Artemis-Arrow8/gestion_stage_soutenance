import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/document_provider.dart';

class DocumentUploadView extends StatefulWidget {
  final int folderId;
  final String accessToken;

  const DocumentUploadView({
    super.key,
    required this.folderId,
    required this.accessToken,
  });

  @override
  State<DocumentUploadView> createState() => _DocumentUploadViewState();
}

class _DocumentUploadViewState extends State<DocumentUploadView> {
  String? _filePath;
  String? _fileName;
  int? _fileSize;

Future<void> _selectFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );

  if (!mounted || result.isEmpty) return;

  final file = result.first;
  final path = file.path;

  if (path == null) {
    _showMessage('Impossible de lire ce fichier.');
    return;
  }

  final fileSize = await File(path).length();

  if (!mounted) return;

  if (fileSize > 10 * 1024 * 1024) {
    _showMessage('Le fichier ne doit pas dépasser 10 Mo.');
    return;
  }

  setState(() {
    _filePath = path;
    _fileName = file.name;
    _fileSize = fileSize;
  });
}
  Future<void> _upload() async {
    if (_filePath == null) {
      _showMessage('Veuillez sélectionner un fichier PDF.');
      return;
    }

    final provider = context.read<DocumentProvider>();

    final success = await provider.uploadDocument(
      folderId: widget.folderId,
      filePath: _filePath!,
      accessToken: widget.accessToken,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document déposé avec succès.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } else {
      _showMessage(provider.errorMessage ?? 'Échec du dépôt.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocumentProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Déposer un document'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.picture_as_pdf,
              size: 75,
              color: Colors.red,
            ),
            const SizedBox(height: 20),
            const Text(
              'Déposez votre document de stage',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Format accepté : PDF\nTaille maximale : 10 Mo',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 25),
            OutlinedButton.icon(
              onPressed: provider.isLoading ? null : _selectFile,
              icon: const Icon(Icons.attach_file),
              label: const Text('Choisir un fichier PDF'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.picture_as_pdf,
                    color: Colors.red,
                  ),
                  title: Text(_fileName!),
                  subtitle: Text(
                    '${(_fileSize! / (1024 * 1024)).toStringAsFixed(2)} Mo',
                  ),
                  trailing: IconButton(
                    onPressed: provider.isLoading
                        ? null
                        : () {
                            setState(() {
                              _filePath = null;
                              _fileName = null;
                              _fileSize = null;
                            });
                          },
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed:
                    _filePath == null || provider.isLoading ? null : _upload,
                icon: provider.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  provider.isLoading
                      ? 'Envoi en cours...'
                      : 'Envoyer le document',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}