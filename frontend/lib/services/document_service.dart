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

  /// Crée le dossier de stage de l'étudiant connecté.
  ///
  /// Le serveur rattache automatiquement le dossier à la fiche de
  /// l'étudiant et à la campagne active, au statut « brouillon ».
  Future<Map<String, dynamic>> createFolder({
    required String companyName,
    required String subject,
  }) async {
    final data = await api.post('internship-folders/', {
      'company_name': companyName,
      'subject': subject,
    });
    return ApiService.requireObject(data);
  }

  /// Modifie l'entreprise et le sujet du dossier [folderId].
  Future<void> updateFolder(
    int folderId, {
    required String companyName,
    required String subject,
  }) async {
    await api.patch('internship-folders/$folderId/', {
      'company_name': companyName,
      'subject': subject,
    });
  }

  /// Applique une transition au dossier [folderId] (chapitre 4).
  ///
  /// Le statut ne se modifie jamais directement : [action] vaut
  /// `soumettre` (étudiant), `autoriser`, `refuser` ou `rouvrir`
  /// (responsable des stages). [motif] est obligatoire pour refuser ou
  /// rouvrir. Une étape sautée est refusée par le serveur (409).
  Future<Map<String, dynamic>> transition(
    int folderId,
    String action, {
    String? motif,
  }) async {
    final data = await api.post('internship-folders/$folderId/$action/', {
      if (motif != null) 'motif': motif,
    });
    return ApiService.requireObject(data);
  }

  /// Historique des transitions du dossier (preuves conservées).
  Future<List<Map<String, dynamic>>> historique(int folderId) {
    return api.getList('internship-folders/$folderId/historique/');
  }

  /// Niveau de confidentialité du rapport du dossier.
  Future<Map<String, dynamic>> confidentialite(int folderId) {
    return api.getObject('internship-folders/$folderId/confidentialite/');
  }

  /// Modifie la confidentialité (personnel) : [niveau] `standard` ou
  /// `confidentiel`, [origine] de la restriction, fin d'[embargo]. La fin
  /// d'un embargo ne rend jamais le rapport public automatiquement.
  Future<Map<String, dynamic>> definirConfidentialite(
    int folderId, {
    required String niveau,
    String origine = '',
    String? embargo,
  }) async {
    final data = await api.put('internship-folders/$folderId/confidentialite/', {
      'niveau': niveau,
      'origine': origine,
      'embargo_jusqu_au': embargo,
      'diffusion_autorisee': false,
    });
    return ApiService.requireObject(data);
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
