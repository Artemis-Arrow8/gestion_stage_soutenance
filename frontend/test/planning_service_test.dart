import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/services/api_service.dart';
import 'package:gestion_stage_soutenance/services/planning_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('charge le planning réel et convertit les champs de soutenance', () async {
    final service = PlanningService(
      accessToken: 'jeton-test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/soutenances/planning/');
        expect(request.headers['Authorization'], 'Bearer jeton-test');
        return http.Response(
          jsonEncode({
            'total': 1,
            'soutenances': [
              {
                'id': 42,
                'folder': 7,
                'jury': 3,
                'student_name': 'Étudiant de test',
                'subject': 'Sujet de test',
                'jury_name': 'Jury A',
                'room_name': 'Salle A',
                'slot_start': '2026-07-10T08:00:00Z',
                'slot_end': '2026-07-10T09:00:00Z',
                'status': 'planifie',
              },
            ],
          }),
          200,
        );
      }),
    );

    final defenses = await service.loadDefenses();

    expect(defenses.single.id, 42);
    expect(defenses.single.folderId, 7);
    expect(defenses.single.juryId, 3);
    expect(defenses.single.studentName, 'Étudiant de test');
    expect(defenses.single.juryName, 'Jury A');
  });

  test('transmet la création au serveur et propage un conflit HTTP 400', () async {
    final service = PlanningService(
      accessToken: 'jeton-test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/soutenances/');
        expect(jsonDecode(request.body), containsPair('folder', 7));
        expect(jsonDecode(request.body), containsPair('jury', 3));
        return http.Response(
          jsonEncode({'detail': 'Conflit de réservation (EXG01).'}),
          400,
        );
      }),
    );

    await expectLater(
      service.createDefense(
        folderId: 7,
        juryId: 3,
        roomName: 'Salle A',
        start: DateTime.utc(2026, 7, 10, 8),
        end: DateTime.utc(2026, 7, 10, 9),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          400,
        ),
      ),
    );
  });
}
