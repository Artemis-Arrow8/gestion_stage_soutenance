/// Accès aux routes des évaluations de soutenance (`/api/assessments/`).
///
/// Réservé au personnel (administrateur, responsable pédagogique) : le
/// serveur refuse ces routes aux autres rôles.
library;

import '../core/network/api_service.dart';
import '../models/evaluation.dart';

/// Service des notes et validations de soutenance.
class EvaluationService {
  /// Crée le service à partir du client HTTP authentifié [api].
  EvaluationService(this.api);

  /// Client HTTP authentifié partagé.
  final ApiService api;

  /// Liste toutes les évaluations, triées par date de soutenance.
  Future<List<Evaluation>> loadEvaluations() async {
    return (await api.getList('assessments/'))
        .map(Evaluation.fromJson)
        .toList();
  }

  /// Crée l'évaluation de la soutenance [defenseId].
  ///
  /// Si la moyenne n'est pas transmise, le serveur la calcule
  /// automatiquement à partir des notes de rapport et d'oral.
  Future<Evaluation> createEvaluation({
    required int defenseId,
    required double reportGrade,
    required double oralGrade,
    required bool isApproved,
  }) async {
    final data = await api.post('assessments/', {
      'defense': defenseId,
      'report_grade': reportGrade.toStringAsFixed(2),
      'oral_grade': oralGrade.toStringAsFixed(2),
      'is_approved': isApproved,
    });
    return Evaluation.fromJson(ApiService.requireObject(data));
  }

  /// Modifie les notes et la validation de l'évaluation [id].
  ///
  /// La moyenne est recalculée par le serveur à partir des nouvelles notes.
  Future<Evaluation> updateEvaluation(
    int id, {
    required double reportGrade,
    required double oralGrade,
    required bool isApproved,
  }) async {
    // La moyenne n'est pas envoyée : le serveur la recalcule à partir des
    // deux notes, ce qui évite toute incohérence.
    final data = await api.patch('assessments/$id/', {
      'report_grade': reportGrade.toStringAsFixed(2),
      'oral_grade': oralGrade.toStringAsFixed(2),
      'is_approved': isApproved,
    });
    return Evaluation.fromJson(ApiService.requireObject(data));
  }
}
