import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/administration.dart';
import 'api_service.dart';

/// Centralise les appels authentifiés des écrans d'administration.
class AdministrationService {
  AdministrationService({
    required this.accessToken,
    String? Function()? accessTokenProvider,
    this.refreshAccessToken,
    http.Client? client,
  }) : _accessTokenProvider = accessTokenProvider ?? (() => accessToken),
       _client = client ?? http.Client();

  final String? accessToken;
  final String? Function() _accessTokenProvider;
  final Future<bool> Function()? refreshAccessToken;
  final http.Client _client;

  Uri _url(String path) {
    final base = ApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final endpoint = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$endpoint');
  }

  Future<List<CampaignRecord>> loadCampaigns() async {
    return (await _getList('campaigns/')).map(CampaignRecord.fromJson).toList();
  }

  Future<List<AccountRecord>> loadAccounts() async {
    return (await _getList('accounts/')).map(AccountRecord.fromJson).toList();
  }

  Future<List<StudentOption>> loadStudents() async {
    return (await _getList('students/')).map(StudentOption.fromJson).toList();
  }

  Future<List<JuryMemberOption>> loadJuryMembers() async {
    return (await _getList('jury-members/'))
        .map(JuryMemberOption.fromJson)
        .toList();
  }

  Future<CampaignRecord> createCampaign({
    required String academicYear,
    required bool isActive,
  }) async {
    return CampaignRecord.fromJson(
      await _sendObject(
        'POST',
        'campaigns/',
        body: {'academic_year': academicYear, 'is_active': isActive},
      ),
    );
  }

  Future<CampaignRecord> updateCampaign(
    int id, {
    required String academicYear,
    required bool isActive,
  }) async {
    return CampaignRecord.fromJson(
      await _sendObject(
        'PATCH',
        'campaigns/$id/',
        body: {'academic_year': academicYear, 'is_active': isActive},
      ),
    );
  }

  Future<AccountRecord> createAccount(Map<String, dynamic> account) async {
    return AccountRecord.fromJson(
      await _sendObject('POST', 'accounts/', body: account),
    );
  }

  Future<AccountRecord> updateAccount(
    int id,
    Map<String, dynamic> changes,
  ) async {
    return AccountRecord.fromJson(
      await _sendObject('PATCH', 'accounts/$id/', body: changes),
    );
  }

  Future<StudentOption> createStudent({
    required String studentNumber,
    required String fullName,
    required String email,
  }) async {
    return StudentOption.fromJson(
      await _sendObject(
        'POST',
        'students/',
        body: {
          'student_number': studentNumber,
          'full_name': fullName,
          'email': email,
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final data = _decode(await _send('GET', path));
    final items = data is List
        ? data
        : data is Map && data['results'] is List
        ? data['results'] as List
        : null;
    if (items == null) {
      throw const FormatException('Le serveur a renvoyé une liste invalide.');
    }
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> _sendObject(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final data = _decode(await _send(method, path, body: body));
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('Le serveur a renvoyé un objet invalide.');
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    Future<http.Response> send(String? token) {
      final headers = <String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final uri = _url(path);
      final encodedBody = body == null ? null : jsonEncode(body);
      return switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encodedBody),
        'PATCH' => _client.patch(uri, headers: headers, body: encodedBody),
        _ => throw ArgumentError.value(method, 'method', 'Méthode non gérée.'),
      };
    }

    late http.Response response;
    try {
      response = await send(_accessTokenProvider());
      final refresh = refreshAccessToken;
      if (response.statusCode == 401 && refresh != null && await refresh()) {
        response = await send(_accessTokenProvider());
      }
    } on http.ClientException catch (error) {
      throw ApiException(
        'Impossible de joindre le serveur API : ${error.message}',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response);
    }
    return response;
  }

  dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const FormatException('Le serveur a renvoyé un JSON invalide.');
    }
  }

  ApiException _apiError(http.Response response) {
    var message = 'Erreur HTTP ${response.statusCode}.';
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final messages = body.values
            .expand((value) => value is List ? value : [value])
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toList();
        if (messages.isNotEmpty) message = messages.join(' ');
      }
    } on FormatException {
      if (response.body.isNotEmpty) message = response.body;
    }
    return ApiException(message, statusCode: response.statusCode);
  }
}
