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

/// Centralise les appels JSON, la gestion des tokens et la traduction des erreurs Django REST.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// URL publique de l’API, remplaçable au lancement avec `--dart-define`.
  ///
  /// Le port 8001 correspond au port local publié par Docker Compose.
  /// En production, fournir l’URL HTTPS du Web Service Render terminée par `/api`.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8001/api',
  );

  /// Client injectable pour permettre des tests HTTP sans réseau réel.
  final http.Client _client;

  /// Envoie un objet JSON à une route POST et retourne sa réponse décodée.
  Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> data, {
    String? accessToken,
  }) async {
    return _request('POST', endpoint, data: data, accessToken: accessToken);
  }

  /// Envoie une requête GET, avec un jeton Bearer si la route est protégée.
  Future<dynamic> get(String endpoint, {String? accessToken}) async {
    return _request('GET', endpoint, accessToken: accessToken);
  }

  /// Envoie un objet JSON à une route PATCH pour modifier une partie d’une ressource.
  Future<dynamic> postPatch(
    String endpoint,
    Map<String, dynamic> data, {
    String? accessToken,
  }) async {
    return _request('PATCH', endpoint, data: data, accessToken: accessToken);
  }

  /// Exécute une requête HTTP, décode sa réponse (Map ou List) et gère les erreurs API.
  Future<dynamic> _request(
    String method,
    String endpoint, {
    Map<String, dynamic>? data,
    String? accessToken,
  }) async {
    // Supprime les séparateurs en trop pour éviter une URL avec `//`.
    final normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');
    final request = http.Request(
      method,
      Uri.parse('$normalizedBase/$normalizedEndpoint'),
    );

    // Accepte uniquement du JSON et ajoute le jeton JWT sur les routes privées.
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

    // Les réponses de l’API peuvent être vides, des objets ou des listes JSON.
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

    // Retourne le corps décodé pour tous les codes HTTP de succès.
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (responseBody == null) {
        return <String, dynamic>{};
      }
      if (responseBody is Map<String, dynamic> || responseBody is List) {
        return responseBody;
      }
      throw const FormatException(
        'Le format de la réponse du serveur est invalide.',
      );
    }

    // Traduit les erreurs JSON de Django REST en message exploitable par l’interface.
    throw ApiException(
      _errorMessage(responseBody, response.statusCode),
      statusCode: response.statusCode,
    );
  }

  /// Extrait un message lisible des réponses d’erreur de Django REST Framework (DRF) et SimpleJWT.
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

  /// Aplatit récursivement les listes et objets de validation renvoyés par Django.
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
