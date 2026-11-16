/// Tests du service d'administration (campagnes et comptes).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/core/network/api_service.dart';
import 'package:gestion_stage_soutenance/services/administration_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Construit un service branché sur un faux serveur [handler], avec un
/// jeton d'accès fixe.
AdministrationService _service(MockClientHandler handler) {
  return AdministrationService(
    ApiService(
      client: MockClient(handler),
      accessTokenProvider: () => 'jeton-test',
    ),
  );
}

void main() {
  test('charge les campagnes et transmet le jeton d’accès', () async {
    final service = _service((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/campaigns/');
      expect(request.headers['Authorization'], 'Bearer jeton-test');
      return http.Response(
        jsonEncode([
          {'id': 7, 'academic_year': '2026-2027', 'is_active': true},
        ]),
        200,
      );
    });

    final campaigns = await service.loadCampaigns();

    expect(campaigns, hasLength(1));
    expect(campaigns.single.id, 7);
    expect(campaigns.single.academicYear, '2026-2027');
    expect(campaigns.single.isActive, isTrue);
  });

  test('crée un compte avec le rôle et la fiche étudiant associés', () async {
    final service = _service((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/accounts/');
      expect(request.headers['Authorization'], 'Bearer jeton-test');
      expect(jsonDecode(request.body), containsPair('student_id', 23));
      return http.Response(
        jsonEncode({
          'id': 81,
          'username': 'ETU001',
          'email': 'etu@example.test',
          'first_name': 'Awa',
          'last_name': 'Traore',
          'role': 'student',
          'is_active': true,
          'student_profile': {
            'id': 23,
            'student_number': 'ETU001',
            'full_name': 'Awa Traore',
            'email': 'etu@example.test',
          },
          'jury_profile': null,
        }),
        201,
      );
    });

    final account = await service.createAccount({
      'username': 'ETU001',
      'password': 'Strong-Passphrase!2026',
      'role': 'student',
      'student_id': 23,
    });

    expect(account.id, 81);
    expect(account.role, 'student');
    expect(account.studentProfile?['id'], 23);
  });

  test('décode correctement les accents sans « charset » explicite', () async {
    // Le serveur renvoie du JSON UTF-8 sans préciser l'encodage.
    final service = _service(
      (_) async => http.Response.bytes(
        utf8.encode(
          jsonEncode([
            {
              'id': 1,
              'student_number': 'E1',
              'full_name': 'Aïssata Diarra',
              'email': 'a@example.test',
            },
          ]),
        ),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );

    final students = await service.loadStudents();

    expect(students.single.fullName, 'Aïssata Diarra');
  });
}
