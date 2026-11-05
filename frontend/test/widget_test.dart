import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:frontend/main.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/repositories/auth_repository.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/auth_storage.dart';
import 'package:frontend/views/home_view.dart';

/// Vérifie les parcours Flutter avec des dépendances réseau simulées.
void main() {
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
      final previousPlatform = FlutterSecureStoragePlatform.instance;
      final values = <String, String>{};
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        values,
      );
      addTearDown(() {
        FlutterSecureStoragePlatform.instance = previousPlatform;
      });

      final storage = SecureAuthStorage();
      await storage.saveTokens('access-test', 'refresh-test');

      expect(values, {
        'sgsus_access_token': 'access-test',
        'sgsus_refresh_token': 'refresh-test',
      });
      expect(await storage.readAccessToken(), 'access-test');
      expect(await storage.readRefreshToken(), 'refresh-test');

      await storage.clearTokens();
      expect(values, isEmpty);
      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);
    },
  );

  testWidgets('affiche et valide les champs requis de connexion', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider();
    await tester.pumpWidget(MyApp(authProvider: provider));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Se connecter'));
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(
      find.text('Identifiant fourni par l\'établissement'),
      findsOneWidget,
    );
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Veuillez entrer votre identifiant'), findsOneWidget);
    expect(find.text('Veuillez entrer votre mot de passe'), findsOneWidget);
  });

  testWidgets('affiche le refus de connexion renvoyé par l’API', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider(failLogin: true);
    await tester.pumpWidget(MyApp(authProvider: provider));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-username')), 'invalide');
    await tester.enterText(find.byKey(const Key('login-password')), 'faux');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.textContaining('Tableau de bord'), findsNothing);
  });

  for (final entry in const {
    'admin': 'Tableau de bord — Administration',
    'responsible': 'Tableau de bord — Pédagogie',
    'supervisor': 'Tableau de bord — Encadrement',
    'student': 'Tableau de bord — Étudiant',
  }.entries) {
    testWidgets('redirige le rôle ${entry.key} vers son tableau de bord', (
      WidgetTester tester,
    ) async {
      final provider = _createProvider(role: entry.key);
      await tester.pumpWidget(MyApp(authProvider: provider));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('login-username')), 'compte');
      await tester.enterText(find.byKey(const Key('login-password')), 'secret');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Se connecter'), findsNothing);
      expect(find.text('Module non intégré'), findsNWidgets(2));
    });
  }

  testWidgets('refuse une vue protégée sans session authentifiée', (
    WidgetTester tester,
  ) async {
    final provider = _createProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: const MaterialApp(home: HomeViewForTest()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Cette session ne donne accès à aucun espace SGSUS.'),
      findsOneWidget,
    );
    expect(find.text('Tableau de bord — Étudiant'), findsNothing);
  });

  testWidgets('la route métier nommée n’est pas encore déclarée', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(authProvider: _createProvider()));
    await tester.pumpAndSettle();

    expect(
      () => tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed('/admin/accounts'),
      throwsA(isA<FlutterError>()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Tableau de bord — Administration'), findsNothing);
  });

  testWidgets('restaure la session sécurisée et affiche le rôle du profil', (
    WidgetTester tester,
  ) async {
    final storage = _MemoryAuthStorage(
      accessToken: 'access-persistant',
      refreshToken: 'refresh-persistant',
    );
    final provider = AuthProvider(
      authRepository: _FakeAuthRepository(role: 'supervisor'),
      storage: storage,
    );
    await tester.pumpWidget(MyApp(authProvider: provider));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord — Encadrement'), findsOneWidget);
    expect(find.text('Encadreur'), findsOneWidget);
  });

  testWidgets('restaure la session après recréation de l’application', (
    WidgetTester tester,
  ) async {
    final storage = _MemoryAuthStorage();
    final loginProvider = AuthProvider(
      authRepository: _FakeAuthRepository(role: 'student'),
      storage: storage,
    );
    await tester.pumpWidget(MyApp(authProvider: loginProvider));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-username')), 'compte');
    await tester.enterText(find.byKey(const Key('login-password')), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(storage.accessToken, 'access-test');
    expect(storage.refreshToken, 'refresh-test');

    await tester.pumpWidget(const SizedBox.shrink());
    final restoredProvider = AuthProvider(
      authRepository: _FakeAuthRepository(role: 'student'),
      storage: storage,
    );
    await tester.pumpWidget(MyApp(authProvider: restoredProvider));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord — Étudiant'), findsOneWidget);
    expect(restoredProvider.isAuthenticated, isTrue);
  });

  testWidgets('renouvelle les jetons si le profil rejette le jeton expiré', (
    WidgetTester tester,
  ) async {
    final storage = _MemoryAuthStorage(
      accessToken: 'access-expiré',
      refreshToken: 'refresh-valide',
    );
    final provider = AuthProvider(
      authRepository: _FakeAuthRepository(
        role: 'responsible',
        rejectFirstProfile: true,
      ),
      storage: storage,
    );
    await tester.pumpWidget(MyApp(authProvider: provider));
    await tester.pumpAndSettle();

    expect(find.text('Tableau de bord — Pédagogie'), findsOneWidget);
    expect(storage.accessToken, 'access-renouvelé');
    expect(storage.refreshToken, 'refresh-renouvelé');
  });

  testWidgets('déconnecte le compte et revient au formulaire', (
    WidgetTester tester,
  ) async {
    final storage = _MemoryAuthStorage();
    final provider = AuthProvider(
      authRepository: _FakeAuthRepository(role: 'student'),
      storage: storage,
    );
    await tester.pumpWidget(MyApp(authProvider: provider));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-username')), 'compte');
    await tester.enterText(find.byKey(const Key('login-password')), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Se déconnecter'));
    await tester.pumpAndSettle();

    expect(find.text('Se connecter'), findsOneWidget);
    expect(provider.isAuthenticated, isFalse);
    expect(storage.accessToken, isNull);
    expect(storage.refreshToken, isNull);
  });
}

/// Écran protégé inséré directement pour vérifier son garde d’accès.
class HomeViewForTest extends StatelessWidget {
  const HomeViewForTest({super.key});

  @override
  Widget build(BuildContext context) => const HomeView();
}

AuthProvider _createProvider({
  String role = 'student',
  bool failLogin = false,
}) {
  return AuthProvider(
    authRepository: _FakeAuthRepository(role: role, failLogin: failLogin),
    storage: _MemoryAuthStorage(),
  );
}

/// Simule uniquement la frontière HTTP pour tester les réactions de l’interface.
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
    if (role == 'student') 'student_number': 'ETU00042',
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
  Future<Map<String, dynamic>> refresh(String refreshToken) async {
    return {'access': 'access-renouvelé', 'refresh': 'refresh-renouvelé'};
  }

  @override
  Future<void> logout(String accessToken, String refreshToken) async {}
}

/// Stocke les jetons en mémoire pour éviter tout accès au trousseau en test.
class _MemoryAuthStorage implements AuthStorage {
  _MemoryAuthStorage({this.accessToken, this.refreshToken});

  String? accessToken;
  String? refreshToken;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }
}
