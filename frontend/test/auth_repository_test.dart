import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/repositories/auth_repository.dart';
import 'package:gestion_stage_soutenance/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'la connexion envoie le contrat Django et retourne les jetons',
    () async {
      final service = ApiService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/login/');
          expect(jsonDecode(request.body), {
            'username': 'ETU_TEST',
            'password': 'mot-de-passe-test',
          });

          return http.Response(
            jsonEncode({
              'access': 'jeton-acces-test',
              'refresh': 'jeton-refresh-test',
              'user': {'username': 'ETU_TEST', 'role': 'student'},
            }),
            200,
          );
        }),
      );
      final repository = AuthRepository(apiService: service);

      final response = await repository.login('ETU_TEST', 'mot-de-passe-test');

      expect(response['access'], 'jeton-acces-test');
      expect(response['refresh'], 'jeton-refresh-test');
      expect((response['user'] as Map<String, dynamic>)['role'], 'student');
    },
  );

  test(
    'la connexion rejette une réponse qui n’est pas un objet JSON',
    () async {
      final service = ApiService(
        client: MockClient(
          (_) async => http.Response(jsonEncode(['réponse-inattendue']), 200),
        ),
      );
      final repository = AuthRepository(apiService: service);

      await expectLater(
        repository.login('ETU_TEST', 'mot-de-passe-test'),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
