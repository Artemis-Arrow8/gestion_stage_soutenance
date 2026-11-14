import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Centralise les routes REST des dossiers, documents et avis associés.
class DocumentService {
  DocumentService({
    required this.accessToken,
    String? Function()? accessTokenProvider,
    this.refreshAccessToken,
    http.Client? client,
  })  : _accessTokenProvider = accessTokenProvider ?? (() => accessToken),
        _client = client ?? http.Client();

  final String? accessToken;
  final String? Function() _accessTokenProvider;
  final Future<bool> Function()? refreshAccessToken;
  final http.Client _client;

  Map<String, String> _headers(String? token) => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _url(String path, {Map<String, String>? queryParameters}) {
    final base = ApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final endpoint = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$endpoint')
        .replace(queryParameters: queryParameters);
  }

  Future<List<dynamic>> getFolders() async {
    return _getList('internship-folders/');
  }

  Future<List<dynamic>> getDocuments(int folderId) async {
    final documents = await _getList('document-versions/');
    return documents.where((document) {
      if (document is! Map) return false;
      return int.tryParse(document['folder']?.toString() ?? '') == folderId;
    }).toList();
  }

  Future<void> uploadDocument(int folderId, PlatformFile file) async {
    final bytes = await file.readAsBytes();
    final response = await _sendWithRefresh((token) async {
      final request = http.MultipartRequest('POST', _url('documents/upload/'));
      request.headers.addAll(_headers(token));
      request.fields['folder_id'] = folderId.toString();
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: file.name),
      );
      return http.Response.fromStream(await _client.send(request));
    });
    if (response.statusCode != 201) {
      throw _apiError(response);
    }
  }

  /// Retourne les avis visibles pour le compte et cette version de document.
  Future<List<dynamic>> getReviews(int documentId) {
    return _getList(
      'reviews/',
      queryParameters: {'document_version_id': documentId.toString()},
    );
  }

  /// Envoie un avis en le reliant explicitement à la version concernée.
  Future<Map<String, dynamic>> addReview(
    int documentId,
    String decision,
    String comments,
  ) async {
    final response = await _sendWithRefresh((token) => _client.post(
          _url('reviews/'),
          headers: {
            ..._headers(token),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'document_version': documentId,
            'decision': decision,
            if (comments.trim().isNotEmpty) 'comments': comments.trim(),
          }),
        ));
    if (response.statusCode != 201) {
      throw _apiError(response);
    }
    return _decodeObject(response);
  }

  Future<bool> downloadDocument(int documentId) async {
    final response = await _sendWithRefresh((token) => _client.get(
          _url('documents/download/$documentId/'),
          headers: _headers(token),
        ));
    if (response.statusCode != 200) {
      throw _apiError(response);
    }

    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Enregistrer le document',
      fileName: 'document_$documentId.pdf',
      mimeType: 'application/pdf',
      bytes: response.bodyBytes,
    );
    return savedUri != null;
  }

  Future<List<dynamic>> _getList(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await _sendWithRefresh((token) => _client.get(
          _url(path, queryParameters: queryParameters),
          headers: _headers(token),
        ));
    if (response.statusCode != 200) {
      throw _apiError(response);
    }

    final data = jsonDecode(response.body);
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    throw const FormatException('Le serveur a renvoyé une liste invalide.');
  }

  Future<http.Response> _sendWithRefresh(
    Future<http.Response> Function(String? token) send,
  ) async {
    var response = await send(_accessTokenProvider());
    final refresh = refreshAccessToken;
    if (response.statusCode == 401 &&
        refresh != null &&
        await refresh()) {
      response = await send(_accessTokenProvider());
    }
    return response;
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('Le serveur a renvoyé un objet invalide.');
  }

  ApiException _apiError(http.Response response) {
    String message = 'Erreur HTTP ${response.statusCode}.';
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        final messages = data.values.map(_flattenError).where((e) => e.isNotEmpty);
        final joined = messages.join(' ');
        if (joined.isNotEmpty) message = joined;
      }
    } on FormatException {
      if (response.body.isNotEmpty) message = response.body;
    }
    return ApiException(message, statusCode: response.statusCode);
  }

  String _flattenError(dynamic value) {
    if (value is String) return value;
    if (value is Iterable) {
      return value.map(_flattenError).where((e) => e.isNotEmpty).join(' ');
    }
    if (value is Map) {
      return value.values.map(_flattenError).where((e) => e.isNotEmpty).join(' ');
    }
    return '';
  }
}
