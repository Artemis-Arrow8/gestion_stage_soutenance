/// Tests du mode hors ligne.
///
/// Un faux serveur ([_Serveur]) peut être « coupé » à tout moment : il
/// lève alors une `ClientException`, exactement comme le client HTTP réel
/// quand le téléphone n'a plus de réseau.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/app.dart';
import 'package:gestion_stage_soutenance/core/network/api_service.dart';
import 'package:gestion_stage_soutenance/core/network/hors_ligne.dart';
import 'package:gestion_stage_soutenance/core/storage/auth_storage.dart';
import 'package:gestion_stage_soutenance/core/utils/dates.dart';
import 'package:gestion_stage_soutenance/providers/auth_provider.dart';
import 'package:gestion_stage_soutenance/providers/planning_store.dart';
import 'package:gestion_stage_soutenance/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Le cache en mémoire est réinitialisé par flutter_test_config.dart.
  setUp(PlanningStore.clear);

  group('ApiService', () {
    test('une lecture réussie est mémorisée puis resservie hors ligne', () async {
      final serveur = _Serveur();
      final api = ApiService(client: serveur.client);

      final enLigne = await api.getList('salles/');
      expect(enLigne.single['name'], 'Salle A');
      expect(HorsLigne.actif.value, isFalse);

      // Coupure du réseau : la même lecture renvoie la copie locale.
      serveur.coupe = true;
      final horsLigne = await api.getList('salles/');
      expect(horsLigne.single['name'], 'Salle A');
      expect(HorsLigne.actif.value, isTrue);
      expect(HorsLigne.donneesDu.value, isNotNull);

      // Retour du réseau : le mode hors ligne s'arrête tout seul.
      serveur.coupe = false;
      await api.getList('salles/');
      expect(HorsLigne.actif.value, isFalse);
      expect(HorsLigne.donneesDu.value, isNull);
    });

    test('un serveur en veille (503) déclenche aussi le repli', () async {
      final serveur = _Serveur();
      final api = ApiService(client: serveur.client);
      await api.getList('salles/');

      serveur.codeForce = 503;
      final donnees = await api.getList('salles/');
      expect(donnees.single['name'], 'Salle A');
      expect(HorsLigne.donneesDu.value, isNotNull);
    });

    test('une page jamais ouverte reste une erreur claire hors ligne', () async {
      final serveur = _Serveur()..coupe = true;
      final api = ApiService(client: serveur.client);

      await expectLater(
        api.getList('salles/'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.serveurInjoignable, 'injoignable', isTrue)
              .having((e) => e.message, 'message', contains('hors ligne')),
        ),
      );
      expect(HorsLigne.actif.value, isTrue);
    });

    test('une modification hors ligne échoue sans rien inventer', () async {
      final serveur = _Serveur();
      final api = ApiService(client: serveur.client);
      await api.getList('salles/');
      serveur.coupe = true;

      await expectLater(
        api.post('salles/', {'name': 'Salle B'}),
        throwsA(isA<ApiException>()),
      );
      expect(serveur.ecritures, 0);
    });
  });

  group('AuthProvider', () {
    test('rouvre la session hors ligne avec le profil mémorisé', () async {
      final serveur = _Serveur();
      final stockage = _StockageMemoire();

      // Première utilisation, en ligne : connexion puis profil chargé.
      final enLigne = _fournisseur(serveur, stockage);
      expect(await enLigne.login('admin', 'secret'), isTrue);
      await enLigne.fetchUserProfile();

      // Réouverture de l'application sans réseau.
      serveur.coupe = true;
      final horsLigne = _fournisseur(serveur, stockage);
      await horsLigne.restoreSession();

      expect(horsLigne.isAuthenticated, isTrue);
      expect(horsLigne.role, 'admin');
      expect(HorsLigne.actif.value, isTrue);
    });

    test('un renouvellement impossible hors ligne ne déconnecte pas', () async {
      final serveur = _Serveur();
      final stockage = _StockageMemoire();
      final fournisseur = _fournisseur(serveur, stockage);
      await fournisseur.login('admin', 'secret');

      serveur.coupe = true;
      expect(await fournisseur.refreshAccessToken(), isFalse);

      expect(fournisseur.isAuthenticated, isTrue);
      expect(await stockage.readRefreshToken(), 'refresh-test');
    });

    test('la déconnexion efface les données mémorisées', () async {
      final serveur = _Serveur();
      final fournisseur = _fournisseur(serveur, _StockageMemoire());
      await fournisseur.login('admin', 'secret');
      await fournisseur.fetchUserProfile();
      expect((HorsLigne.cache as CacheMemoire).donnees, isNotEmpty);

      await fournisseur.logout();

      expect((HorsLigne.cache as CacheMemoire).donnees, isEmpty);
    });
  });

  testWidgets('bandeau « Mode hors ligne » puis retour en ligne', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur();
    final fournisseur = _fournisseur(serveur, _StockageMemoire());
    await fournisseur.login('admin', 'secret');
    await tester.pumpWidget(SgsusApp(authProvider: fournisseur));
    await tester.pumpAndSettle();
    expect(find.text('Étudiant planifié'), findsOneWidget);
    expect(find.text('Mode hors ligne'), findsNothing);

    // Coupure du réseau puis « tirer pour actualiser » (déclenché comme
    // le fait le geste, via l'indicateur d'actualisation de la page).
    serveur.coupe = true;
    final actualisation = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    unawaited(actualisation.show());
    await tester.pumpAndSettle();

    // Le bandeau apparaît et les données restent affichées.
    expect(find.text('Mode hors ligne'), findsOneWidget);
    expect(find.text('Étudiant planifié'), findsOneWidget);

    // Retour du réseau : « Réessayer » fait disparaître le bandeau.
    serveur.coupe = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Mode hors ligne'), findsNothing);
  });
}

