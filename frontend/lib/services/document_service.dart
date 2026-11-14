import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

class DocumentService {
  final String? accessToken;

  DocumentService({required this.accessToken});

  Map<String, String> get _headers => {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Uri _url(String path) {
    return Uri.parse('${ApiService.baseUrl}$path');
  }

  Future<List<dynamic>> getFolders() async {
    final response = await http.get(
      _url('/dossiers/'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Impossible de récupérer les dossiers.');
    }

    final data = jsonDecode(response.body);

    if (data is List) return data;

    if (data is Map && data['results'] is List) {
      return data['results'];
    }

    return [];
  }

  Future<List<dynamic>> getDocuments(int folderId) async {
    final response = await http.get(
      _url('/documents/folder/$folderId/'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Impossible de récupérer les documents.');
    }

    final data = jsonDecode(response.body);

    return data is List ? data : [];
  }

  Future<void> uploadDocument(
    int folderId,
    PlatformFile file,
  ) async {
    final bytes = await file.readAsBytes();

    final request = http.MultipartRequest(
      'POST',
      _url('/documents/upload/'),
    );

    request.headers.addAll(_headers);
    request.fields['folder_id'] = folderId.toString();

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: file.name,
      ),
    );

    final streamedResponse = await request.send();

    final response = await http.Response.fromStream(
      streamedResponse,
    );

    if (response.statusCode != 201) {
      throw Exception(
        'Échec de l’envoi du document : ${response.body}',
      );
    }
  }

  /// Liste les avis (encadreur / tuteur) d'une version de document.
  Future<List<dynamic>> getReviews(int documentId) async {
    final response = await http.get(
      _url('/documents/$documentId/reviews/'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Impossible de récupérer les avis.');
    }

    final data = jsonDecode(response.body);

    return data is List ? data : [];
  }

  /// Dépose un avis (favorable / défavorable) sur une version de document.
  Future<Map<String, dynamic>> addReview(
    int documentId,
    String decision,
    String comments,
  ) async {
    final response = await http.post(
      _url('/documents/$documentId/reviews/'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'decision': decision,
        if (comments.trim().isNotEmpty) 'comments': comments.trim(),
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'Échec de l’envoi de l’avis : ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<bool> downloadDocument(int documentId) async {
    final response = await http.get(
      _url('/documents/$documentId/download/'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Impossible de télécharger le document.');
    }

    // file_picker >= 13 : saveFile écrit lui-même les octets fournis
    // et retourne l'Uri du fichier enregistré (null si annulé).
    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Enregistrer le document',
      fileName: 'document_$documentId.pdf',
      mimeType: 'application/pdf',
      bytes: response.bodyBytes,
    );

    return savedUri != null;
  }
}
