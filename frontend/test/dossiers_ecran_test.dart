/// Tests de l'écran « Dossiers » sur un téléphone de 360 px : chaque rôle
/// trouve son action depuis l'accueil, sans tâtonner, et chaque décision
/// part au serveur avec les bonnes données.
///
/// Le serveur est simulé ([_Serveur]) : il renvoie un dossier dans l'état
/// voulu et enregistre les écritures reçues.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/app.dart';
import 'package:gestion_stage_soutenance/core/network/api_service.dart';
import 'package:gestion_stage_soutenance/core/storage/auth_storage.dart';
import 'package:gestion_stage_soutenance/providers/auth_provider.dart';
import 'package:gestion_stage_soutenance/providers/planning_store.dart';
import 'package:gestion_stage_soutenance/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUp(PlanningStore.clear);

  testWidgets('encadreur : de l’accueil à « demander des corrections »', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(role: 'supervisor', statut: 'soumis', version: 2);
    await _ouvrir(tester, serveur);

    // L'accueil dit combien de rapports attendent, avec un bouton.
    expect(find.text('1 rapport attend votre avis'), findsOneWidget);
    await _toucher(tester, 'Examiner les rapports');

    // La carte dit qui, où on en est, et propose les 3 bons boutons.
    expect(find.text('Awa Traoré'), findsOneWidget);
    expect(find.text('Votre avis est attendu'), findsOneWidget);
    expect(find.text('Lire le rapport (version 2)'), findsOneWidget);
    expect(find.text('Accepter le rapport'), findsOneWidget);
    expect(find.text('Demander des corrections'), findsOneWidget);
    expect(find.text('Autoriser la soutenance'), findsNothing);

    // Commentaire obligatoire : sans texte, rien ne part.
    await _toucher(tester, 'Demander des corrections');
    await tester.tap(find.text('Envoyer la demande'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Écrivez quelques mots'), findsOneWidget);
    expect(serveur.ecritures, isEmpty);

    await tester.enterText(find.byType(TextField), 'Compléter la bibliographie.');
    await tester.tap(find.text('Envoyer la demande'));
    await tester.pumpAndSettle();

    final (chemin, corps) = serveur.ecritures.single;
    expect(chemin, '/api/reviews/');
    expect(corps['document_version'], 72);
    expect(corps['decision'], 'defavorable');
    expect(corps['comments'], 'Compléter la bibliographie.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsable : « autoriser la soutenance » en deux gestes', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(role: 'responsible', statut: 'valide', version: 1);
    await _ouvrir(tester, serveur);

    expect(find.text('1 dossier attend votre décision'), findsOneWidget);
    await _toucher(tester, '1 dossier attend votre décision');

    expect(find.text('À traiter maintenant (1)'), findsOneWidget);
    expect(find.text('Soutenance à autoriser'), findsOneWidget);
    expect(find.text('Refuser le dossier'), findsOneWidget);

    await _toucher(tester, 'Autoriser la soutenance');
    // La fenêtre dit ce qui va se passer avant d'agir.
    expect(find.text('Autoriser la soutenance ?'), findsOneWidget);
    await tester.tap(find.text('Autoriser'));
    await tester.pumpAndSettle();

    expect(serveur.ecritures.single.$1, '/api/internship-folders/5/autoriser/');
    expect(tester.takeException(), isNull);
  });

  testWidgets('étudiant sans rapport : un seul bouton, « déposer »', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(role: 'student', statut: 'brouillon');
    await _ouvrir(tester, serveur);

    // L'accueil donne la prochaine étape en toutes lettres.
    await _toucher(tester, 'Déposez votre rapport');

    expect(find.text('Mon rapport de stage'), findsOneWidget);
    expect(find.text('Déposer mon rapport (PDF)'), findsOneWidget);
    // Rien à envoyer ni à lire tant qu'aucun rapport n'est déposé.
    expect(find.text('Envoyer à mon encadreur'), findsNothing);
    expect(find.textContaining('Lire le rapport'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Ouvre l'application connectée sur un téléphone de 360 × 800 px.
Future<void> _ouvrir(WidgetTester tester, _Serveur serveur) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final session = AuthProvider(
    authService: AuthService(apiService: ApiService(client: serveur.client)),
    storage: _StockageMemoire(),
    httpClient: serveur.client,
  );
  await session.login('compte', 'secret');
  await tester.pumpWidget(SgsusApp(authProvider: session));
  await tester.pumpAndSettle();
}

/// Fait défiler jusqu'au texte [texte], le touche et attend la fin.
Future<void> _toucher(WidgetTester tester, String texte) async {
  final cible = find.text(texte).first;
  await tester.ensureVisible(cible);
  await tester.pumpAndSettle();
  await tester.tap(cible);
  await tester.pumpAndSettle();
}

/// Faux serveur SGSUS : un seul dossier (n° 5) dans l'état voulu.
class _Serveur {
  _Serveur({required this.role, required this.statut, this.version});

  /// Rôle du compte connecté.
  final String role;

  /// Statut du dossier renvoyé.
  final String statut;

  /// Numéro de la dernière version déposée (`null` : aucun dépôt).
  final int? version;

  /// Écritures reçues : (chemin, corps JSON).
  final List<(String, Map<String, dynamic>)> ecritures = [];

  /// Client HTTP simulé à injecter dans l'application.
  late final http.Client client = MockClient(_repondre);

  Map<String, dynamic> get _profil => {
    'id': 1,
    'username': 'compte',
    'full_name': 'Compte Test',
    'role': role,
    if (role == 'student') ...{
      'folder_status': statut,
      'folder_company': 'Orange Mali',
      'folder_subject': 'Application de suivi',
    },
  };

  Map<String, dynamic> get _dossier => {
    'id': 5,
    'status': statut,
    'student_name': 'Awa Traoré',
    'company_name': 'Orange Mali',
    'subject': 'Application de suivi',
    'confidentialite': 'standard',
    'nombre_versions': version ?? 0,
    'derniere_version': version == null
        ? null
        : {'id': 70 + version!, 'version_number': version, 'uploaded_at': '2026-11-12T10:00:00Z'},
    'dernier_avis': null,
    'derniere_etape': null,
  };

  Future<http.Response> _repondre(http.Request requete) async {
    final chemin = requete.url.path;
    if (requete.method == 'POST' && !chemin.endsWith('/login/')) {
      ecritures.add((chemin, requete.body.isEmpty ? {} : jsonDecode(requete.body) as Map<String, dynamic>));
    }
    final Object? corps = switch (chemin) {
      '/api/login/' => {'access': 'a', 'refresh': 'r', 'user': _profil},
      '/api/profile/' => {'user': _profil},
      '/api/internship-folders/' => [_dossier],
      '/api/reviews/' => {'id': 1, 'decision': 'defavorable'},
      '/api/internship-folders/5/autoriser/' => _dossier,
      '/api/soutenances/planning/' => {'total': 0, 'soutenances': []},
      '/api/salles/' || '/api/jurys/' => [],
      _ => null,
    };
    if (corps == null) return http.Response('{"detail":"Introuvable."}', 404);
    return http.Response(
      jsonEncode(corps),
      requete.method == 'POST' && chemin == '/api/reviews/' ? 201 : 200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

/// Stockage de jetons en mémoire (pas de stockage sécurisé en test).
class _StockageMemoire implements AuthStorage {
  String? _acces;
  String? _renouvellement;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    _acces = accessToken;
    _renouvellement = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _acces;

  @override
  Future<String?> readRefreshToken() async => _renouvellement;

  @override
  Future<void> clearTokens() async {
    _acces = null;
    _renouvellement = null;
  }
}
