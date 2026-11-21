/// Tests de l'écran « Dossiers » sur un téléphone de 360 px : chaque rôle
/// trouve son action depuis l'accueil, sans tâtonner, et chaque décision
/// part au serveur avec les bonnes données.
///
/// Le serveur est simulé ([_Serveur]) : il renvoie un dossier dans l'état
/// voulu et enregistre les écritures reçues.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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

  // Le sélecteur de fichier natif est remplacé par un faux qui « choisit »
  // aussitôt un petit PDF (le canal natif n'existe pas en test).
  final selecteurNatif = FilePickerPlatform.instance;
  setUp(() => FilePickerPlatform.instance = _FauxSelecteur());
  tearDown(() => FilePickerPlatform.instance = selecteurNatif);

  testWidgets('encadreur : de l’accueil à « demander des corrections »', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(
      role: 'supervisor',
      statut: 'soumis',
      version: 2,
      messageEnvoi: 'J’ai repris le chapitre 2.',
    );
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
    // Le mot laissé par l'étudiant en envoyant son rapport.
    expect(find.text('Message de l’étudiant'), findsOneWidget);
    expect(find.text('« J’ai repris le chapitre 2. »'), findsOneWidget);

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

  testWidgets('étudiant sans rapport : « Ajouter mon rapport », puis l’envoyer d’un geste', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(role: 'student', statut: 'brouillon');
    await _ouvrir(tester, serveur);

    // L'accueil donne la prochaine étape en mots d'action.
    await _toucher(tester, 'Ajouter mon rapport');

    // La grande zone « Ajouter » est en haut de la page, seule.
    expect(find.text('Mon rapport de stage'), findsOneWidget);
    expect(find.text('Ajouter mon rapport'), findsOneWidget);
    expect(find.text('Fichier PDF · 10 Mo maximum'), findsOneWidget);
    // Rien à envoyer ni à lire tant qu'aucun rapport n'est ajouté.
    expect(find.text('Envoyer à mon encadreur'), findsNothing);
    expect(find.textContaining('Relire mon rapport'), findsNothing);
    expect(find.text('Ajouter une nouvelle version'), findsNothing);

    // Un toucher : le fichier est choisi, UNE fenêtre propose de l'envoyer.
    await _toucher(tester, 'Ajouter mon rapport');
    expect(find.text('Envoyer votre rapport ?'), findsOneWidget);
    expect(find.text('rapport_stage.pdf'), findsOneWidget);
    expect(find.textContaining('Deviendra la version 1'), findsOneWidget);
    expect(find.text('Ajouter sans envoyer'), findsOneWidget);

    await _toucher(tester, 'Envoyer à mon encadreur');
    // Le fichier part, puis l'envoi, sans message (champ laissé vide).
    expect(serveur.ecritures.map((e) => e.$1), [
      '/api/documents/upload/',
      '/api/internship-folders/5/soumettre/',
    ]);
    expect(serveur.ecritures.last.$2, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('étudiant : corrections demandées → ajouter la version corrigée et la renvoyer', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(
      role: 'student',
      statut: 'a_corriger',
      version: 1,
      corrections: 'Revoir le chapitre 2.',
    );
    await _ouvrir(tester, serveur);
    await _toucher(tester, 'Corriger mon rapport');

    // Ce que l'encadreur demande, et de quoi y répondre, en haut de page.
    expect(find.text('Corrections demandées'), findsOneWidget);
    expect(find.text('Ce que votre encadreur demande'), findsOneWidget);
    expect(find.text('« Revoir le chapitre 2. »'), findsWidgets);
    // La zone en haut ET le bouton sous la demande, dans « Mes rapports ».
    expect(find.text('Ajouter la version corrigée'), findsNWidgets(2));
    // L'ancienne version n'est plus « à envoyer » : on attend la corrigée.
    expect(find.text('Envoyer à mon encadreur'), findsNothing);

    await _toucher(tester, 'Ajouter la version corrigée');
    expect(find.text('Renvoyer la version corrigée ?'), findsOneWidget);
    expect(find.text('Ce que votre encadreur a demandé'), findsOneWidget);
    expect(find.textContaining('Deviendra la version 2'), findsOneWidget);

    // Un mot pour l'encadreur, puis « Renvoyer » : tout part d'un coup.
    await tester.enterText(find.byType(TextField), 'J’ai repris le chapitre 2.');
    await _toucher(tester, 'Renvoyer à mon encadreur');
    expect(serveur.ecritures.map((e) => e.$1), [
      '/api/documents/upload/',
      '/api/internship-folders/5/soumettre/',
    ]);
    expect(serveur.ecritures.last.$2, {'motif': 'J’ai repris le chapitre 2.'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('étudiant : « Ajouter » reste visible, versions et stage sont séparés', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(role: 'student', statut: 'soumis', version: 1);
    await _ouvrir(tester, serveur);
    // Rien à faire : l'accueil mène quand même au rapport.
    await _toucher(tester, 'Voir mon rapport');

    // 1. Où en est le rapport, avec l'ajout TOUJOURS à portée de main
    //    (sans passer par « Modifier », « Historique » ni un panneau).
    expect(find.text('Rapport envoyé'), findsOneWidget);
    expect(find.text('Ajouter une nouvelle version'), findsOneWidget);
    expect(find.text('Relire mon rapport (version 1)'), findsOneWidget);

    // 2. Ses rapports déposés, avec ce qu'en fait l'encadreur.
    expect(find.text('Mes rapports déposés'), findsOneWidget);
    expect(find.text('Version 1 · la plus récente'), findsOneWidget);
    expect(find.text('Votre encadreur est en train de la lire'), findsOneWidget);

    // 3. L'historique, en mots simples.
    expect(find.text('Rapport envoyé à l’encadreur'), findsOneWidget);

    // 4. Son stage, modifiable à part, avec un bouton sans ambiguïté.
    expect(find.text('Mon stage'), findsOneWidget);
    expect(find.text('Modifier l’entreprise ou le sujet'), findsOneWidget);
    expect(find.text('Modifier'), findsNothing);

    // Ajouter pendant la lecture de l'encadreur : la fenêtre prévient, et
    // ne propose pas de « renvoyer » (le rapport est déjà chez lui).
    await _toucher(tester, 'Ajouter une nouvelle version');
    expect(find.text('Ajouter cette nouvelle version ?'), findsOneWidget);
    expect(find.textContaining('à la place de l’ancienne'), findsOneWidget);
    expect(find.text('Ajouter sans envoyer'), findsNothing);
    await _toucher(tester, 'Ajouter cette version');
    expect(serveur.ecritures.map((e) => e.$1), ['/api/documents/upload/']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('encadreur : la page complète du dossier est une vraie page', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(role: 'supervisor', statut: 'soumis', version: 2);
    await _ouvrir(tester, serveur);
    await _toucher(tester, 'Examiner les rapports');

    await _toucher(tester, 'Ouvrir le dossier complet');
    // Pas de panneau flottant : une page avec le nom en titre.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Versions du rapport'), findsOneWidget);
    expect(find.text('Version 2 · la plus récente'), findsOneWidget);
    // L'encadreur lit la situation dans SES mots.
    expect(find.text('En attente de votre avis'), findsOneWidget);
    expect(find.text('Historique'), findsOneWidget);

    // Décider depuis la page : elle se ferme et la confirmation s'ouvre.
    await _toucher(tester, 'Accepter le rapport');
    expect(find.text('Accepter le rapport ?'), findsOneWidget);
    await tester.tap(find.text('Accepter'));
    await tester.pumpAndSettle();

    final (chemin, corps) = serveur.ecritures.single;
    expect(chemin, '/api/reviews/');
    expect(corps['decision'], 'favorable');
    expect(find.text('Versions du rapport'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('jury : « Rapports à lire », la date et un seul bouton', (
    WidgetTester tester,
  ) async {
    final serveur = _Serveur(role: 'jury', statut: 'recevable', version: 1);
    await _ouvrir(tester, serveur);

    // L'accueil annonce les rapports à lire.
    expect(find.text('1 rapport(s) à lire avant la soutenance'), findsOneWidget);
    await _toucher(tester, '1 rapport(s) à lire avant la soutenance');

    expect(find.text('Awa Traoré'), findsOneWidget);
    expect(find.textContaining('Soutenance :'), findsOneWidget);
    expect(find.textContaining('Salle 101'), findsOneWidget);
    expect(find.text('Rapport à lire'), findsOneWidget);
    expect(find.text('Lire le rapport (version 1)'), findsOneWidget);
    // Le jury lit ; il ne décide rien sur le dossier.
    for (final decision in [
      'Accepter le rapport',
      'Demander des corrections',
      'Autoriser la soutenance',
      'Refuser le dossier',
      'Ouvrir le dossier complet',
    ]) {
      expect(find.text(decision), findsNothing);
    }
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
  _Serveur({
    required this.role,
    required this.statut,
    this.version,
    this.corrections,
    this.messageEnvoi,
  });

  /// Rôle du compte connecté.
  final String role;

  /// Statut du dossier renvoyé.
  final String statut;

  /// Numéro de la dernière version déposée (`null` : aucun dépôt).
  final int? version;

  /// Commentaire de l'encadreur qui demande des corrections sur la
  /// dernière version (`null` : aucun avis).
  final String? corrections;

  /// Mot laissé par l'étudiant en envoyant son rapport (`null` : aucun).
  final String? messageEnvoi;

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
    'dernier_avis': corrections == null
        ? null
        : {
            'decision': 'defavorable',
            'comments': corrections,
            'author_role': 'encadreur',
            'version_number': version,
            'created_at': '2026-11-13T09:00:00Z',
          },
    'derniere_etape': messageEnvoi == null
        ? null
        : {
            'evenement': 'soumettre',
            'statut_apres': statut,
            'motif': messageEnvoi,
            'created_at': '2026-11-12T10:05:00Z',
          },
  };

  /// Avis visibles : la demande de corrections sur la dernière version.
  List<Map<String, dynamic>> get _avis => [
    if (corrections != null)
      {
        'id': 1,
        'document_version': 70 + version!,
        'decision': 'defavorable',
        'comments': corrections,
        'created_at': '2026-11-13T09:00:00Z',
      },
  ];

  /// Versions déposées du dossier n° 5.
  List<Map<String, dynamic>> get _versions => [
    for (var n = 1; n <= (version ?? 0); n++)
      {'id': 70 + n, 'folder': 5, 'version_number': n, 'uploaded_at': '2026-11-1${n}T10:00:00Z'},
  ];

  /// Historique : l'envoi à l'encadreur, dès que le dossier est soumis.
  List<Map<String, dynamic>> get _historique => [
    if (statut != 'brouillon')
      {
        'evenement': 'soumettre',
        'statut_avant': 'brouillon',
        'statut_apres': 'soumis',
        'created_at': '2026-11-12T10:05:00Z',
        'acteur_nom': 'Awa Traoré',
        'motif': '',
      },
  ];

  /// Soutenances : une seule, celle du dossier n° 5, pour le jury.
  Map<String, dynamic> get _planning => {
    'total': role == 'jury' ? 1 : 0,
    'soutenances': [
      if (role == 'jury')
        {
          'id': 9,
          'folder': 5,
          'student_name': 'Awa Traoré',
          'subject': 'Application de suivi',
          'slot_start': '2030-11-25T09:00:00',
          'slot_end': '2030-11-25T10:00:00',
          'room_name': 'Salle 101',
          'jury_name': 'Jury A',
          'status': 'planifie',
        },
    ],
  };

  Future<http.Response> _repondre(http.Request requete) async {
    final chemin = requete.url.path;
    final ecriture = requete.method == 'POST' && !chemin.endsWith('/login/');
    // Un dépôt de fichier arrive en multipart : on note seulement le chemin.
    final multipart = requete.headers['content-type']?.startsWith('multipart/') ?? false;
    if (ecriture) {
      ecritures.add((
        chemin,
        multipart || requete.body.isEmpty ? {} : jsonDecode(requete.body) as Map<String, dynamic>,
      ));
    }
    final Object? corps = switch (chemin) {
      '/api/login/' => {'access': 'a', 'refresh': 'r', 'user': _profil},
      '/api/profile/' => {'user': _profil},
      '/api/internship-folders/' => [_dossier],
      '/api/document-versions/' => _versions,
      '/api/internship-folders/5/historique/' => _historique,
      '/api/reviews/' when !ecriture => _avis,
      '/api/reviews/' => {'id': 1, 'decision': 'defavorable'},
      '/api/internship-folders/5/autoriser/' => _dossier,
      '/api/internship-folders/5/soumettre/' => _dossier,
      '/api/documents/upload/' => {'id': 80, 'folder': 5, 'version_number': (version ?? 0) + 1},
      '/api/soutenances/planning/' => _planning,
      '/api/salles/' || '/api/jurys/' => [],
      _ => null,
    };
    if (corps == null) return http.Response('{"detail":"Introuvable."}', 404);
    return http.Response(
      jsonEncode(corps),
      requete.method == 'POST' && (chemin == '/api/reviews/' || chemin == '/api/documents/upload/') ? 201 : 200,
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

/// Faux sélecteur de fichier : « choisit » aussitôt un petit PDF.
class _FauxSelecteur extends FilePickerPlatform {
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _FauxPdf();
}

/// Petit fichier PDF en mémoire.
final class _FauxPdf extends PlatformFile {
  /// Contenu : l'en-tête d'un PDF suffit (le serveur est simulé).
  static final _octets = Uint8List.fromList(utf8.encode('%PDF-1.4 rapport de test'));

  @override
  String get name => 'rapport_stage.pdf';

  @override
  Uri get uri => Uri.parse('memoire:///rapport_stage.pdf');

  /// Inutile pour ces tests (le dépôt lit les octets directement).
  @override
  Never get xFile => throw UnimplementedError('Inutile pour ces tests.');

  @override
  int? lengthSync() => _octets.length;

  @override
  Future<int?> length() async => _octets.length;

  @override
  Future<Uint8List> readAsBytes() async => _octets;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_octets);
}
