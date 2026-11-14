import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/document_version_model.dart';

class DocumentApiService {
  DocumentApiService({http.Client? client})
      : _client = client ?? http.Client();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  final http.Client _client;

  Map<String, String> _headers(String token) => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };

  String get _base =>
      baseUrl.replaceFirst(RegExp(r'/+$'), '');

  /// Récupère les versions accessibles via le ViewSet DRF.
  Future<List<DocumentVersion>> getDocuments({
    required String accessToken,
  }) async {
    final uri = Uri.parse('$_base/document-versions/');

    final response = await _client.get(
      uri,
      headers: _headers(accessToken),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      final List<dynamic> items =
          data is List ? data : data['results'] as List<dynamic>;

      return items
          .map((item) => DocumentVersion.fromJson(
                item as Map<String, dynamic>,
              ))
          .toList();
    }

    throw Exception(_getErrorMessage(response));
  }

  /// Dépose un PDF via l’endpoint de téléversement sécurisé.
  Future<DocumentVersion> uploadDocument({
    required int folderId,
    required String filePath,
    required String accessToken,
  }) async {
    final uri = Uri.parse('$_base/documents/upload/');

    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll(_headers(accessToken));
    request.fields['folder_id'] = folderId.toString();

    request.files.add(
      await http.MultipartFile.fromPath('file', filePath),
    );

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);

      return DocumentVersion.fromJson(data as Map<String, dynamic>);
    }

    throw Exception(_getErrorMessage(response));
  }

  /// Télécharge une version depuis l’endpoint autorisé par le backend.
  Future<Uint8List> downloadDocument({
    required int documentId,
    required String accessToken,
  }) async {
    final uri = Uri.parse(
      '$_base/documents/download/$documentId/',
    );

    final response = await _client.get(
      uri,
      headers: _headers(accessToken),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    }

    throw Exception(_getErrorMessage(response));
  }

  String _getErrorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        return data['error']?.toString() ??
            data['detail']?.toString() ??
            'Erreur HTTP ${response.statusCode}';
      }
    } catch (_) {}

    return 'Erreur HTTP ${response.statusCode}';
  }
}