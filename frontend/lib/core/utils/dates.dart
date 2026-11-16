/// Fonctions utilitaires de manipulation et de formatage des dates.
///
/// Les dates de soutenance circulent dans l'application sous forme de
/// chaînes `AAAA-MM-JJ` et les heures sous forme `HH:MM` (voir le modèle
/// `Defense`). Ces fonctions assurent les conversions et l'affichage en
/// français, sans dépendre d'un paquet d'internationalisation.
library;

import 'package:material_ui/material_ui.dart';

/// Convertit une date `AAAA-MM-JJ` en [DateTime] local (minuit).
///
/// Retourne `null` si la chaîne est vide ou mal formée.
DateTime? parseDefenseDate(String value) {
  try {
    final p = value.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  } catch (_) {
    // Format inattendu : l'appelant affichera « date invalide ».
    return null;
  }
}

/// Formate une date au format ISO `AAAA-MM-JJ`.
String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Formate une heure de [TimeOfDay] au format `HH:MM`.
String hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Formate une date au format français court `JJ/MM/AAAA`.
String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Retourne l'année universitaire d'une date (ex. `2026/2027`).
///
/// L'année universitaire commence en septembre.
String anneeScolaire(DateTime d) =>
    d.month >= 9 ? '${d.year}/${d.year + 1}' : '${d.year - 1}/${d.year}';

/// Indique si deux dates tombent le même jour calendaire.
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Abréviations des jours, du lundi (index 0) au dimanche.
const joursCourts = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Noms complets des jours, du lundi (index 0) au dimanche.
const joursLongs = [
  'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche',
];

/// Noms complets des mois, de janvier (index 0) à décembre.
const moisLongs = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];

/// Formate une date en toutes lettres (ex. `Lundi 10 juillet 2026`).
String longDate(DateTime d) =>
    '${joursLongs[d.weekday - 1]} ${d.day} '
    '${moisLongs[d.month - 1].toLowerCase()} ${d.year}';

/// Calcule les initiales d'un nom (ex. « Awa Traoré » → « AT »).
///
/// Retourne `?` pour un nom vide ; une seule lettre pour un nom simple.
String initiales(String nom) {
  final parts = nom.split(' ').where((e) => e.trim().isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  // `characters` gère correctement les lettres accentuées composées.
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}
