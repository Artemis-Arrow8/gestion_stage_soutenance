/// Accès aux routes des évaluations de soutenance (`/api/assessments/`), F06.
///
/// * le personnel voit toutes les évaluations ; un membre du jury, celles
///   des soutenances de son jury (filtré par le serveur) ;
/// * la moyenne est TOUJOURS calculée par le serveur selon la grille de la
///   campagne (règle fictive de démonstration : rapport 40 %, oral 60 %) ;
/// * l'approbation (personnel ou président du jury) produit un
///   procès-verbal ; une note approuvée ne se corrige que par une
///   rectification motivée (responsable), qui crée une nouvelle version.
library;

import '../core/network/api_service.dart';
import '../models/evaluation.dart';

/// Service des notes, approbations et procès-verbaux.
class EvaluationService {
  /// Crée le service à partir du client HTTP authentifié [api].
  EvaluationService(this.api);

  /// Client HTTP authentifié partagé.
  final ApiService api;

  /// Liste les évaluations visibles, triées par date de soutenance.
  Future<List<Evaluation>> loadEvaluations() async {
    return (await api.getList('assessments/')).map(Evaluation.fromJson).toList();
  }

  /// Crée l'évaluation de la soutenance [defenseId]. Une note laissée vide
  /// ([reportGrade] ou [oralGrade] null) reste absente : jamais de zéro.
  Future<Evaluation> createEvaluation({
    required int defenseId,
    required double? reportGrade,
    required double? oralGrade,
  }) async {
    final data = await api.post('assessments/', {
      'defense': defenseId,
      'report_grade': reportGrade?.toStringAsFixed(2),
      'oral_grade': oralGrade?.toStringAsFixed(2),
    });
    return Evaluation.fromJson(ApiService.requireObject(data));
  }

  /// Modifie les notes d'une évaluation NON approuvée (sinon refus 409).
  Future<Evaluation> updateEvaluation(
    int id, {
    required double? reportGrade,
    required double? oralGrade,
  }) async {
    final data = await api.patch('assessments/$id/', {
      'report_grade': reportGrade?.toStringAsFixed(2),
      'oral_grade': oralGrade?.toStringAsFixed(2),
    });
    return Evaluation.fromJson(ApiService.requireObject(data));
  }

  /// Approuve les notes (notes complètes et jury complet exigés) et
  /// produit la version 1 du procès-verbal. [cle] : clé d'idempotence.
  Future<Map<String, dynamic>> approuver(int id, {required String cle}) async {
    final data = await api.post('assessments/$id/approuver/', null, idempotencyKey: cle);
    return ApiService.requireObject(data);
  }

  /// Rectifie une note approuvée avec un [motif] : nouvelle version du
  /// procès-verbal, l'ancienne reste consultable.
  Future<Map<String, dynamic>> rectifier(
    int id, {
    required double reportGrade,
    required double oralGrade,
    required String motif,
    required String cle,
  }) async {
    final data = await api.post(
      'assessments/$id/rectifier/',
      {
        'report_grade': reportGrade.toStringAsFixed(2),
        'oral_grade': oralGrade.toStringAsFixed(2),
        'motif': motif,
      },
      idempotencyKey: cle,
    );
    return ApiService.requireObject(data);
  }

  /// Toutes les versions du procès-verbal (de la plus ancienne à la plus récente).
  Future<List<Map<String, dynamic>>> procesVerbaux(int id) =>
      api.getList('assessments/$id/proces-verbaux/');
}
