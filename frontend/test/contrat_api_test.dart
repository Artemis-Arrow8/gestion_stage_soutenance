/// Tests du contrat d'erreur de l'API vu par l'application (docs/api.md) :
/// un conflit métier (HTTP 409) arrive sous la forme
/// {code, regle, message, request_id, details} et doit être affiché
/// lisiblement, avec la liste des problèmes et la référence de la requête.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/core/network/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  /// Client dont le serveur simulé répond toujours [reponse].
  ApiService api(http.Response reponse, {void Function(http.Request)? controle}) {
    return ApiService(
      client: MockClient((request) async {
        controle?.call(request);
        return reponse;
      }),
    );
  }

  test('un conflit 409 affiche le message, les problèmes et la référence', () async {
    final service = api(
      http.Response(
        jsonEncode({
          'code': 'BUSINESS_CONFLICT',
          'regle': 'F05',
          'message': 'Publication refusée : corrigez les soutenances signalées.',
          'request_id': 'req-demo-17',
          'details': {
            'problemes': ['Soutenance #4 : dossier non recevable'],
          },
        }),
        409,
      ),
    );

    await expectLater(
      service.post('soutenances/publier/', {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isConflit, 'isConflit', isTrue)
            .having((e) => e.message, 'message', contains('Publication refusée'))
            .having((e) => e.message, 'problème', contains('• Soutenance #4'))
            .having((e) => e.message, 'référence', contains('(Réf. req-demo-17)'))
            // Les champs techniques ne sont pas affichés tels quels.
            .having((e) => e.message, 'code masqué', isNot(contains('BUSINESS_CONFLICT'))),
      ),
    );
  });

  test('la clé d’idempotence n’est envoyée que si elle est fournie', () async {
    final entetes = <Map<String, String>>[];
    final service = api(
      http.Response('{}', 201),
      controle: (request) => entetes.add(request.headers),
    );

    await service.post('soutenances/publier/', {}, idempotencyKey: 'cle-1');
    await service.post('soutenances/publier/', {});

    expect(entetes[0]['Idempotency-Key'], 'cle-1');
    expect(entetes[1].containsKey('Idempotency-Key'), isFalse);
  });

  test('les clés d’idempotence générées sont distinctes et hexadécimales', () {
    final a = ApiService.nouvelleCleIdempotence();
    final b = ApiService.nouvelleCleIdempotence();
    expect(a, hasLength(32));
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
    expect(a, isNot(b));
  });
}
