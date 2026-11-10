import 'package:flutter/foundation.dart';

import '../models/document_version_model.dart';
import '../repositories/document_repository.dart';

class DocumentProvider extends ChangeNotifier {
  DocumentProvider({DocumentRepository? repository})
      : _repository = repository ?? DocumentRepository();

  final DocumentRepository _repository;

  final List<DocumentVersion> _documents = [];

  bool _isLoading = false;
  String? _errorMessage;

  List<DocumentVersion> get documents => List.unmodifiable(_documents);

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  /// Charger les documents depuis le backend.
  Future<bool> loadDocuments({
    required String accessToken,
    int? folderId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.getDocuments(
        accessToken: accessToken,
      );

      _documents
        ..clear()
        ..addAll(
          folderId == null
              ? result
              : result.where((document) => document.folderId == folderId),
        );

      return true;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Déposer un document PDF.
  Future<bool> uploadDocument({
    required int folderId,
    required String filePath,
    required String accessToken,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final document = await _repository.uploadDocument(
        folderId: folderId,
        filePath: filePath,
        accessToken: accessToken,
      );

      _documents.insert(0, document);
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Télécharger un document.
  Future<Uint8List?> downloadDocument({
    required int documentId,
    required String accessToken,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await _repository.downloadDocument(
        documentId: documentId,
        accessToken: accessToken,
      );
    } catch (error) {
      _errorMessage = error.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Effacer les documents chargés.
  void clearDocuments() {
    _documents.clear();
    _errorMessage = null;
    notifyListeners();
  }
}