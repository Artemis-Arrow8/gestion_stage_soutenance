/// Tests des modules ajoutés : évaluations, création de dossier, statuts
/// des dossiers et soutenances, changement de mot de passe, libellés.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/core/network/api_service.dart';
import 'package:gestion_stage_soutenance/models/evaluation.dart';
import 'package:gestion_stage_soutenance/services/document_service.dart';
import 'package:gestion_stage_soutenance/services/evaluation_service.dart';
import 'package:gestion_stage_soutenance/services/planning_service.dart';
import 'package:gestion_stage_soutenance/widgets/app_shell.dart';
import 'package:gestion_stage_soutenance/widgets/ui_kit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Client API branché sur un faux serveur [handler], avec un jeton fixe.
ApiService _api(MockClientHandler handler) => ApiService(
  client: MockClient(handler),
  accessTokenProvider: () => 'jeton-test',
);

void main() {
  group('Évaluations', () {
    test('charge les évaluations et convertit les notes', () async {
      final service = EvaluationService(
        _api((request) async {
          expect(request.url.path, '/api/assessments/');
          return http.Response(
            jsonEncode([
              {
                'id': 1,
                'defense': 9,
                'student_name': 'Rokia Dembélé',
                'subject': 'Tableau de bord',
                'jury_name': 'Jury Informatique C',
                'defense_start': '2026-11-12T09:00:00+00:00',
                'report_grade': '15.50',
                'oral_grade': '16.00',
                'final_average': '15.75',
                'is_approved': true,
              },
            ]),
            200,
          );
        }),
      );

      final evaluation = (await service.loadEvaluations()).single;

      expect(evaluation.defenseId, 9);
      expect(evaluation.finalAverage, 15.75);
      expect(evaluation.isApproved, isTrue);
      expect(formatNote(evaluation.finalAverage), '15,75 / 20');
    });

    test('crée une évaluation sans imposer la moyenne', () async {
      final service = EvaluationService(
        _api((request) async {
          expect(request.method, 'POST');
          final corps = jsonDecode(request.body) as Map<String, dynamic>;
          expect(corps['defense'], 4);
          expect(corps['report_grade'], '14.00');
          // La moyenne est calculée par le serveur.
          expect(corps.containsKey('final_average'), isFalse);
          return http.Response(
            jsonEncode({'id': 2, 'defense': 4, 'final_average': '15.00'}),
            201,
          );
        }),
      );

      final creee = await service.createEvaluation(
        defenseId: 4,
        reportGrade: 14,
        oralGrade: 16,
        isApproved: false,
      );

      expect(creee.finalAverage, 15);
    });

    test('formatNote affiche un tiret pour une note absente', () {
      expect(formatNote(null), '—');
      expect(formatNote(12), '12 / 20');
    });
  });

  group('Dossiers et soutenances', () {
    test('l’étudiant crée son dossier sans identifiant de campagne', () async {
      final service = DocumentService(
        _api((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/internship-folders/');
          expect(jsonDecode(request.body), {
            'company_name': 'Sahel Énergie',
            'subject': 'Supervision solaire',
          });
          return http.Response(jsonEncode({'id': 3, 'status': 'brouillon'}), 201);
        }),
      );

      final dossier = await service.createFolder(
        companyName: 'Sahel Énergie',
        subject: 'Supervision solaire',
      );

      expect(dossier['status'], 'brouillon');
    });

    test('le personnel change le statut d’un dossier', () async {
      final service = DocumentService(
        _api((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/internship-folders/3/');
          expect(jsonDecode(request.body), {'status': 'recevable'});
          return http.Response(jsonEncode({'id': 3, 'status': 'recevable'}), 200);
        }),
      );

      await service.setFolderStatus(3, 'recevable');
    });

    test('le personnel confirme puis supprime une soutenance', () async {
      final appels = <String>[];
      final service = PlanningService(
        _api((request) async {
          appels.add('${request.method} ${request.url.path}');
          if (request.method == 'DELETE') return http.Response('', 204);
          expect(jsonDecode(request.body), {'status': 'confirme'});
          return http.Response(jsonEncode({'id': 7}), 200);
        }),
      );

      await service.updateDefenseStatus(7, 'confirme');
      await service.deleteDefense(7);

      expect(appels, ['PATCH /api/soutenances/7/', 'DELETE /api/soutenances/7/']);
    });
  });

  group('Libellés et navigation', () {
    test('les statuts techniques ont un libellé français', () {
      expect(libelleStatut('planifie'), 'Planifiée');
      expect(libelleStatut('recevable'), 'Recevable');
      expect(libelleStatut('rejete'), 'Rejeté');
      // Statut inconnu : affiché avec une majuscule.
      expect(libelleStatut('special'), 'Special');
    });

    test('les nouveaux modules sont accessibles aux bons rôles', () {
      expect(Session.sections('admin'), contains(AppSection.evaluations));
      expect(Session.sections('responsible'), contains(AppSection.evaluations));
      expect(Session.sections('student'), isNot(contains(AppSection.evaluations)));
      for (final role in ['admin', 'responsible', 'supervisor', 'jury', 'student']) {
        expect(Session.sections(role), contains(AppSection.profil));
      }
    });
  });

  test('le changement de mot de passe appelle la bonne route', () async {
    final api = _api((request) async {
      expect(request.url.path, '/api/profile/password/');
      expect(jsonDecode(request.body), {
        'old_password': 'ancien',
        'new_password': 'Nouveau-2026',
      });
      return http.Response(jsonEncode({'message': 'ok'}), 200);
    });

    await api.post('profile/password/', {
      'old_password': 'ancien',
      'new_password': 'Nouveau-2026',
    });
  });
}
