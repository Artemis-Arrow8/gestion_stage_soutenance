import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/services/document_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('charge les dossiers depuis la route DRF réelle', () async {
    final service = DocumentService(
      accessToken: 'jeton-test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/internship-folders/');
        expect(request.headers['Authorization'], 'Bearer jeton-test');
        return http.Response(jsonEncode([
          {'id': 12, 'company_name': 'Entreprise de test'},
        ]), 200);
      }),
    );

    final folders = await service.getFolders();

    expect(folders.single['id'], 12);
  });

  test('renouvelle le jeton et réessaie une requête après HTTP 401', () async {
    var token = 'jeton-expire';
    var refreshCount = 0;
    final service = DocumentService(
      accessToken: token,
      accessTokenProvider: () => token,
      refreshAccessToken: () async {
        refreshCount++;
        token = 'jeton-renouvele';
        return true;
      },
      client: MockClient((request) async {
        if (request.headers['Authorization'] == 'Bearer jeton-expire') {
          return http.Response('{"detail":"Token expiré"}', 401);
        }
        expect(request.headers['Authorization'], 'Bearer jeton-renouvele');
        return http.Response('[]', 200);
      }),
    );

    expect(await service.getFolders(), isEmpty);
    expect(refreshCount, 1);
  });

  test('filtre les versions par dossier après la route DRF réelle', () async {
    final service = DocumentService(
      accessToken: 'jeton-test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/document-versions/');
        return http.Response(jsonEncode([
          {'id': 1, 'folder': 12},
          {'id': 2, 'folder': 13},
        ]), 200);
      }),
    );

    final documents = await service.getDocuments(12);

    expect(documents.map((document) => document['id']), [1]);
  });

  test('filtre et crée un avis avec la version de document associée', () async {
    final service = DocumentService(
      accessToken: 'jeton-test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/reviews/');
        expect(request.headers['Authorization'], 'Bearer jeton-test');
        if (request.method == 'GET') {
          expect(request.url.queryParameters['document_version_id'], '42');
          return http.Response('[]', 200);
        }

        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'document_version': 42,
          'decision': 'favorable',
          'comments': 'Avis favorable',
        });
        return http.Response(jsonEncode({'id': 8}), 201);
      }),
    );

    expect(await service.getReviews(42), isEmpty);
    final review = await service.addReview(
      42,
      'favorable',
      ' Avis favorable ',
    );

    expect(review['id'], 8);
  });
}
