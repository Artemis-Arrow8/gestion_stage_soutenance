/// Modèle d'une évaluation de soutenance (notes sur 20 et approbation).
///
/// Correspond à la ressource `/api/assessments/` de l'API Django. Les
/// notes sont transmises par l'API sous forme de texte décimal (`"15.50"`)
/// et converties ici en nombres. La moyenne est calculée par le serveur
/// selon la grille de la campagne (coefficients [poidsRapport] et
/// [poidsOral]) ; l'application ne fait qu'en afficher un aperçu.
library;

/// Évaluation d'une soutenance.
class Evaluation {
  /// Crée une évaluation.
  const Evaluation({
    required this.id,
    required this.defenseId,
    required this.studentName,
    required this.subject,
    required this.juryName,
    required this.defenseStart,
    required this.reportGrade,
    required this.oralGrade,
    required this.finalAverage,
    required this.isApproved,
    this.poidsRapport = 0.4,
    this.poidsOral = 0.6,
    this.nombreProcesVerbaux = 0,
  });

  /// Identifiant de l'évaluation.
  final int id;

  /// Identifiant de la soutenance évaluée.
  final int defenseId;

  /// Nom de l'étudiant évalué.
  final String studentName;

  /// Sujet du stage.
  final String subject;

  /// Nom du jury.
  final String juryName;

  /// Début de la soutenance (heure locale), ou `null` si inconnu.
  final DateTime? defenseStart;

  /// Note du rapport écrit (sur 20), ou `null` si non saisie.
  final double? reportGrade;

  /// Note de l'oral (sur 20), ou `null` si non saisie.
  final double? oralGrade;

  /// Moyenne finale (sur 20), calculée par le serveur si non saisie.
  final double? finalAverage;

  /// Vrai si la note est approuvée (visible par l'étudiant, figée dans un
  /// procès-verbal ; seule une rectification motivée peut la corriger).
  final bool isApproved;

  /// Coefficient du rapport dans la grille de la campagne (0,4 par défaut).
  final double poidsRapport;

  /// Coefficient de l'oral dans la grille de la campagne (0,6 par défaut).
  final double poidsOral;

  /// Nombre de versions du procès-verbal (rectifications comprises).
  final int nombreProcesVerbaux;

  /// Aperçu de la moyenne pondérée (le serveur fait foi), ou `null` si
  /// une note manque : une note absente n'est jamais comptée comme zéro.
  double? apercuMoyenne(double? rapport, double? oral) =>
      rapport == null || oral == null ? null : poidsRapport * rapport + poidsOral * oral;

  /// Construit une évaluation depuis le JSON de l'API.
  factory Evaluation.fromJson(Map<String, dynamic> json) {
    return Evaluation(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      defenseId: int.tryParse(json['defense']?.toString() ?? '') ?? 0,
      studentName: json['student_name']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '',
      juryName: json['jury_name']?.toString() ?? '',
      defenseStart: DateTime.tryParse(
        json['defense_start']?.toString() ?? '',
      )?.toLocal(),
      reportGrade: _note(json['report_grade']),
      oralGrade: _note(json['oral_grade']),
      finalAverage: _note(json['final_average']),
      isApproved: json['is_approved'] == true,
      poidsRapport: _note((json['grille'] as Map?)?['poids_rapport']) ?? 0.4,
      poidsOral: _note((json['grille'] as Map?)?['poids_oral']) ?? 0.6,
      nombreProcesVerbaux:
          int.tryParse(json['nombre_proces_verbaux']?.toString() ?? '') ?? 0,
    );
  }

  /// Convertit une note JSON (texte ou nombre) en `double`, ou `null`.
  static double? _note(dynamic valeur) =>
      valeur == null ? null : double.tryParse(valeur.toString());
}

/// Formate une note sur 20 pour l'affichage (ex. `15.75` → `15,75 / 20`).
///
/// Retourne `—` si la note est absente.
String formatNote(double? note) {
  if (note == null) return '—';
  // Virgule décimale à la française, zéros inutiles retirés.
  var texte = note.toStringAsFixed(2).replaceAll('.', ',');
  if (texte.endsWith(',00')) texte = texte.substring(0, texte.length - 3);
  return '$texte / 20';
}
