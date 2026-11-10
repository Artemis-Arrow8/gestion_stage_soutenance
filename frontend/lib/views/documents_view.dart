import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/document_provider.dart';
import '../widgets/document_card.dart';
import 'document_upload_view.dart';
import 'document_details_view.dart';

class DocumentsView extends StatefulWidget {
  final int folderId;
  final String accessToken;

  const DocumentsView({
    super.key,
    required this.folderId,
    required this.accessToken,
  });

  @override
  State<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends State<DocumentsView> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<DocumentProvider>().loadDocuments(
            accessToken: widget.accessToken,
            folderId: widget.folderId,
          );
    });
  }

  Future<void> _refreshDocuments() async {
    await context.read<DocumentProvider>().loadDocuments(
          accessToken: widget.accessToken,
          folderId: widget.folderId,
        );
  }

  Future<void> _openUploadPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentUploadView(
          folderId: widget.folderId,
          accessToken: widget.accessToken,
        ),
      ),
    );

    if (mounted) {
      await _refreshDocuments();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DocumentProvider>();
    final documents = provider.documents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes documents'),
        actions: [
          IconButton(
            onPressed: _refreshDocuments,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: provider.isLoading ? null : _openUploadPage,
        icon: const Icon(Icons.upload_file),
        label: const Text('Déposer'),
      ),

      body: RefreshIndicator(
        onRefresh: _refreshDocuments,
        child: provider.isLoading && documents.isEmpty
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : provider.errorMessage != null && documents.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(
                        Icons.error_outline,
                        size: 55,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(provider.errorMessage!),
                      ),
                      TextButton(
                        onPressed: _refreshDocuments,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  )
                : documents.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 150),
                          Icon(
                            Icons.folder_open,
                            size: 65,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Center(
                            child: Text(
                              'Aucun document déposé pour le moment.',
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          final document = documents[index];

                          return DocumentCard(
                            document: document,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DocumentDetailsView(
                                    document: document,
                                    accessToken: widget.accessToken,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
      ),
    );
  }
}