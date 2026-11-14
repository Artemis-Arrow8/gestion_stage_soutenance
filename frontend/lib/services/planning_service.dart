import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/defense.dart';
import 'api_service.dart';

/// Centralise l’accès REST au planning et aux référentiels nécessaires.
class PlanningService {
  PlanningService({
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

  Uri _url(String path) {
    final base = ApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final endpoint = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$endpoint');
  }

  Future<List<Defense>> loadDefenses() async {
    final data = await _getObject('soutenances/planning/');
    final items = data['soutenances'];
    if (items is! List) {
      throw const FormatException('Le serveur a renvoyé un planning invalide.');
    }
    return items
        .whereType<Map>()
        .map((item) => Defense.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<dynamic>> loadRooms() => _getList('salles/');

  Future<List<dynamic>> loadJuries() => _getList('jurys/');

  Future<List<dynamic>> loadFolders() => _getList('internship-folders/');

  Future<Map<String, dynamic>> createDefense({
    required int folderId,
    required int juryId,
    required String roomName,
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _send(
      'POST',
      'soutenances/',
      body: {
        'folder': folderId,
        'jury': juryId,
        'room_name': roomName,
        'slot_start': start.toUtc().toIso8601String(),
        'slot_end': end.toUtc().toIso8601String(),
        'status': 'planifie',
      },
    );
    return _decodeObject(response);
  }

  Future<List<dynamic>> _getList(String path) async {
    final response = await _send('GET', path);
    final data = _decode(response);
    if (data is List) return data;
    if (data is Map && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    throw const FormatException('Le serveur a renvoyé une liste invalide.');
  }

  Future<Map<String, dynamic>> _getObject(String path) async {
    return _decodeObject(await _send('GET', path));
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
      if (method == 'POST') {
        return _client.post(
          _url(path),
          headers: headers,
          body: jsonEncode(body),
        );
      }
      return _client.get(_url(path), headers: headers);
    }

    var response = await send(_accessTokenProvider());
    final refresh = refreshAccessToken;
    if (response.statusCode == 401 &&
        refresh != null &&
        await refresh()) {
      response = await send(_accessTokenProvider());
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

  Map<String, dynamic> _decodeObject(http.Response response) {
    final data = _decode(response);
    if (data is Map<String, dynamic>) return data;
    throw const FormatException('Le serveur a renvoyé un objet invalide.');
  }

  ApiException _apiError(http.Response response) {
    var message = 'Erreur HTTP ${response.statusCode}.';
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        final values = data.values.map((value) {
          if (value is String) return value;
          if (value is List) return value.join(' ');
          return '';
        }).where((value) => value.isNotEmpty);
        final joined = values.join(' ');
        if (joined.isNotEmpty) message = joined;
      }
    } on FormatException {
      if (response.body.isNotEmpty) message = response.body;
    }
    return ApiException(message, statusCode: response.statusCode);
  }
}
