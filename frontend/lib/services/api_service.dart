import 'dart:convert';

import 'package:http/http.dart' as http;

/// Décrit une erreur HTTP de l’API sans masquer son code de réponse.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Centralise les appels JSON et la traduction des erreurs Django REST.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  final http.Client _client;

  /// Envoie une requête POST JSON à l’API.
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data, {
    String? accessToken,
  }) {
    return _request('POST', endpoint, data: data, accessToken: accessToken);
  }

  /// Envoie une requête GET authentifiée ou publique à l’API.
  Future<Map<String, dynamic>> get(String endpoint, {String? accessToken}) {
    return _request('GET', endpoint, accessToken: accessToken);
  }

  /// Envoie une requête PATCH JSON à l’API.
  Future<Map<String, dynamic>> patch(
    String endpoint,
    Map<String, dynamic> data, {
    String? accessToken,
  }) {
    return _request('PATCH', endpoint, data: data, accessToken: accessToken);
  }

  /// Exécute une requête HTTP, décode sa réponse et conserve les erreurs API.
  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint, {
    Map<String, dynamic>? data,
    String? accessToken,
  }) async {
    final normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');
    final request = http.Request(
      method,
      Uri.parse('$normalizedBase/$normalizedEndpoint'),
    );
    request.headers['Accept'] = 'application/json';
    if (data != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(data);
    }
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }

    late final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (error) {
      throw ApiException(
        'Impossible de joindre le serveur API. Vérifiez son adresse et son état : ${error.message}',
      );
    }

    dynamic responseBody;
    if (response.body.isNotEmpty) {
      try {
        responseBody = jsonDecode(response.body);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException(
            'Le serveur a renvoyé une réponse JSON invalide.',
          );
        }
        throw ApiException(
          'Le serveur a répondu avec le code HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (responseBody == null) {
        return <String, dynamic>{};
      }
      if (responseBody is Map<String, dynamic>) {
        return responseBody;
      }
      throw const FormatException(
        'Le format de la réponse du serveur est invalide.',
      );
    }

    throw ApiException(
      _errorMessage(responseBody, response.statusCode),
      statusCode: response.statusCode,
    );
  }

  /// Extrait un message lisible des réponses d’erreur DRF et SimpleJWT.
  String _errorMessage(dynamic body, int statusCode) {
    if (body is Map<String, dynamic>) {
      for (final key in const ['error', 'detail', 'non_field_errors']) {
        final value = body[key];
        if (value != null) {
          final message = _flattenError(value);
          if (message.isNotEmpty) {
            return message;
          }
        }
      }
      final messages = body.entries
          .map((entry) => _flattenError(entry.value))
          .where((message) => message.isNotEmpty)
          .toList();
      if (messages.isNotEmpty) {
        return messages.join(' ');
      }
    } else {
      final message = _flattenError(body);
      if (message.isNotEmpty) {
        return message;
      }
    }
    return 'Le serveur a répondu avec le code HTTP $statusCode.';
  }

  /// Aplati les listes et objets de validation renvoyés par Django REST.
  String _flattenError(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is List) {
      return value
          .map(_flattenError)
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    if (value is Map) {
      return value.values
          .map(_flattenError)
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    return '';
  }
}
