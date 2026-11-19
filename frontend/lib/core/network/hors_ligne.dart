/// Mode hors ligne de SGSUS.
///
/// Principe : chaque lecture réussie de l'API (requête GET) est mémorisée
/// sur l'appareil avec son heure. Si le serveur ne peut plus être joint
/// (pas de réseau, serveur en veille ou arrêté), [ApiService] renvoie la
/// dernière réponse mémorisée au lieu d'une erreur, et l'interface affiche
/// le bandeau « Mode hors ligne » grâce à [HorsLigne.actif].
///
/// Choix volontaires :
/// * seules les CONSULTATIONS fonctionnent hors ligne (planning, dossier,
///   profil, notes…). Les modifications (créer une soutenance, noter,
///   déposer un rapport) demandent une connexion : les mettre en attente
///   ferait découvrir trop tard un conflit de salle ou de jury refusé par
///   le serveur ;
/// * une page n'est disponible hors ligne qu'après avoir été ouverte au
///   moins une fois avec une connexion, sur cet appareil ;
/// * tout est effacé à la déconnexion, pour qu'un appareil partagé ne
///   garde pas les données du compte précédent.
///
/// Stockage : `SharedPreferences`, c'est-à-dire un fichier privé de
/// l'application sur Android et le `localStorage` du navigateur sur le Web.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Réponse de l'API mémorisée : corps JSON brut et date d'enregistrement.
class ReponseMemorisee {
  /// Crée une réponse mémorisée.
  const ReponseMemorisee(this.corps, this.date);

  /// Corps JSON tel que renvoyé par le serveur.
  final String corps;

  /// Moment où la réponse a été reçue du serveur.
  final DateTime date;
}

/// Stockage des réponses de l'API, remplaçable dans les tests.
abstract interface class CacheReponses {
  /// Retourne la réponse mémorisée pour [cle] (une URL), ou `null`.
  Future<ReponseMemorisee?> lire(String cle);

  /// Mémorise [corps] pour [cle], avec l'heure actuelle.
  Future<void> ecrire(String cle, String corps);

  /// Efface toutes les réponses mémorisées.
  Future<void> vider();
}

/// Cache persistant de l'application (survit à la fermeture de l'appli).
class CachePreferences implements CacheReponses {
  /// Préfixe des clés : sépare le cache des autres préférences.
  static const _prefixe = 'sgsus_cache:';

  /// Accès (mis en cache par le plugin) aux préférences de l'appareil.
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<ReponseMemorisee?> lire(String cle) async {
    final brut = (await _prefs).getString('$_prefixe$cle');
    if (brut == null) return null;
    final donnees = jsonDecode(brut);
    if (donnees is! Map) return null;
    final date = DateTime.tryParse(donnees['date']?.toString() ?? '');
    final corps = donnees['corps'];
    if (date == null || corps is! String) return null;
    return ReponseMemorisee(corps, date);
  }

  @override
  Future<void> ecrire(String cle, String corps) async {
    await (await _prefs).setString(
      '$_prefixe$cle',
      jsonEncode({'date': DateTime.now().toIso8601String(), 'corps': corps}),
    );
  }

  @override
  Future<void> vider() async {
    final prefs = await _prefs;
    // Copie de la liste : on ne modifie pas l'ensemble pendant son parcours.
    final cles = prefs.getKeys().where((c) => c.startsWith(_prefixe)).toList();
    for (final cle in cles) {
      await prefs.remove(cle);
    }
  }
}

/// Cache en mémoire vive (tests, ou repli si le stockage est indisponible).
class CacheMemoire implements CacheReponses {
  /// Réponses mémorisées, par URL.
  final Map<String, ReponseMemorisee> donnees = {};

  @override
  Future<ReponseMemorisee?> lire(String cle) async => donnees[cle];

  @override
  Future<void> ecrire(String cle, String corps) async {
    donnees[cle] = ReponseMemorisee(corps, DateTime.now());
  }

  @override
  Future<void> vider() async => donnees.clear();
}

/// État global du mode hors ligne, observé par l'interface.
abstract final class HorsLigne {
  /// Vrai quand le serveur est injoignable (bandeau « Mode hors ligne »).
  static final ValueNotifier<bool> actif = ValueNotifier(false);

  /// Date des plus anciennes données mémorisées actuellement affichées.
  static final ValueNotifier<DateTime?> donneesDu = ValueNotifier(null);

  /// Cache utilisé par [ApiService] (remplacé par [CacheMemoire] en test).
  static CacheReponses cache = CachePreferences();

  /// Délai maximal d'une opération sur le stockage : un stockage bloqué
  /// ne doit jamais empêcher l'affichage ni la déconnexion.
  static const delaiStockage = Duration(seconds: 3);

  /// Des données mémorisées le [date] viennent d'être affichées.
  static void signalerCache(DateTime date) {
    final actuelle = donneesDu.value;
    // On garde la plus ancienne : c'est elle qui limite la fraîcheur.
    if (actuelle == null || date.isBefore(actuelle)) donneesDu.value = date;
    actif.value = true;
  }

  /// Le serveur n'a pas pu être joint (sans données de secours).
  static void signalerInjoignable() => actif.value = true;

  /// Le serveur a répondu : retour au fonctionnement normal.
  static void signalerConnecte() {
    actif.value = false;
    donneesDu.value = null;
  }

  /// Efface les données mémorisées (déconnexion).
  ///
  /// Une erreur du stockage n'empêche jamais la déconnexion.
  static Future<void> effacer() async {
    signalerConnecte();
    try {
      await cache.vider().timeout(delaiStockage);
    } catch (_) {
      // Stockage indisponible : rien à effacer.
    }
  }
}
