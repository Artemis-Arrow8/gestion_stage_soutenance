/// Tests du service d'authentification : contrat de la route de connexion.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/core/network/api_service.dart';
import 'package:gestion_stage_soutenance/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'la connexion envoie le contrat Django et retourne les jetons',
    () async {
      // Faux serveur : vérifie la requête puis renvoie des jetons fictifs.
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
      final authService = AuthService(apiService: service);

      final response = await authService.login('ETU_TEST', 'mot-de-passe-test');

      expect(response['access'], 'jeton-acces-test');
      expect(response['refresh'], 'jeton-refresh-test');
      expect((response['user'] as Map<String, dynamic>)['role'], 'student');
    },
  );

  test(
    'la connexion rejette une réponse qui n’est pas un objet JSON',
    () async {
      // Une liste au lieu d'un objet doit être signalée comme invalide.
      final service = ApiService(
        client: MockClient(
          (_) async => http.Response(jsonEncode(['réponse-inattendue']), 200),
        ),
      );
      final authService = AuthService(apiService: service);

      await expectLater(
        authService.login('ETU_TEST', 'mot-de-passe-test'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('une page d’erreur HTML de proxy donne un message lisible', () async {
    // Cas typique d'un service Render en cours de démarrage (502 HTML).
    final service = ApiService(
      client: MockClient(
        (_) async => http.Response('<html>Bad Gateway</html>', 502),
      ),
    );

    await expectLater(
      AuthService(apiService: service).login('a', 'b'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having(
              (e) => e.message,
              'message',
              contains('momentanément indisponible'),
            ),
      ),
    );
  });
}
