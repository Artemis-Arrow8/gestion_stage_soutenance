/// Tests d'interface de bout en bout (sans serveur réel) : connexion,
/// aiguillage de session, tableau de bord par rôle et déconnexion.
///
/// Le serveur est simulé de deux façons :
/// * [_FakeAuthService] remplace les routes d'authentification ;
/// * un `MockClient` répond aux routes métier appelées par le tableau de
///   bord (planning, salles, jurys).
library;

import 'dart:convert';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/app.dart';
import 'package:gestion_stage_soutenance/core/network/api_service.dart';
import 'package:gestion_stage_soutenance/core/storage/auth_storage.dart';
import 'package:gestion_stage_soutenance/core/utils/dates.dart';
import 'package:gestion_stage_soutenance/providers/auth_provider.dart';
import 'package:gestion_stage_soutenance/providers/planning_store.dart';
import 'package:gestion_stage_soutenance/screens/dashboard_screen.dart';
import 'package:gestion_stage_soutenance/screens/login_screen.dart';
import 'package:gestion_stage_soutenance/services/auth_service.dart';
import 'package:gestion_stage_soutenance/widgets/app_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

/// Plateforme de stockage d'origine, restaurée après chaque test.
late FlutterSecureStoragePlatform _previousPlatform;

/// Contenu du faux stockage sécurisé (clé → valeur).
late Map<String, String> _storageValues;

void main() {
  setUp(() {
    // Stockage sécurisé en mémoire, observable par les tests.
    _previousPlatform = FlutterSecureStoragePlatform.instance;
    _storageValues = {};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      _storageValues,
    );
    // Le magasin de planning est statique : on repart d'un état vierge.
    PlanningStore.clear();
  });

  tearDown(() {
    FlutterSecureStoragePlatform.instance = _previousPlatform;
  });

  test('traduit les erreurs de validation Django REST', () async {
    final service = ApiService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/login/');
        return http.Response(
          jsonEncode({
            'password': ['Ce champ est invalide.'],
          }),
          400,
        );
      }),
    );

    await expectLater(
      service.post('login/', {'username': 'test', 'password': 'faux'}),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Ce champ est invalide.',
        ),
      ),
    );
  });

  test(
    'SecureAuthStorage délègue lecture, écriture et suppression au plugin',
    () async {
      final storage = SecureAuthStorage();

      await storage.saveTokens('access-test', 'refresh-test');

      expect(_storageValues, {
        'sgsus_access_token': 'access-test',
        'sgsus_refresh_token': 'refresh-test',
      });
      expect(await storage.readAccessToken(), 'access-test');
      expect(await storage.readRefreshToken(), 'refresh-test');

      await storage.clearTokens();

      expect(_storageValues, isEmpty);
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
    },
  );

  testWidgets('affiche et valide les champs requis de connexion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(SgsusApp(authProvider: _createProvider()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text("Identifiant fourni par l'établissement"), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Veuillez entrer votre identifiant'), findsOneWidget);
    expect(find.text('Veuillez entrer votre mot de passe'), findsOneWidget);
  });

  testWidgets('affiche le refus de connexion renvoyé par l’API', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      SgsusApp(authProvider: _createProvider(failLogin: true)),
    );
    await tester.pumpAndSettle();

    await _login(tester, 'invalide', 'faux');

    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
  });

  testWidgets('authentifie un étudiant et affiche ses accès rapides', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider();
    await tester.pumpWidget(SgsusApp(authProvider: provider));
    await tester.pumpAndSettle();

    await _login(tester, 'compte', 'secret');

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Bonjour, Compte'), findsOneWidget);
    expect(find.text('Mon dossier et mes documents'), findsOneWidget);
    expect(provider.isAuthenticated, isTrue);
  });

  testWidgets('un encadreur accède à ses dossiers affectés', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider(role: 'supervisor');
    await provider.login('encadreur', 'secret');
    await tester.pumpWidget(SgsusApp(authProvider: provider));
    await tester.pumpAndSettle();

    expect(
      find.text("Dossiers affectés et avis d'encadrement"),
      findsOneWidget,
    );
  });

  testWidgets(
    'un administrateur voit le planning chargé et ses modules de gestion',
    (WidgetTester tester) async {
      final provider = _createProvider(role: 'admin');
      await provider.login('administrateur', 'secret');
      await tester.pumpWidget(SgsusApp(authProvider: provider));
      await tester.pumpAndSettle();

      // Soutenance renvoyée par le faux serveur : visible dans « à venir ».
      expect(find.text('Étudiant planifié'), findsOneWidget);
      expect(find.text('Gestion des campagnes'), findsOneWidget);
      expect(find.text('Comptes et rôles'), findsOneWidget);
      // Règles de navigation par rôle.
      expect(Session.sections('admin'), contains(AppSection.campaigns));
      expect(Session.sections('admin'), contains(AppSection.accounts));
      expect(Session.sections('responsible'), contains(AppSection.campaigns));
      expect(
        Session.sections('responsible'),
        isNot(contains(AppSection.accounts)),
      );
    },
  );

  test('restaure la session et renouvelle un jeton expiré', () async {
    _storageValues.addAll({
      'sgsus_access_token': 'access-expiré',
      'sgsus_refresh_token': 'refresh-valide',
    });
    final provider = _createProvider(rejectFirstProfile: true);

    await provider.restoreSession();

    expect(provider.isAuthenticated, isTrue);
    expect(provider.role, 'student');
    expect(_storageValues['sgsus_access_token'], 'access-renouvelé');
    expect(_storageValues['sgsus_refresh_token'], 'refresh-renouvelé');
  });

  test('partage un seul renouvellement entre appels simultanés', () async {
    _storageValues['sgsus_refresh_token'] = 'refresh-valide';
    final authService = _FakeAuthService();
    final provider = AuthProvider(authService: authService);

    // Deux requêtes expirées en même temps ne déclenchent qu'un appel.
    final results = await Future.wait([
      provider.refreshAccessToken(),
      provider.refreshAccessToken(),
    ]);

    expect(results, [true, true]);
    expect(authService.refreshCalls, 1);
  });

  testWidgets('déconnecte le compte et revient au formulaire', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider();
    await tester.pumpWidget(SgsusApp(authProvider: provider));
    await tester.pumpAndSettle();

    await _login(tester, 'compte', 'secret');

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(provider.isAuthenticated, isFalse);
    expect(_storageValues['sgsus_access_token'], isNull);
    expect(_storageValues['sgsus_refresh_token'], isNull);
  });

  testWidgets('affiche la connexion tant qu’aucune session n’est ouverte', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(SgsusApp(authProvider: _createProvider()));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
  });
}

