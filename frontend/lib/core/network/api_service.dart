/// Client HTTP centralisé de l'application SGSUS.
///
/// Toutes les communications avec l'API Django passent par [ApiService] :
/// construction des URL, en-têtes JSON, jeton JWT, renouvellement
/// automatique du jeton après une réponse 401, délai d'expiration,
/// décodage UTF-8, traduction des erreurs en messages lisibles et mode
/// hors ligne (dernières lectures mémorisées, voir `hors_ligne.dart`).
///
/// Les services métier (planning, administration, documents…) ne
/// manipulent donc jamais `http` directement : ils décrivent seulement
/// la route appelée et la forme des données attendues.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'hors_ligne.dart';

/// Erreur renvoyée par l'API (ou impossibilité de la joindre).
///
/// [message] est directement affichable à l'utilisateur ; [statusCode]
/// vaut `null` lorsque le serveur n'a pas pu être contacté.
class ApiException implements Exception {
  /// Crée une erreur API avec son message et, si connu, son code HTTP.
  const ApiException(this.message, {this.statusCode});

  /// Message lisible, en français.
  final String message;

  /// Code HTTP de la réponse, ou `null` en cas d'erreur réseau.
  final int? statusCode;

  /// Vrai si le serveur a refusé l'authentification (jeton absent/expiré).
  bool get isUnauthorized => statusCode == 401;

  /// Vrai pour un refus par une règle métier (HTTP 409, ex. créneau déjà
  /// pris, note déjà approuvée, étape sautée).
  bool get isConflit => statusCode == 409;

  /// Vrai si le serveur n'a pas pu répondre : pas de réseau, délai dépassé
  /// ou passerelle en erreur (serveur Render en veille ou arrêté). Une
  /// lecture peut alors se replier sur les données mémorisées.
  bool get serveurInjoignable =>
      statusCode == null ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  @override
  String toString() => message;
}

/// Fonction qui retourne le jeton d'accès courant (ou `null`).
typedef AccessTokenProvider = String? Function();

/// Fonction qui tente de renouveler le jeton d'accès ; retourne `true`
/// si un nouveau jeton est disponible.
typedef AccessTokenRefresher = Future<bool> Function();

/// Client JSON de l'API REST Django.
class ApiService {
  /// Crée un client.
  ///
  /// * [client] : client HTTP injectable (un `MockClient` dans les tests).
  /// * [baseUrl] : URL de l'API ; par défaut [AppConfig.apiBaseUrl].
  /// * [accessTokenProvider] : source du jeton pour les routes protégées.
  /// * [refreshAccessToken] : appelé une fois après un 401 pour renouveler
  ///   le jeton, avant de rejouer la requête.
  /// * [timeout] : délai maximal d'une requête.
  /// * [cache] : réponses mémorisées pour le mode hors ligne ; par défaut
  ///   le cache partagé [HorsLigne.cache].
  ApiService({
    http.Client? client,
    String? baseUrl,
    this.accessTokenProvider,
    this.refreshAccessToken,
    Duration? timeout,
    this.cache,
  }) : _client = client ?? http.Client(),
       _baseUrl = _resoudreAdresse(baseUrl ?? AppConfig.apiBaseUrl),
       _timeout = timeout ?? AppConfig.httpTimeout;

  /// Normalise l'adresse de l'API : sans barre oblique finale et, si elle
  /// est relative (`/api`, version PC), complétée par l'adresse de la page.
  ///
  /// Une adresse relative permet au même site de fonctionner depuis le PC
  /// (`http://localhost:8080`) comme depuis un téléphone du même Wi-Fi
  /// (`http://192.168.x.x:8080`), l'API étant servie à la même adresse.
  static String _resoudreAdresse(String adresse) {
    final propre = adresse.replaceFirst(RegExp(r'/+$'), '');
    if (!propre.startsWith('/')) return propre;
    return Uri.base.resolve(propre).toString();
  }

  /// Cache propre à ce client (tests) ; `null` : cache partagé.
  final CacheReponses? cache;

  /// Cache effectivement utilisé pour le mode hors ligne.
  CacheReponses get _cacheEffectif => cache ?? HorsLigne.cache;

  /// Client HTTP sous-jacent (réel ou simulé).
  final http.Client _client;

  /// URL de base sans barre oblique finale (ex. `https://x.onrender.com/api`).
  final String _baseUrl;

  /// Délai maximal d'attente d'une réponse.
  final Duration _timeout;

  /// Source du jeton d'accès pour les routes protégées.
  final AccessTokenProvider? accessTokenProvider;

