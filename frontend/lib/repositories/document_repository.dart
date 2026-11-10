import 'dart:typed_data';

import '../models/document_version_model.dart';
import '../services/document_api_service.dart';

class DocumentRepository {
  DocumentRepository({
    DocumentApiService? apiService,
  }) : _apiService = apiService ?? DocumentApiService();

  final DocumentApiService _apiService;

  /// Récupérer les documents.
  Future<List<DocumentVersion>> getDocuments({
    required String accessToken,
  }) async {
    return await _apiService.getDocuments(
      accessToken: accessToken,
    );
  }

  /// Déposer un document.
  Future<DocumentVersion> uploadDocument({
    required int folderId,
    required String filePath,
    required String accessToken,
  }) async {
    return await _apiService.uploadDocument(
      folderId: folderId,
      filePath: filePath,
      accessToken: accessToken,
    );
  }

  /// Télécharger un document.
  Future<Uint8List> downloadDocument({
    required int documentId,
    required String accessToken,
  }) async {
    return await _apiService.downloadDocument(
      documentId: documentId,
      accessToken: accessToken,
    );
  }
}