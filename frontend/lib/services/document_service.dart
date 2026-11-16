/// Accès aux routes documentaires : dossiers de stage, versions de
/// rapports PDF et avis d'encadrement.
library;

import 'package:file_picker/file_picker.dart';

import '../core/network/api_service.dart';

/// Service de la gestion documentaire.
class DocumentService {
  /// Crée le service à partir du client HTTP authentifié [api].
  DocumentService(this.api);

  /// Client HTTP authentifié partagé.
  final ApiService api;

  /// Liste les dossiers de stage visibles par le compte connecté.
  ///
  /// Le serveur filtre déjà selon le rôle (étudiant : les siens ;
  /// encadreur : ceux qui lui sont affectés ; personnel : tous).
  Future<List<Map<String, dynamic>>> getFolders() {
    return api.getList('internship-folders/');
  }

  /// Liste les versions de documents du dossier [folderId].
  Future<List<Map<String, dynamic>>> getDocuments(int folderId) async {
    final documents = await api.getList('document-versions/');
    // Filtrage côté client : la route ne propose pas de filtre par dossier.
    return documents
        .where(
          (document) =>
              int.tryParse(document['folder']?.toString() ?? '') == folderId,
        )
        .toList();
  }

  /// Dépose le fichier PDF [file] dans le dossier [folderId].
  ///
  /// Le serveur vérifie la taille (10 Mo max) et la signature PDF ; un refus
  /// remonte sous forme d'[ApiException] au message explicite.
  Future<void> uploadDocument(int folderId, PlatformFile file) async {
    // `readAsBytes` fonctionne sur toutes les plateformes, Web compris.
    final bytes = await file.readAsBytes();
    await api.postMultipart(
      'documents/upload/',
      fields: {'folder_id': folderId.toString()},
      fileField: 'file',
      bytes: bytes,
      filename: file.name,
    );
  }

  /// Retourne les avis visibles pour la version de document [documentId].
  Future<List<Map<String, dynamic>>> getReviews(int documentId) {
    return api.getList(
      'reviews/',
      query: {'document_version_id': documentId.toString()},
    );
  }

  /// Enregistre un avis ([decision] + [comments]) sur [documentId].
  ///
  /// Un commentaire vide n'est pas transmis.
  Future<Map<String, dynamic>> addReview(
    int documentId,
    String decision,
    String comments,
  ) async {
    final data = await api.post('reviews/', {
      'document_version': documentId,
      'decision': decision,
      if (comments.trim().isNotEmpty) 'comments': comments.trim(),
    });
    return ApiService.requireObject(data);
  }

  /// Télécharge le PDF [documentId] puis propose de l'enregistrer.
  ///
  /// Retourne `true` si l'utilisateur a choisi un emplacement (sur le Web,
  /// le navigateur gère directement le téléchargement).
  Future<bool> downloadDocument(int documentId) async {
    final bytes = await api.getBytes('documents/download/$documentId/');
    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Enregistrer le document',
      fileName: 'document_$documentId.pdf',
      mimeType: 'application/pdf',
      bytes: bytes,
    );
    return savedUri != null;
  }
}
