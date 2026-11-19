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
          // La moyenne et l'approbation sont décidées par le serveur.
          expect(corps.containsKey('final_average'), isFalse);
          expect(corps.containsKey('is_approved'), isFalse);
          return http.Response(
            jsonEncode({
              'id': 2,
              'defense': 4,
              'final_average': '15.20',
              'grille': {'poids_rapport': '0.400', 'poids_oral': '0.600'},
            }),
            201,
          );
        }),
      );

      final creee = await service.createEvaluation(
        defenseId: 4,
        reportGrade: 14,
        oralGrade: 16,
      );

      // Grille fictive 40/60 : 0,4 × 14 + 0,6 × 16 = 15,20 (STA10).
      expect(creee.finalAverage, 15.2);
      expect(creee.apercuMoyenne(14, 16), closeTo(15.2, 1e-9));
      // Une note absente reste absente : pas de moyenne.
      expect(creee.apercuMoyenne(14, null), isNull);
    });

    test('l’approbation envoie une clé d’idempotence', () async {
      final service = EvaluationService(
        _api((request) async {
          expect(request.url.path, '/api/assessments/2/approuver/');
          expect(request.headers['Idempotency-Key'], 'cle-de-test');
          return http.Response(jsonEncode({'version': 1, 'statut': 'approuve'}), 201);
        }),
      );

      final pv = await service.approuver(2, cle: 'cle-de-test');
      expect(pv['version'], 1);
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

    test('le responsable refuse un dossier avec un motif (transition)', () async {
      final service = DocumentService(
        _api((request) async {
          // Le statut ne se modifie jamais directement : action dédiée.
          expect(request.method, 'POST');
          expect(request.url.path, '/api/internship-folders/3/refuser/');
          expect(jsonDecode(request.body), {'motif': 'Pièces manquantes'});
          return http.Response(jsonEncode({'id': 3, 'status': 'rejete'}), 200);
        }),
      );

      final dossier = await service.transition(3, 'refuser', motif: 'Pièces manquantes');
      expect(dossier['status'], 'rejete');
    });

    test('le personnel confirme puis supprime une soutenance', () async {
      final appels = <String>[];
      final service = PlanningService(
        _api((request) async {
          appels.add('${request.method} ${request.url.path}');
          if (request.method == 'DELETE') return http.Response('', 204);
          return http.Response(jsonEncode({'id': 7}), 200);
        }),
      );

      // Le statut change par des actions dédiées, jamais par PATCH.
      await service.confirmer(7);
      await service.deleteDefense(7);

      expect(appels, [
        'POST /api/soutenances/7/confirmer/',
        'DELETE /api/soutenances/7/',
      ]);
    });
  });

  group('Libellés et navigation', () {
    test('les statuts techniques ont un libellé français', () {
      expect(libelleStatut('planifie'), 'Proposée');
      expect(libelleStatut('a_corriger'), 'À corriger');
      expect(libelleStatut('publie'), 'Publiée');
      expect(libelleStatut('recevable'), 'Recevable');
      expect(libelleStatut('rejete'), 'Rejeté');
      // Statut inconnu : affiché avec une majuscule.
      expect(libelleStatut('special'), 'Special');
    });

    test('les nouveaux modules sont accessibles aux bons rôles', () {
      expect(Session.sections('admin'), contains(AppSection.evaluations));
      expect(Session.sections('responsible'), contains(AppSection.evaluations));
      expect(Session.sections('student'), isNot(contains(AppSection.evaluations)));
      // Le jury saisit les notes des soutenances de son jury.
      expect(Session.sections('jury'), contains(AppSection.evaluations));
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