  /// Procédure de renouvellement du jeton après une réponse 401.
  final AccessTokenRefresher? refreshAccessToken;

  /// URL de base effectivement utilisée (utile pour les messages d'erreur).
  String get baseUrl => _baseUrl;

  // ---------------------------------------------------------------------
  // Méthodes publiques JSON
  // ---------------------------------------------------------------------

  /// Envoie une requête GET et retourne le JSON décodé (Map ou List).
  ///
  /// [query] ajoute des paramètres d'URL ; [accessToken] force un jeton
  /// précis au lieu de celui du [accessTokenProvider].
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? query,
    String? accessToken,
  }) {
    return _json('GET', endpoint, query: query, accessToken: accessToken);
  }

  /// Envoie un objet JSON en POST et retourne la réponse décodée.
  ///
  /// [idempotencyKey] (en-tête `Idempotency-Key`) identifie une opération
  /// logique : si la réponse se perd et que l'on renvoie la même demande
  /// avec la même clé, le serveur rejoue le résultat sans second effet
  /// (publication du planning, approbation des notes…). Voir
  /// [nouvelleCleIdempotence].
  Future<dynamic> post(
    String endpoint,
    Map<String, dynamic>? data, {
    String? accessToken,
    String? idempotencyKey,
  }) {
    return _json(
      'POST',
      endpoint,
      data: data,
      accessToken: accessToken,
      extraHeaders: idempotencyKey == null
          ? null
          : {'Idempotency-Key': idempotencyKey},
    );
  }

  /// Nouvelle clé d'idempotence aléatoire (32 caractères hexadécimaux),
  /// à générer UNE fois par action de l'utilisateur et à réutiliser pour
  /// une nouvelle tentative de la même action.
  static String nouvelleCleIdempotence() {
    final aleatoire = Random.secure();
    return List.generate(
      16,
      (_) => aleatoire.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Envoie une modification partielle (PATCH) et retourne la réponse décodée.
  Future<dynamic> patch(
    String endpoint,
    Map<String, dynamic> data, {
    String? accessToken,
  }) {
    return _json('PATCH', endpoint, data: data, accessToken: accessToken);
  }

  /// Remplace une ressource (PUT) et retourne la réponse décodée.
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) {
    return _json('PUT', endpoint, data: data);
  }

  /// Supprime une ressource (DELETE).
  Future<void> delete(String endpoint, {String? accessToken}) async {
    await _json('DELETE', endpoint, accessToken: accessToken);
  }

  /// Récupère une liste JSON, en acceptant aussi le format paginé de DRF
  /// (`{"results": [...]}`). Les éléments non-objets sont ignorés.
  ///
  /// Lève une [FormatException] si la réponse n'est pas une liste.
  Future<List<Map<String, dynamic>>> getList(
    String endpoint, {
    Map<String, String>? query,
  }) async {
    final data = await get(endpoint, query: query);
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

  /// Récupère un objet JSON ; lève une [FormatException] sinon.
  Future<Map<String, dynamic>> getObject(
    String endpoint, {
    Map<String, String>? query,
  }) async {
    return requireObject(await get(endpoint, query: query));
  }

  /// Envoie un fichier en `multipart/form-data` (POST).
  ///
  /// [fields] contient les champs texte du formulaire ; le fichier est
  /// transmis sous le nom de champ [fileField].
  Future<dynamic> postMultipart(
    String endpoint, {
    Map<String, String> fields = const {},
    required String fileField,
    required List<int> bytes,
    required String filename,
  }) async {
    final response = await _send((token) {
      final request = http.MultipartRequest('POST', buildUri(endpoint));
      _applyHeaders(request.headers, token: token, json: false);
      request.fields.addAll(fields);
      request.files.add(
        http.MultipartFile.fromBytes(fileField, bytes, filename: filename),
      );
      return request;
    });
    return _decodeSuccess(response);
  }

  /// Télécharge un contenu binaire (ex. un PDF) et retourne ses octets.
  Future<Uint8List> getBytes(String endpoint) async {
    final response = await _send((token) {
      final request = http.Request('GET', buildUri(endpoint));
      _applyHeaders(request.headers, token: token, json: false);
      return request;
    });
    return response.bodyBytes;
  }

  // ---------------------------------------------------------------------
  // Outils partagés
  // ---------------------------------------------------------------------

  /// Construit l'URL complète d'une route de l'API.
  ///
  /// Les barres obliques en double sont évitées (`/api` + `/login/`).
  Uri buildUri(String endpoint, {Map<String, String>? query}) {
    final normalizedEndpoint = endpoint.replaceFirst(RegExp(r'^/+'), '');
    final uri = Uri.parse('$_baseUrl/$normalizedEndpoint');
    return query == null || query.isEmpty
        ? uri
        : uri.replace(queryParameters: query);
  }

  /// Vérifie qu'une réponse est un objet JSON et le retourne typé.
  static Map<String, dynamic> requireObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('Le serveur a renvoyé un objet invalide.');
  }

  // ---------------------------------------------------------------------
  // Implémentation interne
  // ---------------------------------------------------------------------

  /// Exécute une requête JSON complète et retourne le corps décodé.
  ///
  /// Mode hors ligne : une lecture (GET) réussie est mémorisée ; si le
  /// serveur est injoignable, une lecture renvoie la dernière réponse
  /// mémorisée pour la même adresse et l'interface affiche le bandeau
  /// « Mode hors ligne ». Les écritures échouent avec un message clair.
  Future<dynamic> _json(
    String method,
    String endpoint, {
    Map<String, String>? query,
    Map<String, dynamic>? data,
    String? accessToken,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = buildUri(endpoint, query: query);
    final lecture = method == 'GET';
    final http.Response response;
    try {
      response = await _send((token) {
        final request = http.Request(method, uri);
        _applyHeaders(request.headers, token: token, json: data != null);
        if (extraHeaders != null) request.headers.addAll(extraHeaders);
        if (data != null) request.body = jsonEncode(data);
        return request;
      }, accessToken: accessToken);
    } on ApiException catch (error) {
      // Lecture impossible faute de serveur : on cherche une copie locale.
      if (lecture && error.serveurInjoignable) {
        final memo = await _lireCache(uri);
        if (memo != null) {
          HorsLigne.signalerCache(memo.date);
          return _decodeTexte(memo.corps);
        }
      }
      // Aucun réseau : le bandeau « Mode hors ligne » s'affiche.
      if (error.statusCode == null) HorsLigne.signalerInjoignable();
      rethrow;
    }

    // Le serveur a répondu : fin du mode hors ligne éventuel.
    HorsLigne.signalerConnecte();
    final texte = response.bodyBytes.isEmpty ? '' : _bodyText(response);
    final resultat = _decodeTexte(texte);
    // Mémorisation sans attendre : l'affichage n'est pas ralenti.
    if (lecture && texte.isNotEmpty) unawaited(_ecrireCache(uri, texte));
    return resultat;
  }

  /// Lit la copie locale d'une réponse ; `null` si absente ou illisible.
  Future<ReponseMemorisee?> _lireCache(Uri uri) async {
    try {
      return await _cacheEffectif
          .lire(uri.toString())
          .timeout(HorsLigne.delaiStockage);
    } catch (_) {
      return null;
    }
  }

  /// Mémorise une réponse ; une erreur de stockage (espace plein,
  /// navigation privée…) est ignorée : le mode hors ligne est un bonus.
  Future<void> _ecrireCache(Uri uri, String texte) async {
    try {
      await _cacheEffectif
          .ecrire(uri.toString(), texte)
          .timeout(HorsLigne.delaiStockage);
    } catch (_) {
      // Rien à faire : la réponse a déjà été transmise à l'écran.
    }
  }

  /// Ajoute les en-têtes communs : format JSON et jeton Bearer éventuel.
  void _applyHeaders(
    Map<String, String> headers, {
    required String? token,
    required bool json,
  }) {
    headers['Accept'] = 'application/json';
    if (json) headers['Content-Type'] = 'application/json; charset=utf-8';
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
  }

  /// Envoie une requête, la rejoue une fois après renouvellement du jeton
  /// si le serveur répond 401, puis lève une [ApiException] si le code HTTP
  /// n'est pas un succès (2xx).
  ///
  /// [build] reconstruit la requête à chaque tentative (une requête `http`
  /// ne peut pas être envoyée deux fois).
  Future<http.Response> _send(
    http.BaseRequest Function(String? token) build, {
    String? accessToken,
  }) async {
    // Un jeton explicite est prioritaire ; sinon on interroge le fournisseur.
    final usesProvider = accessToken == null;
    var response = await _transmit(
      build(accessToken ?? accessTokenProvider?.call()),
    );

    // Jeton expiré : on tente un renouvellement unique puis on rejoue.
    final refresh = refreshAccessToken;
    if (response.statusCode == 401 &&
        usesProvider &&
        refresh != null &&
        await refresh()) {
      response = await _transmit(build(accessTokenProvider?.call()));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _errorMessage(_tryDecode(response), response.statusCode),
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  /// Transmet une requête avec délai d'expiration et traduit les erreurs
  /// réseau (serveur éteint, CORS refusé, DNS…) en [ApiException].
  Future<http.Response> _transmit(http.BaseRequest request) async {
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'Le serveur ne répond pas. Il est peut-être en cours de démarrage : '
        'réessayez dans quelques instants.',
      );
    } on http.ClientException catch (error) {
      // Pas de réseau, serveur arrêté, ou (sur le Web) refus CORS. Le
      // détail technique n'est affiché qu'en mode développement.
      throw ApiException(
        'Connexion au serveur impossible : vous êtes peut-être hors ligne. '
        'Vérifiez votre connexion Internet puis réessayez.'
        '${kDebugMode ? ' ($_baseUrl : ${error.message})' : ''}',
      );
    }
  }

  /// Retourne le texte d'une réponse.
  ///
  /// UTF-8 est essayé en premier : les accents français restent intacts
  /// même si le serveur n'indique pas de « charset » (cas de Django REST).
  /// Si les octets ne sont pas de l'UTF-8 valide, on se replie sur
  /// l'encodage déclaré par l'en-tête (latin-1 par défaut).
  String _bodyText(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } on FormatException {
      return response.body;
    }
  }

  /// Décode le corps d'une réponse réussie : objet, liste ou objet vide.
  dynamic _decodeSuccess(http.Response response) {
    return _decodeTexte(
      response.bodyBytes.isEmpty ? '' : _bodyText(response),
    );
  }

  /// Décode un corps JSON (reçu ou mémorisé) : objet, liste ou objet vide.
  dynamic _decodeTexte(String texte) {
    if (texte.isEmpty) return <String, dynamic>{};
    final dynamic body;
    try {
      body = jsonDecode(texte);
    } on FormatException {
      throw const FormatException(
        'Le serveur a renvoyé une réponse JSON invalide.',
      );
    }
    if (body is Map<String, dynamic> || body is List) return body;
    throw const FormatException(
      'Le format de la réponse du serveur est invalide.',
    );
  }

  /// Tente de décoder le corps d'une réponse d'erreur (sinon `null`).
  dynamic _tryDecode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(_bodyText(response));
    } on FormatException {
      // Page HTML d'erreur d'un proxy, texte brut… : pas de JSON exploitable.
      return null;
    }
  }

  /// Extrait un message lisible des erreurs de Django REST Framework et
  /// de SimpleJWT, avec un repli selon le code HTTP.
  String _errorMessage(dynamic body, int statusCode) {
    if (body is Map) {
      // Conflit métier (409) : {code, regle, message, request_id, details}.
      // On affiche le message et, s'il y en a, la liste des problèmes
      // (publication refusée), avec la référence de la requête.
      final messageMetier = body['message'];
      if (messageMetier is String && messageMetier.isNotEmpty) {
        final details = body['details'];
        final problemes = details is Map && details['problemes'] is List
            ? (details['problemes'] as List).map((p) => '• $p').join('\n')
            : '';
        final reference = body['request_id'];
        return [
          messageMetier,
          if (problemes.isNotEmpty) problemes,
          if (reference is String && reference != '-') '(Réf. $reference)',
        ].join('\n');
      }
      // Clés prioritaires utilisées par l'API et par DRF.
      for (final key in const ['error', 'detail', 'non_field_errors']) {
        final message = _flatten(body[key]);
        if (message.isNotEmpty) return message;
      }
      // Erreurs de validation par champ : {"champ": ["message"]}.
      final messages = body.values
          .map(_flatten)
          .where((message) => message.isNotEmpty)
          .toList();
      if (messages.isNotEmpty) return messages.join(' ');
    } else {
      final message = _flatten(body);
      if (message.isNotEmpty) return message;
    }
    return switch (statusCode) {
      401 => 'Votre session a expiré. Veuillez vous reconnecter.',
      403 => 'Vous n’avez pas les droits nécessaires pour cette action.',
      404 => 'La ressource demandée est introuvable.',
      502 || 503 || 504 =>
        'Le serveur est momentanément indisponible. Réessayez dans quelques instants.',
      _ => 'Le serveur a répondu avec le code HTTP $statusCode.',
    };
  }

  /// Aplatit récursivement listes et objets de validation en une phrase.
  String _flatten(dynamic value) {
    if (value is String) return value;
    if (value is List) {
      return value.map(_flatten).where((item) => item.isNotEmpty).join(' ');
    }
    if (value is Map) {
      return value.values
          .map(_flatten)
          .where((item) => item.isNotEmpty)
          .join(' ');
    }
    return '';
  }
}