/// Crée un fournisseur de session branché sur le faux [serveur].
AuthProvider _fournisseur(_Serveur serveur, AuthStorage stockage) {
  return AuthProvider(
    authService: AuthService(apiService: ApiService(client: serveur.client)),
    storage: stockage,
    httpClient: serveur.client,
  );
}

/// Faux serveur SGSUS qu'on peut couper ou mettre « en veille ».
class _Serveur {
  /// Vrai : plus de réseau (ClientException).
  bool coupe = false;

  /// Code HTTP imposé à toutes les réponses (ex. 503), sinon `null`.
  int? codeForce;

  /// Nombre d'écritures (POST hors authentification) reçues.
  int ecritures = 0;

  /// Client HTTP simulé à injecter dans l'application.
  late final http.Client client = MockClient(_repondre);

  /// Profil du compte administrateur fictif.
  static const _profil = {
    'id': 1,
    'username': 'admin',
    'full_name': 'Admin Test',
    'role': 'admin',
  };

  Future<http.Response> _repondre(http.Request requete) async {
    if (coupe) throw http.ClientException('Réseau indisponible', requete.url);
    if (codeForce != null) return http.Response('', codeForce!);
    final chemin = requete.url.path;
    if (requete.method == 'POST' &&
        !chemin.endsWith('/login/') &&
        !chemin.endsWith('/logout/')) {
      ecritures++;
    }
    final jour = DateTime.now().add(const Duration(days: 2));
    final debut = DateTime(jour.year, jour.month, jour.day, 9);
    final corps = switch (chemin) {
      '/api/login/' => {
        'access': 'access-test',
        'refresh': 'refresh-test',
        'user': _profil,
      },
      '/api/logout/' => <String, dynamic>{},
      '/api/profile/' => {'user': _profil},
      '/api/soutenances/planning/' => {
        'total': 1,
        'soutenances': [
          {
            'id': 1,
            'folder': 1,
            'jury': 1,
            'student_name': 'Étudiant planifié',
            'subject': 'Sujet ${isoDate(jour)}',
            'jury_name': 'Jury A',
            'room_name': 'Salle A',
            'slot_start': debut.toUtc().toIso8601String(),
            'slot_end': debut
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'status': 'planifie',
          },
        ],
      },
      '/api/salles/' => [
        {'id': 1, 'name': 'Salle A', 'capacity': 30, 'is_active': true},
      ],
      '/api/jurys/' => <dynamic>[],
      _ => null,
    };
    if (corps == null) return http.Response('{"detail":"Introuvable."}', 404);
    return http.Response.bytes(
      utf8.encode(jsonEncode(corps)),
      200,
      headers: {'content-type': 'application/json'},
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