/// Saisit les identifiants puis valide le formulaire de connexion.
Future<void> _login(WidgetTester tester, String user, String password) async {
  await tester.enterText(find.byKey(const Key('login-username')), user);
  await tester.enterText(find.byKey(const Key('login-password')), password);
  await tester.tap(find.text('Se connecter'));
  await tester.pumpAndSettle();
}

/// Crée un fournisseur de session branché sur les faux serveurs.
AuthProvider _createProvider({
  String role = 'student',
  bool failLogin = false,
  bool rejectFirstProfile = false,
}) {
  return AuthProvider(
    authService: _FakeAuthService(
      role: role,
      failLogin: failLogin,
      rejectFirstProfile: rejectFirstProfile,
    ),
    httpClient: MockClient(_fakeBusinessApi),
  );
}

/// Faux serveur des routes métier utilisées par le tableau de bord.
Future<http.Response> _fakeBusinessApi(http.Request request) async {
  // Soutenance placée dans deux jours pour apparaître dans « à venir ».
  final day = DateTime.now().add(const Duration(days: 2));
  final start = DateTime(day.year, day.month, day.day, 9);
  return switch (request.url.path) {
    '/api/soutenances/planning/' => http.Response(
      jsonEncode({
        'total': 1,
        'soutenances': [
          {
            'id': 1,
            'folder': 1,
            'jury': 1,
            'student_name': 'Étudiant planifié',
            'subject': 'Sujet ${isoDate(day)}',
            'jury_name': 'Jury A',
            'room_name': 'Salle A',
            'slot_start': start.toUtc().toIso8601String(),
            'slot_end': start
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'status': 'planifie',
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
    '/api/salles/' => http.Response(
      jsonEncode([
        {'id': 1, 'name': 'Salle A', 'capacity': 30, 'is_active': true},
      ]),
      200,
    ),
    '/api/jurys/' => http.Response(jsonEncode([]), 200),
    _ => http.Response('{"detail":"Introuvable."}', 404),
  };
}

/// Faux service d'authentification, sans réseau.
class _FakeAuthService extends AuthService {
  _FakeAuthService({
    this.role = 'student',
    this.failLogin = false,
    this.rejectFirstProfile = false,
  });

  /// Rôle renvoyé dans le profil.
  final String role;

  /// Simule un refus d'identifiants.
  final bool failLogin;

  /// Simule un jeton expiré au premier chargement du profil.
  final bool rejectFirstProfile;

  var _profileCalls = 0;

  /// Nombre d'appels au renouvellement (test de dédoublonnage).
  var refreshCalls = 0;

  /// Profil fictif renvoyé par la connexion et `/profile/`.
  Map<String, dynamic> get _profile => {
    'id': 42,
    'username': 'compte',
    'full_name': 'Compte de test',
    'email': 'compte@example.test',
    'role': role,
  };

  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    if (failLogin) {
      throw const ApiException(
        'Identifiant ou mot de passe incorrect.',
        statusCode: 401,
      );
    }
    return {'user': _profile, 'access': 'access-test', 'refresh': 'refresh-test'};
  }

  @override
  Future<Map<String, dynamic>> profile(String accessToken) async {
    _profileCalls++;
    if (rejectFirstProfile && _profileCalls == 1) {
      throw const ApiException('Jeton expiré.', statusCode: 401);
    }
    return {'user': _profile};
  }

  @override
  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    refreshCalls++;
    // Laisse le temps à un second appel concurrent d'arriver.
    await Future<void>.delayed(Duration.zero);
    return {'access': 'access-renouvelé', 'refresh': 'refresh-renouvelé'};
  }

  @override
  Future<void> logout(String accessToken, String refreshToken) async {}
}
