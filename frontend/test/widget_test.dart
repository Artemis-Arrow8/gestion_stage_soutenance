import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:gestion_stage_soutenance/providers/auth_provider.dart';
import 'package:gestion_stage_soutenance/repositories/auth_repository.dart';
import 'package:gestion_stage_soutenance/services/api_service.dart';
import 'package:gestion_stage_soutenance/services/auth_storage.dart';
import 'package:gestion_stage_soutenance/views/home_view.dart';
import 'package:gestion_stage_soutenance/views/login_view.dart';
import 'package:gestion_stage_soutenance/widgets/app_shell.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

late FlutterSecureStoragePlatform _previousPlatform;
late Map<String, String> _storageValues;

void main() {
  setUp(() {
    _previousPlatform = FlutterSecureStoragePlatform.instance;
    _storageValues = {};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      _storageValues,
    );
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
    await tester.pumpWidget(_app(_createProvider()));
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
    await tester.pumpWidget(_app(_createProvider(failLogin: true)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login-username')), 'invalide');
    await tester.enterText(find.byKey(const Key('login-password')), 'faux');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.text('Tableau de bord - SGSUS'), findsNothing);
  });

  testWidgets('authentifie le compte et affiche ses actions', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider();
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login-username')), 'compte');
    await tester.enterText(find.byKey(const Key('login-password')), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord - SGSUS'), findsOneWidget);
    expect(find.text('Compte de test'), findsOneWidget);
    expect(find.text('Mon dossier et mes documents'), findsOneWidget);
    expect(provider.isAuthenticated, isTrue);
  });

  testWidgets('un encadreur accède à ses dossiers affectés', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider(role: 'supervisor');
    await provider.login('encadreur', 'secret');
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();

    expect(
      find.text("Dossiers affectés et avis d'encadrement"),
      findsOneWidget,
    );
    expect(find.text('Ce module n’est pas encore intégré.'), findsNothing);
  });

  testWidgets('un administrateur accède aux campagnes et comptes', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider(role: 'admin');
    await provider.login('administrateur', 'secret');
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();

    expect(find.text('Gestion des Campagnes'), findsOneWidget);
    expect(find.text('Gestion des Utilisateurs & Rôles'), findsOneWidget);
    expect(Session.sections('admin'), contains(AppSection.campaigns));
    expect(Session.sections('admin'), contains(AppSection.accounts));
    expect(Session.sections('responsible'), contains(AppSection.campaigns));
    expect(
      Session.sections('responsible'),
      isNot(contains(AppSection.accounts)),
    );
  });

  test('restaure la session et renouvelle un jeton expiré', () async {
    _storageValues.addAll({
      'access_token': 'access-expiré',
      'refresh_token': 'refresh-valide',
    });
    final provider = _createProvider(rejectFirstProfile: true);

    await provider.restoreSession();

    expect(provider.isAuthenticated, isTrue);
    expect(provider.role, 'student');
    expect(_storageValues['access_token'], 'access-renouvelé');
    expect(_storageValues['refresh_token'], 'refresh-renouvelé');
  });

  testWidgets('déconnecte le compte et revient au formulaire', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider();
    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login-username')), 'compte');
    await tester.enterText(find.byKey(const Key('login-password')), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsOneWidget);
    expect(provider.isAuthenticated, isFalse);
    expect(_storageValues['access_token'], isNull);
    expect(_storageValues['refresh_token'], isNull);
  });

  testWidgets('refuse une vue protégée sans session authentifiée', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _createProvider(),
        child: const MaterialApp(home: HomeView()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Aucune session active. Veuillez vous connecter.'),
      findsOneWidget,
    );
  });
}

Widget _app(AuthProvider provider) {
  return ChangeNotifierProvider<AuthProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) =>
            authProvider.isAuthenticated ? const HomeView() : const LoginView(),
      ),
    ),
  );
}

AuthProvider _createProvider({
  String role = 'student',
  bool failLogin = false,
  bool rejectFirstProfile = false,
}) {
  return AuthProvider(
    authRepository: _FakeAuthRepository(
      role: role,
      failLogin: failLogin,
      rejectFirstProfile: rejectFirstProfile,
    ),
    storage: const FlutterSecureStorage(),
  );
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({
    this.role = 'student',
    this.failLogin = false,
    this.rejectFirstProfile = false,
  });

  final String role;
  final bool failLogin;
  final bool rejectFirstProfile;
  var _profileCalls = 0;

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

    return {
      'user': _profile,
      'access': 'access-test',
      'refresh': 'refresh-test',
    };
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
  Future<Map<String, dynamic>> refresh(String refreshToken) async => {
    'access': 'access-renouvelé',
    'refresh': 'refresh-renouvelé',
  };

  @override
  Future<void> logout(String accessToken, String refreshToken) async {}
}
