/// Dossiers de stage et rapports : écran conçu pour être compris SANS
/// formation, avec une page différente pour chaque profil.
///
/// * **Étudiant** — « Mon rapport de stage » : TOUT est sur une seule page,
///   en blocs séparés, sans rien à déplier ni panneau flottant :
///   1. mon rapport : la phrase qui dit où il en est, le commentaire de
///      l'encadreur s'il demande des corrections, puis une GRANDE zone
///      « Ajouter mon rapport » (bordure en pointillés, comme une zone de
///      dépôt de fichier) toujours visible en haut de la page — jamais
///      cachée derrière « Historique » ou « Modifier ». Après le choix du
///      fichier, UNE seule fenêtre propose de l'envoyer (ou de le renvoyer
///      corrigé) à l'encadreur, avec un mot facultatif pour lui ;
///   2. mes rapports déposés (chaque version, avec la réponse de
///      l'encadreur, et « Ajouter la version corrigée » sous sa demande) ;
///   3. l'historique ;
///   4. mon stage (entreprise et sujet, modifiables à part).
/// * **Encadreur** — « Rapports à examiner » : les rapports qui attendent
///   son avis en haut, avec « Lire », « Accepter » et « Demander des
///   corrections ». « Ouvrir le dossier complet » ouvre une vraie page
///   (versions, avis, historique) que le geste retour referme.
/// * **Responsable / administrateur** — « Dossiers de stage » : même
///   principe, avec « Autoriser la soutenance » et « Refuser » ; les
///   décisions rares (rouvrir, confidentialité…) sont dans la page du dossier.
/// * **Jury** — « Rapports à lire » : les rapports des soutenances où il
///   siège, avec la date de la soutenance et un seul bouton « Lire ».
///
/// Règles communes : un gros bouton par décision possible (et seulement
/// celles-là, voir `core/utils/etapes_dossier.dart`), chaque décision est
/// confirmée par une fenêtre qui dit ce qui va se passer, et un refus ou
/// une demande de corrections exige un commentaire.
///
/// Le statut ne se choisit jamais directement : il évolue par les étapes
/// du chapitre 4 et le serveur refuse toute étape sautée (409).
library;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/network/api_service.dart';
import '../core/pdf/visionneuse_pdf.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../core/utils/etapes_dossier.dart';
import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../providers/planning_store.dart';
import '../services/document_service.dart';
import '../services/planning_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Taille maximale d'un PDF déposé (identique à la limite du serveur).
const _tailleMaxPdf = 10 * 1024 * 1024;

/// Au-delà de ce nombre de dossiers, un champ de recherche est proposé.
const _seuilRecherche = 6;

/// Longueur maximale du mot laissé à l'encadreur (identique au serveur).
const _longueurMaxMessage = 1000;

/// Choix fait dans la fenêtre qui suit l'ajout d'un fichier : l'envoyer
/// tout de suite à l'encadreur ou non, avec un mot facultatif pour lui.
typedef _ChoixAjout = ({bool envoyer, String message});

/// Taille lisible d'un fichier : « 850 Ko », « 2,4 Mo ».
String _fmtTaille(int octets) {
  if (octets < 1024 * 1024) return '${(octets / 1024).ceil()} Ko';
  return '${(octets / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}

/// Formate une date ISO (`2026-07-10T…`) en `10/07/2026`.
String _fmtDate(String? raw) {
  if (raw == null || raw.length < 10) return raw ?? '';
  final p = raw.substring(0, 10).split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : raw.substring(0, 10);
}

/// Message lisible d'une erreur quelconque.
String _message(Object e) => switch (e) {
  ApiException(:final message) => message,
  FormatException(:final message) => message,
  _ => 'Une erreur inattendue est survenue.',
};

/// Identifiant entier d'un dossier (0 si absent).
int _id(Map<String, dynamic> dossier) =>
    int.tryParse(dossier['id']?.toString() ?? '') ?? 0;

/// Statut brut du dossier (`brouillon`, `soumis`…), chaîne vide si absent.
String _statut(Map<String, dynamic> dossier) =>
    dossier['status']?.toString() ?? '';

/// Nom de l'étudiant du dossier (repli : « Dossier n° … »).
String _nomEtudiant(Map<String, dynamic> dossier) {
  final nom = (dossier['student_name'] ?? '').toString().trim();
  return nom.isEmpty ? 'Dossier n° ${_id(dossier)}' : nom;
}

/// « Entreprise · sujet » (parties vides omises).
String _entrepriseEtSujet(Map<String, dynamic> dossier) =>
    [dossier['company_name'], dossier['subject']]
        .map((v) => (v ?? '').toString().trim())
        .where((v) => v.isNotEmpty)
        .join(' · ');

/// Vrai si le rapport du dossier est confidentiel.
bool _estConfidentiel(Map<String, dynamic> dossier) =>
    dossier['confidentialite']?.toString() == 'confidentiel';

/// Identifiant de la dernière version déposée, ou `null`.
int? _idDerniereVersion(Map<String, dynamic> dossier) {
  final version = dossier['derniere_version'];
  if (version is! Map) return null;
  return int.tryParse(version['id']?.toString() ?? '');
}

/// Initiales (2 lettres au plus) d'un nom, pour l'avatar.
String _initiales(String nom) {
  final mots = nom.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
  if (mots.isEmpty) return '?';
  return mots.take(2).map((m) => m[0].toUpperCase()).join();
}

/// Couleurs (texte, fond) et icône associées à une [HumeurDossier].
(Color, Color, IconData) _styleHumeur(HumeurDossier humeur) => switch (humeur) {
  HumeurDossier.aFaire => (AppColors.goldDeep, AppColors.goldSoft, Icons.touch_app_rounded),
  HumeurDossier.attente => (AppColors.grey, AppColors.neutralBg, Icons.hourglass_top_rounded),
  HumeurDossier.succes => (AppColors.success, AppColors.successBg, Icons.check_circle_rounded),
  HumeurDossier.alerte => (AppColors.danger, AppColors.dangerBg, Icons.error_outline_rounded),
};

/// Écran des dossiers de stage et des rapports.
class DocumentsScreen extends StatefulWidget {
  /// Crée l'écran.
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

/// État de l'écran : dossiers, recherche et actions en cours.
class _DocumentsScreenState extends State<DocumentsScreen> {
  late final DocumentService _service;

  /// Rôle du compte connecté (`student`, `supervisor`, `admin`…).
  late final String? _role;

  /// Dossiers visibles par le compte (déjà filtrés par le serveur).
  List<Map<String, dynamic>> _dossiers = [];

  /// Dossiers dont une action est en cours (bouton en attente, pas de
  /// double envoi par un double toucher).
  final Set<int> _enCours = {};

  bool _chargement = true;
  String? _erreur;

  /// Numéro de chargement : il change à chaque rechargement réussi, ce qui
  /// force les blocs « versions » et « historique » à se recharger aussi.
  int _generation = 0;

  /// Texte de recherche (étudiant, entreprise ou sujet).
  String _recherche = '';

  /// Filtre choisi en haut de l'écran ; `null` = tous les dossiers.
  CategorieDossier? _filtre;

  bool get _estEtudiant => _role == 'student';
  bool get _estJury => _role == 'jury';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _service = DocumentService(auth.api);
    _role = auth.role;
    // Jury : les dates de soutenance viennent du planning partagé (déjà
    // chargé par l'accueil en général ; sinon on le charge ici).
    if (_estJury) {
      PlanningStore.ensureLoaded(PlanningService(auth.api), loadCatalog: false);
    }
    _charger();
  }

  // -------------------------------------------------------------------------
  // Chargement
  // -------------------------------------------------------------------------

  /// Charge (ou recharge) la liste des dossiers.
  Future<void> _charger() async {
    setState(() {
      _chargement = _dossiers.isEmpty;
      _erreur = null;
    });
    try {
      final resultat = await _service.getFolders();
      if (!mounted) return;
      setState(() {
        _dossiers = resultat;
        _chargement = false;
        _generation++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = _message(e);
      });
      // La liste déjà affichée reste visible : on prévient seulement.
      if (_dossiers.isNotEmpty) SgToast.show(context, _erreur!, tone: SgTone.danger);
    }
  }

  /// Recharge les dossiers (et le profil de l'étudiant, affiché à l'accueil).
  Future<void> _rafraichir() async {
    if (_estEtudiant) await context.read<AuthProvider>().fetchUserProfile();
    await _charger();
  }

  /// Dossier à jour (après rechargement) ayant l'identifiant [id].
  Map<String, dynamic>? _dossierParId(int id) {
    for (final d in _dossiers) {
      if (_id(d) == id) return d;
    }
    return null;
  }

  /// Exécute [action] sur le dossier [id] : bouton en attente, message de
  /// réussite [succes], rechargement ; une erreur est affichée en rouge.
  Future<bool> _executer(int id, Future<void> Function() action, String succes) async {
    if (_enCours.contains(id)) return false;
    setState(() => _enCours.add(id));
    try {
      await action();
      if (!mounted) return true;
      SgToast.show(context, succes);
      await _rafraichir();
      return true;
    } catch (e) {
      if (mounted) SgToast.show(context, _message(e), tone: SgTone.danger);
      return false;
    } finally {
      if (mounted) setState(() => _enCours.remove(id));
    }
  }

  // -------------------------------------------------------------------------
  // Fenêtres de confirmation
  // -------------------------------------------------------------------------

  /// Fenêtre de décision : dit ce qui va se passer, avec un champ de
  /// commentaire facultatif ou obligatoire. Retourne le texte saisi (vide
  /// s'il n'y a pas de champ), ou `null` si l'utilisateur renonce.
  Future<String?> _confirmer({
    required String titre,
    required String message,
    required String bouton,
    required IconData icone,
    bool danger = false,
    String? champ,
    bool champObligatoire = false,
    String? exemple,
    int? longueurMax,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DialogueDecision(
        titre: titre,
        message: message,
        bouton: bouton,
        icone: icone,
        danger: danger,
        champ: champ,
        champObligatoire: champObligatoire,
        exemple: exemple,
        longueurMax: longueurMax,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions (une méthode par bouton)
  // -------------------------------------------------------------------------

  /// Exécute l'action [action] sur [dossier].
  void _agir(ActionDossier action, Map<String, dynamic> dossier) {
    switch (action) {
      case ActionDossier.deposer:
        _ajouter(dossier);
      case ActionDossier.envoyer:
        _envoyer(dossier);
      case ActionDossier.accepter:
        _accepter(dossier);
      case ActionDossier.demanderCorrections:
        _demanderCorrections(dossier);
      case ActionDossier.autoriser:
        _autoriser(dossier);
      case ActionDossier.refuser:
        _refuser(dossier);
      case ActionDossier.rouvrir:
        _rouvrir(dossier);
    }
  }

  /// Ouvre le rapport (dernière version, ou [versionId]) pour le lire.
  ///
  /// Sur le Web, l'onglet est préparé AVANT l'attente réseau (sinon le
  /// navigateur le bloquerait) : `preparer` doit rester la 1re instruction.
  Future<void> _lire(Map<String, dynamic> dossier, {int? versionId, int? numero}) async {
    final visionneuse = VisionneusePdf()..preparer();
    final id = versionId ?? _idDerniereVersion(dossier);
    if (id == null) {
      visionneuse.annuler();
      return;
    }
    final num = numero ?? numeroDerniereVersion(dossier) ?? 1;
    try {
      final octets = await _service.telechargerOctets(id);
      await visionneuse.afficher(octets, 'rapport_dossier_${_id(dossier)}_v$num.pdf');
    } catch (e) {
      visionneuse.annuler();
      if (mounted) SgToast.show(context, _message(e), tone: SgTone.danger);
    }
  }

  /// Étudiant : ajoute un document (PDF) puis, quand c'est possible, l'envoie
  /// (ou le renvoie corrigé) à l'encadreur dans la foulée — un seul geste,
  /// une seule fenêtre, au lieu de deux étapes séparées.
  ///
  /// Sur le Web, le sélecteur de fichier doit s'ouvrir DIRECTEMENT après le
  /// toucher (sinon le navigateur le bloque) : il passe donc en premier, et
  /// les explications (avertissement, commentaire de l'encadreur) viennent
  /// dans la fenêtre qui suit.
  Future<void> _ajouter(Map<String, dynamic> dossier) async {
    final id = _id(dossier);
    if (_enCours.contains(id)) return;

    final PlatformFile? choisi;
    try {
      choisi = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (e) {
      if (mounted) SgToast.show(context, _message(e), tone: SgTone.danger);
      return;
    }
    if (choisi == null || !mounted) return;
    final fichier = choisi;

    // Contrôle immédiat (le serveur vérifie aussi taille et signature).
    final taille = (await fichier.length()) ?? 0;
    if (!mounted) return;
    if (taille > _tailleMaxPdf) {
      SgToast.show(
        context,
        'Ce fichier dépasse 10 Mo : réduisez-le (par exemple en '
        'compressant les images) puis réessayez.',
        tone: SgTone.danger,
      );
      return;
    }

    // Une seule fenêtre : ce qui va se passer, et « envoyer maintenant ? ».
    final statut = _statut(dossier);
    final nom = fichier.name;
    final choix = await showDialog<_ChoixAjout>(
      context: context,
      builder: (_) => _DialogueAjout(
        nomFichier: nom,
        taille: taille,
        numero: (numeroDerniereVersion(dossier) ?? 0) + 1,
        statut: statut,
        envoiPossible: envoiPossible(dossier),
        corrections: statut == 'a_corriger' ? commentaireCorrections(dossier) : null,
      ),
    );
    if (choix == null || !mounted) return;

    setState(() => _enCours.add(id));
    var ajoute = false;
    try {
      await _service.uploadDocument(id, fichier);
      ajoute = true;
      if (choix.envoyer) {
        await _service.transition(id, 'soumettre', motif: choix.message.isEmpty ? null : choix.message);
      }
      if (mounted) {
        SgToast.show(context, switch (statut) {
          'a_corriger' when choix.envoyer => 'Version corrigée renvoyée à votre encadreur.',
          _ when choix.envoyer => 'Rapport envoyé à votre encadreur.',
          'soumis' => 'Nouvelle version ajoutée : votre encadreur examinera celle-ci.',
          'valide' || 'recevable' => 'Nouvelle version ajoutée : votre encadreur va l’examiner de nouveau.',
          _ => 'Document ajouté. Il reste à l’envoyer à votre encadreur.',
        });
      }
    } catch (e) {
      // Fichier ajouté mais envoi refusé : on dit exactement où on en est.
      if (mounted) {
        SgToast.show(
          context,
          ajoute
              ? 'Document ajouté, mais pas encore envoyé : ${_message(e)} '
                    'Touchez « Envoyer à mon encadreur » pour réessayer.'
              : _message(e),
          tone: SgTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _enCours.remove(id));
    }
    if (ajoute && mounted) await _rafraichir();
  }

  /// Étudiant : envoie (ou renvoie) le rapport déjà ajouté à l'encadreur
  /// (transition « soumettre »), avec un mot facultatif pour lui.
  Future<void> _envoyer(Map<String, dynamic> dossier) async {
    final version = numeroDerniereVersion(dossier);
    final correction = _statut(dossier) == 'a_corriger';
    final texte = await _confirmer(
      titre: correction ? 'Renvoyer la version corrigée ?' : 'Envoyer votre rapport ?',
      message:
          '${version == null ? 'Votre rapport' : 'La version $version de votre rapport'} '
          'sera envoyée à votre encadreur, qui donnera son avis. Vous pourrez '
          'encore ajouter une nouvelle version ensuite.',
      bouton: correction ? 'Renvoyer à mon encadreur' : 'Envoyer à mon encadreur',
      icone: Icons.send_rounded,
      champ: 'Message pour votre encadreur',
      exemple: correction
          ? 'Ex. : j’ai complété la bibliographie et revu le chapitre 2.'
          : 'Ex. : voici mon rapport de stage.',
      longueurMax: _longueurMaxMessage,
    );
    if (texte == null || !mounted) return;
    await _executer(
      _id(dossier),
      () => _service.transition(_id(dossier), 'soumettre', motif: texte.isEmpty ? null : texte),
      correction ? 'Version corrigée renvoyée à votre encadreur.' : 'Rapport envoyé à votre encadreur.',
    );
  }

  /// Encadreur : accepte la dernière version (avis favorable).
  Future<void> _accepter(Map<String, dynamic> dossier) async {
    final versionId = _idDerniereVersion(dossier);
    if (versionId == null) return;
    final texte = await _confirmer(
      titre: 'Accepter le rapport ?',
      message:
          'Version ${numeroDerniereVersion(dossier) ?? ''} du rapport de '
          '${_nomEtudiant(dossier)}. Le dossier passera ensuite au '
          'responsable des stages, qui autorisera la soutenance.',
      bouton: 'Accepter',
      icone: Icons.check_circle_rounded,
      champ: 'Commentaire pour l’étudiant',
    );
    if (texte == null || !mounted) return;
    await _executer(
      _id(dossier),
      () => _service.addReview(versionId, 'favorable', texte),
      'Rapport accepté. Le dossier passe au responsable des stages.',
    );
  }

  /// Encadreur : demande des corrections (avis défavorable commenté).
  Future<void> _demanderCorrections(Map<String, dynamic> dossier) async {
    final versionId = _idDerniereVersion(dossier);
    if (versionId == null) return;
    final texte = await _confirmer(
      titre: 'Demander des corrections',
      message:
          '${_nomEtudiant(dossier)} verra votre commentaire, ajoutera une '
          'version corrigée et vous la renverra.',
      bouton: 'Envoyer la demande',
      icone: Icons.edit_note_rounded,
      champ: 'Ce qu’il faut corriger',
      champObligatoire: true,
      exemple: 'Ex. : compléter la bibliographie, revoir le chapitre 2…',
    );
    if (texte == null || !mounted) return;
    await _executer(
      _id(dossier),
      () => _service.addReview(versionId, 'defavorable', texte),
      'Corrections demandées : l’étudiant verra votre commentaire.',
    );
  }

  /// Personnel : autorise la soutenance (dossier prêt à être planifié).
  Future<void> _autoriser(Map<String, dynamic> dossier) async {
    final texte = await _confirmer(
      titre: 'Autoriser la soutenance ?',
      message:
          'Le dossier de ${_nomEtudiant(dossier)} sera prêt pour la '
          'soutenance et pourra être planifié.',
      bouton: 'Autoriser',
      icone: Icons.verified_rounded,
    );
    if (texte == null || !mounted) return;
    await _executer(
      _id(dossier),
      () => _service.transition(_id(dossier), 'autoriser'),
      'Soutenance autorisée : le dossier peut être planifié.',
    );
  }

  /// Personnel : refuse le dossier (motif obligatoire, lu par l'étudiant).
  Future<void> _refuser(Map<String, dynamic> dossier) async {
    final motif = await _confirmer(
      titre: 'Refuser le dossier ?',
      message:
          '${_nomEtudiant(dossier)} verra le motif. Le dossier pourra être '
          'rouvert plus tard si nécessaire.',
      bouton: 'Refuser le dossier',
      icone: Icons.block_rounded,
      danger: true,
      champ: 'Motif du refus',
      champObligatoire: true,
    );
    if (motif == null || !mounted) return;
    await _executer(
      _id(dossier),
      () => _service.transition(_id(dossier), 'refuser', motif: motif),
      'Dossier refusé.',
    );
  }

  /// Personnel : rouvre un dossier refusé ou prêt (motif obligatoire).
  Future<void> _rouvrir(Map<String, dynamic> dossier) async {
    final motif = await _confirmer(
      titre: 'Rouvrir le dossier ?',
      message: 'Le dossier repassera « en attente d’avis » de l’encadreur.',
      bouton: 'Rouvrir',
      icone: Icons.lock_open_rounded,
      champ: 'Motif',
      champObligatoire: true,
    );
    if (motif == null || !mounted) return;
    await _executer(
      _id(dossier),
      () => _service.transition(_id(dossier), 'rouvrir', motif: motif),
      'Dossier rouvert.',
    );
  }

  /// Étudiant : crée son dossier ([dossier] null) ou modifie l'entreprise et
  /// le sujet.
  Future<void> _editerDossier({Map<String, dynamic>? dossier}) async {
    final saisie = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _FolderDialog(
        entreprise: dossier?['company_name']?.toString(),
        sujet: dossier?['subject']?.toString(),
      ),
    );
    if (saisie == null || !mounted) return;
    final (entreprise, sujet) = saisie;
    try {
      if (dossier == null) {
        await _service.createFolder(companyName: entreprise, subject: sujet);
      } else {
        await _service.updateFolder(_id(dossier), companyName: entreprise, subject: sujet);
      }
      if (!mounted) return;
      SgToast.show(
        context,
        dossier == null
            ? 'Dossier créé. Étape suivante : ajouter votre rapport.'
            : 'Informations du stage mises à jour.',
      );
      await _rafraichir();
    } catch (e) {
      if (mounted) SgToast.show(context, _message(e), tone: SgTone.danger);
    }
  }

  /// Bascule le rapport entre « standard » et « confidentiel » (personnel).
  Future<void> _basculerConfidentialite(Map<String, dynamic> dossier, bool confidentiel) async {
    try {
      await _service.definirConfidentialite(
        _id(dossier),
        niveau: confidentiel ? 'confidentiel' : 'standard',
        origine: confidentiel ? 'Demande de l’entreprise d’accueil' : '',
      );
      if (!mounted) return;
      SgToast.show(
        context,
        confidentiel
            ? 'Rapport confidentiel : seules les personnes habilitées le lisent.'
            : 'Rapport consultable normalement.',
      );
      await _charger();
    } catch (e) {
      if (mounted) SgToast.show(context, _message(e), tone: SgTone.danger);
    }
  }

  /// Encadreur et personnel : ouvre la page complète du dossier (vraie page,
  /// refermée par le geste retour), puis exécute la décision choisie.
  Future<void> _ouvrirDossier(Map<String, dynamic> dossier) async {
    final action = await pushPage<ActionDossier>(
      context,
      _PageDossier(
        service: _service,
        dossier: dossier,
        role: _role,
        onLire: () => _lire(dossier),
        onLireVersion: (versionId, numero) =>
            _lire(dossier, versionId: versionId, numero: numero),
        onConfidentialite: (valeur) => _basculerConfidentialite(dossier, valeur),
      ),
    );
    if (action == null || !mounted) return;
    _agir(action, _dossierParId(_id(dossier)) ?? dossier);
  }

  // -------------------------------------------------------------------------
  // Affichage
  // -------------------------------------------------------------------------

  /// Titre de la page, dans les mots du rôle.
  String get _titre => switch (_role) {
    'student' => 'Mon rapport de stage',
    'supervisor' => 'Rapports à examiner',
    'jury' => 'Rapports à lire',
    _ => 'Dossiers de stage',
  };

  /// Sous-titre : ce que l'utilisateur doit savoir pour commencer.
  String get _sousTitre => switch (_role) {
    'student' => 'Où en est votre rapport, ce que vous avez déposé et votre stage.',
    'supervisor' => 'Les rapports qui attendent votre avis sont en haut.',
    'jury' => 'Les rapports des soutenances où vous siégez : lisez-les avant le jour J.',
    _ => 'Les dossiers qui attendent une décision sont en haut.',
  };

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.documents,
      title: _titre,
      subtitle: _sousTitre,
      // Étudiant : une seule colonne, largeur de lecture confortable ;
      // autres rôles : jusqu'à deux colonnes de cartes sur grand écran.
      maxWidth: _estEtudiant ? 760 : 1240,
      // La liste se recharge après chaque décision, et en tirant la page
      // vers le bas.
      onRefresh: _rafraichir,
      child: _chargement
          ? const SgLoading(message: 'Chargement des dossiers…')
          : _erreur != null && _dossiers.isEmpty
          ? SgErrorState(
              title: 'Impossible de charger les dossiers',
              message: _erreur!,
              onRetry: _charger,
            )
          : switch (_role) {
              'student' => _vueEtudiant(),
              'jury' => _vueJury(),
              _ => _vueSuivi(),
            },
    );
  }

  /// Liste de cartes : une colonne sur téléphone et tablette étroite, deux
  /// colonnes dès 900 px, pour utiliser la largeur d'un ordinateur.
  Widget _grille(Iterable<Map<String, dynamic>> dossiers, Widget Function(Map<String, dynamic>) carte) {
    final liste = dossiers.toList();
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final dossier in liste)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: carte(dossier)),
            ],
          );
        }
        const espace = 16.0;
        final largeur = (contraintes.maxWidth - espace) / 2;
        return Wrap(
          spacing: espace,
          runSpacing: 14,
          children: [
            for (final dossier in liste) SizedBox(width: largeur, child: carte(dossier)),
          ],
        );
      },
    );
  }

  // --- Étudiant -------------------------------------------------------------

  /// Étudiant : son dossier (en général un seul), en blocs séparés.
  Widget _vueEtudiant() {
    if (_dossiers.isEmpty) {
      return SgEmpty(
        icon: Icons.create_new_folder_outlined,
        title: 'Commencez par créer votre dossier',
        message:
            'Indiquez votre entreprise d’accueil et votre sujet. Vous '
            'ajouterez ensuite votre rapport.',
        action: SgButton(
          'Créer mon dossier de stage',
          icon: Icons.create_new_folder_outlined,
          onPressed: () => _editerDossier(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final dossier in _dossiers) ..._blocsEtudiant(dossier),
      ],
    );
  }

  /// Les quatre blocs de la page de l'étudiant pour [dossier].
  List<Widget> _blocsEtudiant(Map<String, dynamic> dossier) {
    final id = _id(dossier);
    return [
      // 1. Mon rapport : la phrase, le commentaire de l'encadreur, la
      //    grande zone « Ajouter » (toujours visible) et l'envoi.
      SgCard(
        padding: const EdgeInsets.all(18),
        child: _CarteRapportEtudiant(
          dossier: dossier,
          situation: situationDossier(_role, dossier),
          enCours: _enCours.contains(id),
          onAjouter: () => _ajouter(dossier),
          onEnvoyer: () => _envoyer(dossier),
          onLire: () => _lire(dossier),
        ),
      ),
      const SizedBox(height: 28),
      // 2 et 3. Mes rapports déposés, puis l'historique.
      _SuiviDossier(
        key: ValueKey('suivi-$id-$_generation'),
        service: _service,
        dossier: dossier,
        role: _role,
        onLire: (versionId, numero) => _lire(dossier, versionId: versionId, numero: numero),
        // Sous la demande de corrections de l'encadreur, le bouton pour
        // ajouter la version corrigée est à portée de main.
        onAjouter: peutDeposer(_role, dossier) ? () => _ajouter(dossier) : null,
      ),
      const SizedBox(height: 28),
      // 4. Mon stage : entreprise et sujet, modifiables à part (ce bouton
      //    ne sert JAMAIS à déposer un rapport).
      const SgSectionTitle('Mon stage'),
      const SizedBox(height: 12),
      _CarteStage(
        dossier: dossier,
        onModifier: _statut(dossier) == 'recevable'
            ? null
            : () => _editerDossier(dossier: dossier),
      ),
      const SizedBox(height: 28),
    ];
  }

  // --- Jury -----------------------------------------------------------------

  /// Jury : les rapports des soutenances de son jury, la plus proche en
  /// premier, avec un seul bouton « Lire ».
  Widget _vueJury() {
    if (_dossiers.isEmpty) {
      return const SgEmpty(
        icon: Icons.menu_book_outlined,
        title: 'Aucun rapport à lire pour le moment',
        message:
            'Les rapports apparaîtront ici dès qu’une soutenance de votre '
            'jury sera planifiée.',
      );
    }
    return ValueListenableBuilder<List<Defense>>(
      valueListenable: PlanningStore.defenses,
      builder: (context, soutenances, _) {
        // Soutenance (non annulée) de chaque dossier, si elle est connue.
        Defense? soutenanceDe(Map<String, dynamic> dossier) => soutenances
            .where((d) => d.folderId == _id(dossier) && d.status != 'annule')
            .firstOrNull;
        String cle(Map<String, dynamic> dossier) {
          final s = soutenanceDe(dossier);
          return s == null ? '9999' : '${s.date}${s.startTime}';
        }

        final tries = [..._dossiers]..sort((a, b) => cle(a).compareTo(cle(b)));
        return _grille(
          tries,
          (dossier) => _CarteJury(
            dossier: dossier,
            situation: situationDossier(_role, dossier),
            soutenance: soutenanceDe(dossier),
            onLire: () => _lire(dossier),
          ),
        );
      },
    );
  }

  // --- Encadreur et personnel -----------------------------------------------

  /// Libellé d'une catégorie de filtre.
  static String _libelleCategorie(CategorieDossier c) => switch (c) {
    CategorieDossier.aTraiter => 'À traiter',
    CategorieDossier.enCours => 'En cours',
    CategorieDossier.prets => 'Prêts',
    CategorieDossier.refuses => 'Refusés',
  };

  /// Carte d'un dossier suivi (encadreur, personnel).
  Widget _carteSuivi(Map<String, dynamic> dossier) {
    return _CarteDossier(
      dossier: dossier,
      situation: situationDossier(_role, dossier),
      role: _role,
      enCours: _enCours.contains(_id(dossier)),
      onAction: (action) => _agir(action, dossier),
      onLire: () => _lire(dossier),
      onOuvrir: () => _ouvrirDossier(dossier),
    );
  }

  /// Encadreur et personnel : compteurs cliquables (filtres), puis « À
  /// traiter maintenant » et les autres dossiers.
  Widget _vueSuivi() {
    if (_dossiers.isEmpty) {
      return SgEmpty(
        icon: Icons.folder_open_outlined,
        title: 'Aucun dossier pour le moment',
        message: _role == 'supervisor'
            ? 'Les rapports des étudiants que vous encadrez apparaîtront ici.'
            : 'Les dossiers créés par les étudiants apparaîtront ici.',
      );
    }
    final q = _recherche.toLowerCase();
    final trouves = _dossiers.where((d) {
      if (q.isEmpty) return true;
      return [d['student_name'], d['company_name'], d['subject']]
          .any((v) => (v ?? '').toString().toLowerCase().contains(q));
    }).toList();
    // Nombre de dossiers par catégorie (affiché sur chaque filtre).
    final parCategorie = {
      for (final c in CategorieDossier.values)
        c: trouves.where((d) => categorieDossier(_role, d) == c).toList(),
    };
    final aTraiter = parCategorie[CategorieDossier.aTraiter]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compteurs cliquables : un toucher filtre la liste.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in CategorieDossier.values)
              SgChip(
                label: '${_libelleCategorie(c)} (${parCategorie[c]!.length})',
                selected: _filtre == c,
                onTap: () => setState(() => _filtre = _filtre == c ? null : c),
              ),
            SgChip(
              label: 'Tous (${trouves.length})',
              selected: _filtre == null,
              onTap: () => setState(() => _filtre = null),
            ),
          ],
        ),
        if (_dossiers.length > _seuilRecherche) ...[
          const SizedBox(height: 12),
          SgSearch(
            hint: 'Nom de l’étudiant, entreprise ou sujet…',
            onChanged: (v) => setState(() => _recherche = v),
          ),
        ],
        const SizedBox(height: 20),
        if (_filtre != null) ...[
          // Une seule catégorie demandée.
          SgSectionTitle('${_libelleCategorie(_filtre!)} (${parCategorie[_filtre]!.length})'),
          const SizedBox(height: 12),
          if (parCategorie[_filtre]!.isEmpty)
            const SgBanner(message: 'Aucun dossier dans cette catégorie.')
          else
            _grille(parCategorie[_filtre]!, _carteSuivi),
        ] else ...[
          SgSectionTitle(
            aTraiter.isEmpty ? 'À traiter maintenant' : 'À traiter maintenant (${aTraiter.length})',
          ),
          const SizedBox(height: 12),
          if (aTraiter.isEmpty)
            const SgBanner(
              message: 'Rien à traiter pour le moment. Tout est à jour.',
              tone: SgTone.success,
              icon: Icons.task_alt_rounded,
            )
          else
            _grille(aTraiter, _carteSuivi),
          if (trouves.length > aTraiter.length) ...[
            const SizedBox(height: 22),
            SgSectionTitle('Autres dossiers (${trouves.length - aTraiter.length})'),
            const SizedBox(height: 12),
            _grille(
              trouves.where((d) => categorieDossier(_role, d) != CategorieDossier.aTraiter),
              _carteSuivi,
            ),
          ],
        ],
        if (trouves.isEmpty && q.isNotEmpty)
          const SgEmpty(
            icon: Icons.search_off_rounded,
            title: 'Aucun résultat',
            message: 'Aucun dossier ne correspond à votre recherche.',
          ),
      ],
    );
  }
}

// ===========================================================================
// Cœur d'un dossier : situation, étapes et boutons utiles
// ===========================================================================

/// Situation du dossier (phrase + 4 étapes) et les gros boutons qui ont un
/// sens pour CE rôle et CET état. Partagé par les cartes de l'encadreur et
/// du personnel et par la page d'un dossier (l'étudiant a sa propre carte,
/// [_CarteRapportEtudiant], construite autour du bouton « Ajouter »).
class _CorpsDossier extends StatelessWidget {
  const _CorpsDossier({
    required this.dossier,
    required this.situation,
    required this.role,
    required this.enCours,
    required this.onAction,
    required this.onLire,
  });

  /// Dossier affiché (réponse de /api/internship-folders/).
  final Map<String, dynamic> dossier;

  /// Situation calculée pour le rôle de l'utilisateur.
  final SituationDossier situation;

  /// Rôle du compte connecté.
  final String? role;

  /// Vrai pendant une action sur ce dossier (boutons en attente).
  final bool enCours;

  /// Action choisie.
  final ValueChanged<ActionDossier> onAction;

  /// « Lire le rapport » (dernière version).
  final VoidCallback onLire;

  /// Texte du bouton d'une action, adapté au dossier.
  String _libelle(ActionDossier action) => switch (action) {
    ActionDossier.deposer => libelleAjout(dossier),
    ActionDossier.envoyer => 'Envoyer à l’encadreur',
    ActionDossier.accepter => 'Accepter le rapport',
    ActionDossier.demanderCorrections => 'Demander des corrections',
    ActionDossier.autoriser => 'Autoriser la soutenance',
    ActionDossier.refuser => 'Refuser le dossier',
    ActionDossier.rouvrir => 'Rouvrir le dossier',
  };

  /// Icône du bouton d'une action.
  IconData _icone(ActionDossier action) => switch (action) {
    ActionDossier.deposer => Icons.upload_file_rounded,
    ActionDossier.envoyer => Icons.send_rounded,
    ActionDossier.accepter => Icons.check_circle_rounded,
    ActionDossier.demanderCorrections => Icons.edit_note_rounded,
    ActionDossier.autoriser => Icons.verified_rounded,
    ActionDossier.refuser => Icons.block_rounded,
    ActionDossier.rouvrir => Icons.lock_open_rounded,
  };

  /// Variante du bouton : la 1re action attendue est en or, un refus en
  /// rouge, les autres sont discrètes.
  SgBtnVariant _variante(ActionDossier action, int rang) {
    if (action == ActionDossier.refuser) return SgBtnVariant.danger;
    // L'or est réservé à ce qui est attendu de l'utilisateur ; une action
    // possible mais non urgente (ex. rouvrir un dossier refusé) reste discrète.
    if (!situation.aTraiter) return SgBtnVariant.outline;
    return rang == 0 ? SgBtnVariant.primary : SgBtnVariant.outline;
  }

  @override
  Widget build(BuildContext context) {
    final version = numeroDerniereVersion(dossier);
    final corrections = commentaireCorrections(dossier);
    // Le mot laissé par l'étudiant en envoyant son rapport (« ce que j'ai
    // corrigé ») aide l'encadreur à relire vite.
    final message = messageEtudiant(dossier);
    // Pour décider, on LIT d'abord : « Lire » passe avant les décisions.
    final lireEnPremier = situation.aTraiter;

    final boutonLire = version == null
        ? null
        : _GrosBouton(
            'Lire le rapport (version $version)',
            icon: _estConfidentiel(dossier) ? Icons.lock_outline_rounded : Icons.chrome_reader_mode_outlined,
            variant: SgBtnVariant.outline,
            onPressed: onLire,
          );

    final boutons = <Widget>[
      if (lireEnPremier && boutonLire != null) boutonLire,
      for (final (rang, action) in situation.actions.indexed)
        _GrosBouton(
          _libelle(action),
          icon: _icone(action),
          variant: _variante(action, rang),
          loading: enCours && rang == 0,
          onPressed: enCours ? null : () => onAction(action),
        ),
      if (!lireEnPremier && boutonLire != null) boutonLire,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BandeauSituation(situation: situation),
        if (message != null) ...[
          const SizedBox(height: 10),
          _Citation(titre: 'Message de l’étudiant', texte: message, couleur: AppColors.gold),
        ],
        if (corrections != null && _statut(dossier) == 'a_corriger') ...[
          const SizedBox(height: 10),
          _Citation(titre: 'Commentaire de l’encadreur', texte: corrections),
        ],
        if (situation.etape >= 0) ...[
          const SizedBox(height: 16),
          _BarreEtapes(etape: situation.etape),
        ],
        if (boutons.isNotEmpty) const SizedBox(height: 18),
        for (final (i, bouton) in boutons.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          bouton,
        ],
        if (version == null) ...[
          const SizedBox(height: 12),
          const Text(
            'Aucun rapport déposé pour le moment.',
            style: TextStyle(fontSize: 12.5, color: AppColors.grey),
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Étudiant : « Mon rapport », construit autour du bouton « Ajouter »
// ===========================================================================

/// Bloc « Mon rapport » de l'étudiant, dans l'ordre où il se lit :
/// 1. la phrase qui dit où il en est ;
/// 2. le commentaire de l'encadreur s'il demande des corrections ;
/// 3. LE bouton à toucher : « Envoyer à mon encadreur » quand un fichier
///    attend d'être envoyé, puis la grande zone « Ajouter … » — toujours
///    visible, dorée quand c'est l'étape attendue ;
/// 4. « Relire mon rapport », puis la barre des 4 étapes.
class _CarteRapportEtudiant extends StatelessWidget {
  const _CarteRapportEtudiant({
    required this.dossier,
    required this.situation,
    required this.enCours,
    required this.onAjouter,
    required this.onEnvoyer,
    required this.onLire,
  });

  /// Dossier de l'étudiant (réponse de /api/internship-folders/).
  final Map<String, dynamic> dossier;

  /// Situation vue par l'étudiant.
  final SituationDossier situation;

  /// Vrai pendant un ajout ou un envoi (boutons en attente).
  final bool enCours;

  /// Choisit un fichier puis propose de l'envoyer.
  final VoidCallback onAjouter;

  /// Envoie le fichier déjà ajouté à l'encadreur.
  final VoidCallback onEnvoyer;

  /// Relit la dernière version.
  final VoidCallback onLire;

  @override
  Widget build(BuildContext context) {
    final version = numeroDerniereVersion(dossier);
    final statut = _statut(dossier);
    final corrections = statut == 'a_corriger' ? commentaireCorrections(dossier) : null;
    // L'étape attendue décide de ce qui est mis en avant (en or).
    final ajoutAttendu = situation.actions.firstOrNull == ActionDossier.deposer;
    final envoiAttendu = situation.actions.contains(ActionDossier.envoyer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BandeauSituation(situation: situation),
        if (corrections != null) ...[
          const SizedBox(height: 10),
          _Citation(titre: 'Ce que votre encadreur demande', texte: corrections),
        ],
        const SizedBox(height: 18),
        // Un fichier ajouté attend d'être envoyé : c'est LE bouton or.
        if (envoiAttendu) ...[
          _GrosBouton(
            statut == 'a_corriger' ? 'Renvoyer à mon encadreur' : 'Envoyer à mon encadreur',
            icon: Icons.send_rounded,
            variant: SgBtnVariant.primary,
            loading: enCours,
            onPressed: enCours ? null : onEnvoyer,
          ),
          const SizedBox(height: 10),
        ],
        // La zone « Ajouter » reste TOUJOURS là (sauf dossier refusé, qui
        // doit d'abord être rouvert par le responsable).
        if (peutDeposer('student', dossier))
          _ZoneAjout(
            titre: libelleAjout(dossier),
            enAvant: ajoutAttendu,
            enCours: enCours && !envoiAttendu,
            onTap: enCours ? null : onAjouter,
          ),
        if (version != null) ...[
          const SizedBox(height: 10),
          _GrosBouton(
            'Relire mon rapport (version $version)',
            icon: Icons.chrome_reader_mode_outlined,
            variant: SgBtnVariant.outline,
            onPressed: onLire,
          ),
        ],
        if (situation.etape >= 0) ...[const SizedBox(height: 20), _BarreEtapes(etape: situation.etape)],
      ],
    );
  }
}

/// Grande zone « Ajouter un document » à bordure en pointillés, comme une
/// zone de dépôt de fichier : impossible à manquer, facile à toucher au
/// pouce, et elle dit ce qu'on attend (PDF, 10 Mo).
class _ZoneAjout extends StatelessWidget {
  const _ZoneAjout({required this.titre, required this.enAvant, required this.enCours, required this.onTap});

  /// Texte principal (« Ajouter mon rapport », « Ajouter la version
  /// corrigée »…).
  final String titre;

  /// Vrai quand ajouter un fichier est l'étape attendue : zone dorée.
  final bool enAvant;

  /// Vrai pendant l'envoi du fichier.
  final bool enCours;

  /// Ouvre le choix du fichier (`null` : désactivée).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rayon = BorderRadius.circular(AppTheme.radiusSmall);
    return Semantics(
      button: true,
      label: '$titre, fichier PDF de 10 Mo maximum',
      excludeSemantics: true,
      child: Material(
        color: enAvant ? AppColors.goldSoft : AppColors.surfaceAlt,
        borderRadius: rayon,
        child: InkWell(
          onTap: onTap,
          borderRadius: rayon,
          child: CustomPaint(
            painter: _BordurePointillee(
              couleur: enAvant ? AppColors.gold : AppColors.greyLight,
              rayon: AppTheme.radiusSmall,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(
                children: [
                  // Pastille ronde : flèche de dépôt, ou roue pendant l'envoi.
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: enAvant ? AppColors.gold : Colors.white,
                      border: enAvant ? null : Border.all(color: AppColors.line),
                    ),
                    child: enCours
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.ink),
                          )
                        : const Icon(Icons.upload_file_rounded, color: AppColors.ink, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          enCours ? 'Envoi du fichier…' : titre,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Fichier PDF · 10 Mo maximum',
                          style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (!enCours)
                    Icon(Icons.add_circle_outline_rounded, color: enAvant ? AppColors.goldDeep : AppColors.greyLight),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dessine une bordure arrondie en pointillés (zone de dépôt de fichier).
class _BordurePointillee extends CustomPainter {
  const _BordurePointillee({required this.couleur, required this.rayon});

  /// Couleur des tirets.
  final Color couleur;

  /// Rayon des coins.
  final double rayon;

  @override
  void paint(Canvas canvas, Size size) {
    final pinceau = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    // Contour légèrement rentré pour que le trait ne soit pas rogné.
    final contour = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(rayon)).deflate(0.8));
    // Tirets de 6 px espacés de 4 px tout le long du contour.
    for (final trace in contour.computeMetrics()) {
      for (var debut = 0.0; debut < trace.length; debut += 10) {
        canvas.drawPath(trace.extractPath(debut, debut + 6), pinceau);
      }
    }
  }

  @override
  bool shouldRepaint(_BordurePointillee ancien) => ancien.couleur != couleur || ancien.rayon != rayon;
}

/// Fenêtre qui suit le choix d'un fichier : ce qui a été choisi, ce que
/// l'encadreur avait demandé, ce qui va se passer, et — quand c'est
/// possible — « Envoyer à mon encadreur » tout de suite, avec un mot
/// facultatif pour lui. Les boutons sont empilés en pleine largeur pour
/// être touchés au pouce sur un téléphone.
class _DialogueAjout extends StatefulWidget {
  const _DialogueAjout({
    required this.nomFichier,
    required this.taille,
    required this.numero,
    required this.statut,
    required this.envoiPossible,
    this.corrections,
  });

  /// Nom du fichier choisi.
  final String nomFichier;

  /// Taille du fichier, en octets.
  final int taille;

  /// Numéro que portera la nouvelle version.
  final int numero;

  /// Statut actuel du dossier.
  final String statut;

  /// Vrai si le fichier peut être envoyé à l'encadreur dans la foulée.
  final bool envoiPossible;

  /// Commentaire de l'encadreur qui demande des corrections, le cas échéant.
  final String? corrections;

  @override
  State<_DialogueAjout> createState() => _DialogueAjoutState();
}

/// État de la fenêtre : le mot pour l'encadreur.
class _DialogueAjoutState extends State<_DialogueAjout> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  /// Vrai si l'étudiant renvoie une version corrigée.
  bool get _correction => widget.statut == 'a_corriger';

  /// Ce qui va se passer quand l'encadreur a déjà le rapport en main
  /// (STA05 : une pièce acceptée n'est jamais remplacée en silence).
  String? get _avertissement => switch (widget.statut) {
    'valide' || 'recevable' =>
      'Votre rapport a déjà été accepté : cette nouvelle version devra de '
          'nouveau être examinée par votre encadreur.',
    'soumis' =>
      'Votre encadreur n’a pas encore répondu : il examinera cette version '
          'à la place de l’ancienne.',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final avertissement = _avertissement;
    final titre = !widget.envoiPossible
        ? 'Ajouter cette nouvelle version ?'
        : _correction
        ? 'Renvoyer la version corrigée ?'
        : 'Envoyer votre rapport ?';
    return AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.upload_file_rounded, color: AppColors.goldDeep, size: 34),
      title: Text(titre, textAlign: TextAlign.center),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Le fichier choisi : on vérifie d'un coup d'œil que c'est le bon.
            _ApercuFichier(nom: widget.nomFichier, taille: widget.taille, numero: widget.numero),
            if (widget.corrections != null) ...[
              const SizedBox(height: 12),
              _Citation(titre: 'Ce que votre encadreur a demandé', texte: widget.corrections!),
            ],
            if (avertissement != null) ...[
              const SizedBox(height: 12),
              Text(avertissement, style: const TextStyle(fontSize: 14, height: 1.45)),
            ],
            if (widget.envoiPossible) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                minLines: 2,
                maxLines: 4,
                maxLength: _longueurMaxMessage,
                decoration: InputDecoration(
                  labelText: 'Message pour votre encadreur (facultatif)',
                  hintText: _correction
                      ? 'Ex. : j’ai complété la bibliographie et revu le chapitre 2.'
                      : 'Ex. : voici mon rapport de stage.',
                  alignLabelWithHint: true,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _GrosBouton(
              !widget.envoiPossible
                  ? 'Ajouter cette version'
                  : _correction
                  ? 'Renvoyer à mon encadreur'
                  : 'Envoyer à mon encadreur',
              icon: widget.envoiPossible ? Icons.send_rounded : Icons.upload_file_rounded,
              variant: SgBtnVariant.primary,
              onPressed: () =>
                  Navigator.pop<_ChoixAjout>(context, (envoyer: widget.envoiPossible, message: _message.text.trim())),
            ),
            if (widget.envoiPossible) ...[
              const SizedBox(height: 10),
              _GrosBouton(
                'Ajouter sans envoyer',
                icon: Icons.save_alt_rounded,
                variant: SgBtnVariant.outline,
                onPressed: () => Navigator.pop<_ChoixAjout>(context, (envoyer: false, message: '')),
              ),
            ],
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ],
        ),
      ),
    );
  }
}

/// Aperçu du fichier choisi : icône PDF, nom, numéro de version et taille.
class _ApercuFichier extends StatelessWidget {
  const _ApercuFichier({required this.nom, required this.taille, required this.numero});

  final String nom;
  final int taille;
  final int numero;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf_rounded, color: AppColors.goldDeep, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Deviendra la version $numero · ${_fmtTaille(taille)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Cartes de liste (encadreur, personnel, jury)
// ===========================================================================

/// En-tête « qui et quoi » d'une carte : avatar, nom, entreprise et sujet.
class _EnteteEtudiant extends StatelessWidget {
  const _EnteteEtudiant({required this.dossier, this.onTap});

  final Map<String, dynamic> dossier;

  /// Ouvre la page du dossier (toucher le nom est un geste naturel).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final nom = _nomEtudiant(dossier);
    final details = _entrepriseEtSujet(dossier);
    final contenu = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SgAvatar(initials: _initiales(nom), size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nom,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.35),
                ),
              ],
            ],
          ),
        ),
        if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.greyLight),
      ],
    );
    if (onTap == null) return contenu;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: contenu,
    );
  }
}

/// Carte d'un dossier suivi par l'encadreur ou le personnel : qui, où on en
/// est, les boutons utiles, et l'accès à la page complète du dossier.
class _CarteDossier extends StatelessWidget {
  const _CarteDossier({
    required this.dossier,
    required this.situation,
    required this.role,
    required this.enCours,
    required this.onAction,
    required this.onLire,
    required this.onOuvrir,
  });

  final Map<String, dynamic> dossier;
  final SituationDossier situation;
  final String? role;
  final bool enCours;
  final ValueChanged<ActionDossier> onAction;
  final VoidCallback onLire;

  /// Ouvre la page complète du dossier.
  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    return SgCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnteteEtudiant(dossier: dossier, onTap: onOuvrir),
          const SizedBox(height: 14),
          _CorpsDossier(
            dossier: dossier,
            situation: situation,
            role: role,
            enCours: enCours,
            onAction: onAction,
            onLire: onLire,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOuvrir,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Ouvrir le dossier complet'),
              style: TextButton.styleFrom(foregroundColor: AppColors.goldDeep),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'un rapport à lire par un membre du jury : qui, quand a lieu la
/// soutenance, et un seul bouton « Lire ».
class _CarteJury extends StatelessWidget {
  const _CarteJury({
    required this.dossier,
    required this.situation,
    required this.soutenance,
    required this.onLire,
  });

  final Map<String, dynamic> dossier;
  final SituationDossier situation;

  /// Soutenance du dossier, si le planning est connu.
  final Defense? soutenance;

  final VoidCallback onLire;

  /// « Mardi 25 novembre 2026 à 09:00 · Salle 101 ».
  String _quand(Defense s) {
    final jour = parseDefenseDate(s.date);
    return [
      '${jour == null ? s.date : longDate(jour)} à ${s.startTime}',
      if (s.roomName.isNotEmpty) s.roomName,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final version = numeroDerniereVersion(dossier);
    final confidentiel = _estConfidentiel(dossier);
    return SgCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnteteEtudiant(dossier: dossier),
          if (soutenance != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded, color: AppColors.goldDeep, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Soutenance : ${_quand(soutenance!)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          _BandeauSituation(situation: situation),
          if (version != null) ...[
            const SizedBox(height: 18),
            _GrosBouton(
              'Lire le rapport (version $version)',
              icon: confidentiel ? Icons.lock_outline_rounded : Icons.chrome_reader_mode_outlined,
              variant: SgBtnVariant.primary,
              onPressed: onLire,
            ),
            if (confidentiel) ...[
              const SizedBox(height: 8),
              const Text(
                'Rapport confidentiel : sa lecture demande une autorisation '
                'du responsable des stages.',
                style: TextStyle(fontSize: 12, color: AppColors.grey, height: 1.35),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Bloc « Mon stage » de l'étudiant : entreprise et sujet, avec un bouton
/// de modification bien nommé (il ne sert pas à déposer un rapport).
class _CarteStage extends StatelessWidget {
  const _CarteStage({required this.dossier, this.onModifier});

  final Map<String, dynamic> dossier;

  /// Modification de l'entreprise et du sujet, ou `null` si interdite.
  final VoidCallback? onModifier;

  @override
  Widget build(BuildContext context) {
    return SgCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SgKv(label: 'Entreprise d’accueil', value: (dossier['company_name'] ?? '').toString()),
          const SizedBox(height: 14),
          SgKv(label: 'Sujet du stage', value: (dossier['subject'] ?? '').toString()),
          const SizedBox(height: 16),
          if (onModifier != null)
            SgButton(
              'Modifier l’entreprise ou le sujet',
              icon: Icons.edit_outlined,
              variant: SgBtnVariant.outline,
              expand: true,
              onPressed: onModifier,
            )
          else
            const Text(
              'Votre soutenance est autorisée : ces informations ne se modifient plus.',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.35),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Éléments visuels communs
// ===========================================================================

/// Bouton large et haut (52 px), facile à toucher avec le pouce.
class _GrosBouton extends StatelessWidget {
  const _GrosBouton(
    this.label, {
    required this.icon,
    required this.variant,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final SgBtnVariant variant;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // Contrainte stricte : le bouton de la charte prend 52 px de haut et
    // toute la largeur de la carte.
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: SgButton(
        label,
        icon: icon,
        variant: variant,
        loading: loading,
        onPressed: onPressed,
      ),
    );
  }
}

/// Phrase de situation sur fond coloré : titre + explication.
class _BandeauSituation extends StatelessWidget {
  const _BandeauSituation({required this.situation});

  final SituationDossier situation;

  @override
  Widget build(BuildContext context) {
    final (couleur, fond, icone) = _styleHumeur(situation.humeur);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: couleur, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  situation.titre,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: couleur),
                ),
                const SizedBox(height: 3),
                Text(
                  situation.explication,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Commentaire cité (demande de corrections), bien visible.
class _Citation extends StatelessWidget {
  const _Citation({required this.titre, required this.texte, this.couleur = AppColors.warning});

  final String titre;
  final String texte;

  /// Couleur du trait à gauche (orange : corrections ; vert : accepté).
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(left: BorderSide(color: couleur, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.grey),
          ),
          const SizedBox(height: 4),
          Text('« $texte »', style: const TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.ink)),
        ],
      ),
    );
  }
}

/// Barre des 4 étapes du parcours : faites (coche or), en cours (anneau
/// or), à venir (gris).
class _BarreEtapes extends StatelessWidget {
  const _BarreEtapes({required this.etape});

  /// Étape atteinte (0 à 3 ; 3 = parcours terminé).
  final int etape;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, libelle) in etapesParcours.indexed)
          Expanded(
            child: Semantics(
              label: 'Étape ${i + 1} sur ${etapesParcours.length} : $libelle',
              child: Column(
                children: [
                  _Pastille(
                    faite: i < etape || etape == etapesParcours.length - 1,
                    enCours: i == etape && etape != etapesParcours.length - 1,
                    numero: i + 1,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    libelle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      fontWeight: i == etape ? FontWeight.w700 : FontWeight.w500,
                      color: i <= etape ? AppColors.ink : AppColors.greyLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Pastille ronde d'une étape.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.faite, required this.enCours, required this.numero});

  final bool faite;
  final bool enCours;
  final int numero;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: faite ? AppColors.gold : Colors.white,
        border: Border.all(
          color: faite || enCours ? AppColors.gold : AppColors.line,
          width: enCours ? 2.5 : 1.5,
        ),
      ),
      child: faite
          ? const Icon(Icons.check_rounded, size: 16, color: AppColors.ink)
          : Text(
              '$numero',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: enCours ? AppColors.goldDeep : AppColors.greyLight,
              ),
            ),
    );
  }
}

// ===========================================================================
// Versions déposées et historique (chargés à part)
// ===========================================================================

/// Données des blocs « versions » et « historique ».
class _DonneesSuivi {
  const _DonneesSuivi(this.versions, this.avis, this.historique);

  /// Versions du rapport, la plus récente en premier.
  final List<Map<String, dynamic>> versions;

  /// Avis par identifiant de version (du plus ancien au plus récent).
  final Map<int, List<Map<String, dynamic>>> avis;

  /// Étapes du dossier, de la plus ancienne à la plus récente.
  final List<Map<String, dynamic>> historique;
}

/// Deux blocs séparés : les versions déposées (chacune avec la réponse de
/// l'encadreur et un bouton « Lire »), puis l'historique en mots simples.
class _SuiviDossier extends StatefulWidget {
  const _SuiviDossier({
    super.key,
    required this.service,
    required this.dossier,
    required this.role,
    required this.onLire,
    this.onAjouter,
  });

  final DocumentService service;
  final Map<String, dynamic> dossier;
  final String? role;

  /// Lecture d'une version précise (identifiant, numéro).
  final void Function(int versionId, int numero) onLire;

  /// Étudiant : ajout d'une version (corrigée), proposé sous la demande de
  /// corrections de l'encadreur ; `null` pour les autres rôles.
  final VoidCallback? onAjouter;

  @override
  State<_SuiviDossier> createState() => _SuiviDossierState();
}

/// État : chargement unique des versions, des avis et de l'historique.
class _SuiviDossierState extends State<_SuiviDossier> {
  late final Future<_DonneesSuivi> _donnees = _chargerDonnees();

  bool get _etudiant => widget.role == 'student';

  /// Versions, avis (en un appel) et historique du dossier. Un bloc
  /// secondaire indisponible (avis, historique) s'affiche simplement vide.
  Future<_DonneesSuivi> _chargerDonnees() async {
    final id = _id(widget.dossier);
    final versions = nombreVersions(widget.dossier) == 0
        ? <Map<String, dynamic>>[]
        : await widget.service.getDocuments(id);
    versions.sort(
      (a, b) => (int.tryParse(b['version_number']?.toString() ?? '') ?? 0)
          .compareTo(int.tryParse(a['version_number']?.toString() ?? '') ?? 0),
    );
    final ids = versions.map((v) => int.tryParse(v['id']?.toString() ?? '') ?? 0);
    // Un rôle sans droit de lecture des avis reçoit simplement une liste vide.
    final avis = versions.isEmpty
        ? <int, List<Map<String, dynamic>>>{}
        : await widget.service
              .getReviewsParVersion(ids)
              .catchError((_) => <int, List<Map<String, dynamic>>>{});
    final historique = await widget.service
        .historique(id)
        .catchError((_) => <Map<String, dynamic>>[]);
    return _DonneesSuivi(versions, avis, historique);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DonneesSuivi>(
      future: _donnees,
      builder: (context, snapshot) {
        final pret = snapshot.connectionState == ConnectionState.done;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SgSectionTitle(
              _etudiant ? 'Mes rapports déposés' : 'Versions du rapport',
              subtitle: 'La plus récente en premier.',
            ),
            const SizedBox(height: 12),
            if (!pret)
              const SgLoading(message: 'Chargement…')
            else if (snapshot.hasError)
              SgBanner(message: _message(snapshot.error!), tone: SgTone.danger)
            else if (snapshot.data!.versions.isEmpty)
              _CadreVide(
                _etudiant
                    ? 'Vous n’avez encore déposé aucun rapport. Touchez '
                          '« Ajouter mon rapport » en haut de la page.'
                    : 'Aucun rapport déposé pour le moment.',
              )
            else
              for (final (i, v) in snapshot.data!.versions.indexed)
                _CarteVersion(
                  version: v,
                  avis: snapshot.data!.avis[int.tryParse(v['id']?.toString() ?? '') ?? 0] ?? const [],
                  derniere: i == 0,
                  statutDossier: _statut(widget.dossier),
                  role: widget.role,
                  onLire: widget.onLire,
                  onAjouter: widget.onAjouter,
                ),
            const SizedBox(height: 28),
            const SgSectionTitle('Historique'),
            const SizedBox(height: 12),
            if (!pret)
              const SizedBox.shrink()
            else if (snapshot.hasError || snapshot.data!.historique.isEmpty)
              const _CadreVide('Aucune étape enregistrée pour le moment.')
            else
              SgCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: [
                    for (final l in snapshot.data!.historique.reversed) _LigneHistorique(ligne: l),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Petit cadre gris pour un bloc encore vide.
class _CadreVide extends StatelessWidget {
  const _CadreVide(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(texte, style: const TextStyle(fontSize: 13, color: AppColors.grey, height: 1.4)),
    );
  }
}

/// Une version déposée : numéro, date, réponse de l'encadreur et « Lire ».
class _CarteVersion extends StatelessWidget {
  const _CarteVersion({
    required this.version,
    required this.avis,
    required this.derniere,
    required this.statutDossier,
    required this.role,
    required this.onLire,
    this.onAjouter,
  });

  final Map<String, dynamic> version;

  /// Avis reçus par cette version.
  final List<Map<String, dynamic>> avis;

  /// Vrai pour la version la plus récente.
  final bool derniere;

  /// Statut actuel du dossier (pour dire « en cours de lecture »…).
  final String statutDossier;

  /// Rôle du lecteur : chacun lit la situation dans SES mots (l'étudiant
  /// « votre encadreur », l'encadreur « votre avis »).
  final String? role;

  final void Function(int versionId, int numero) onLire;

  /// Étudiant : ajout de la version corrigée (`null` : pas de bouton).
  final VoidCallback? onAjouter;

  /// Vrai si l'encadreur a demandé des corrections sur CETTE version et
  /// qu'aucune version corrigée n'a encore été ajoutée.
  bool get _correctionsAttendues =>
      derniere &&
      statutDossier == 'a_corriger' &&
      avis.isNotEmpty &&
      avis.last['decision']?.toString() == 'defavorable';

  /// Situation d'une version SANS avis, en mots simples (ou `null`).
  (String, SgTone, IconData)? get _sansAvis {
    if (!derniere) {
      return ('Remplacée par une version plus récente', SgTone.neutral, Icons.history_rounded);
    }
    return switch (statutDossier) {
      'brouillon' || 'a_corriger' => (
        role == 'student' ? 'Pas encore envoyée à votre encadreur' : 'Pas encore envoyée par l’étudiant',
        SgTone.warning,
        Icons.outbox_rounded,
      ),
      'soumis' => (
        switch (role) {
          'student' => 'Votre encadreur est en train de la lire',
          'supervisor' => 'En attente de votre avis',
          _ => 'En attente de l’avis de l’encadreur',
        },
        SgTone.info,
        Icons.hourglass_top_rounded,
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(version['id']?.toString() ?? '') ?? 0;
    final numero = int.tryParse(version['version_number']?.toString() ?? '') ?? 0;
    final sansAvis = avis.isEmpty ? _sansAvis : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: derniere ? AppColors.gold : AppColors.line, width: derniere ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: AppColors.goldDeep, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      derniere ? 'Version $numero · la plus récente' : 'Version $numero',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Déposée le ${_fmtDate(version['uploaded_at']?.toString())}',
                      style: const TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
              SgButton(
                'Lire',
                icon: Icons.chrome_reader_mode_outlined,
                dense: true,
                variant: SgBtnVariant.outline,
                onPressed: () => onLire(id, numero),
              ),
            ],
          ),
          if (sansAvis != null) ...[
            const SizedBox(height: 10),
            _Etiquette(sansAvis.$1, tone: sansAvis.$2, icone: sansAvis.$3),
          ],
          for (final a in avis) ...[
            const SizedBox(height: 10),
            _ReponseEncadreur(avis: a),
          ],
          // Juste sous la demande de l'encadreur : de quoi y répondre.
          if (onAjouter != null && _correctionsAttendues) ...[
            const SizedBox(height: 12),
            SgButton(
              'Ajouter la version corrigée',
              icon: Icons.upload_file_rounded,
              variant: SgBtnVariant.outline,
              expand: true,
              onPressed: onAjouter,
            ),
          ],
        ],
      ),
    );
  }
}

/// Étiquette colorée qui passe à la ligne (contrairement à un badge) : une
/// phrase entière reste lisible sur un téléphone de 360 px.
class _Etiquette extends StatelessWidget {
  const _Etiquette(this.texte, {required this.tone, required this.icone});

  final String texte;
  final SgTone tone;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final (couleur, fond) = sgTones(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: couleur),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: TextStyle(color: couleur, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Réponse de l'encadreur sur une version : acceptée (vert) ou corrections
/// demandées (orange), avec son commentaire.
class _ReponseEncadreur extends StatelessWidget {
  const _ReponseEncadreur({required this.avis});

  final Map<String, dynamic> avis;

  @override
  Widget build(BuildContext context) {
    final favorable = avis['decision']?.toString() == 'favorable';
    final commentaire = (avis['comments'] ?? '').toString().trim();
    final date = _fmtDate(avis['created_at']?.toString());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Etiquette(
          favorable ? 'Acceptée par l’encadreur le $date' : 'Corrections demandées le $date',
          tone: favorable ? SgTone.success : SgTone.warning,
          icone: favorable ? Icons.check_circle_rounded : Icons.edit_note_rounded,
        ),
        if (commentaire.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Citation(
            titre: 'Commentaire de l’encadreur',
            texte: commentaire,
            couleur: favorable ? AppColors.success : AppColors.warning,
          ),
        ],
      ],
    );
  }
}

/// Une étape de l'historique, en mots simples.
class _LigneHistorique extends StatelessWidget {
  const _LigneHistorique({required this.ligne});

  final Map<String, dynamic> ligne;

  /// Traduit un événement technique de l'historique en phrase simple.
  static String _evenementLisible(String evenement, String statutApres) => switch (evenement) {
    'nouvelle_version' => 'Nouvelle version ajoutée',
    'soumettre' => 'Rapport envoyé à l’encadreur',
    'avis_favorable' => 'Rapport accepté par l’encadreur',
    'demander_correction' => 'Corrections demandées',
    'autoriser_soutenance' => 'Soutenance autorisée',
    'refuser' => 'Dossier refusé',
    'rouvrir' => 'Dossier rouvert',
    _ => '${evenement.replaceAll('_', ' ')} → ${libelleStatut(statutApres)}',
  };

  @override
  Widget build(BuildContext context) {
    final motif = (ligne['motif'] ?? '').toString().trim();
    final details = [
      _fmtDate(ligne['created_at']?.toString()),
      if (ligne['acteur_nom'] != null) 'par ${ligne['acteur_nom']}',
      if (motif.isNotEmpty) '« $motif »',
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.radio_button_checked_rounded, color: AppColors.goldDeep, size: 18),
      minLeadingWidth: 18,
      title: Text(
        _evenementLisible(ligne['evenement']?.toString() ?? '', ligne['statut_apres']?.toString() ?? ''),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details, style: const TextStyle(fontSize: 12)),
    );
  }
}

// ===========================================================================
// Page complète d'un dossier (encadreur, personnel)
// ===========================================================================

/// Page d'un dossier : situation et décisions, versions avec leurs avis,
/// historique, puis décisions rares et confidentialité (personnel).
///
/// C'est une VRAIE page (et non un panneau flottant) : le geste retour du
/// téléphone la referme, comme dans une messagerie. Une décision touchée ici
/// referme la page et renvoie l'[ActionDossier] à l'écran de liste, qui
/// l'exécute (fenêtre de confirmation, envoi, rechargement).
class _PageDossier extends StatefulWidget {
  const _PageDossier({
    required this.service,
    required this.dossier,
    required this.role,
    required this.onLire,
    required this.onLireVersion,
    required this.onConfidentialite,
  });

  final DocumentService service;
  final Map<String, dynamic> dossier;
  final String? role;

  /// Lecture de la dernière version.
  final VoidCallback onLire;

  /// Lecture d'une version précise (identifiant, numéro).
  final void Function(int versionId, int numero) onLireVersion;

  /// Changement de confidentialité (personnel).
  final Future<void> Function(bool confidentiel) onConfidentialite;

  @override
  State<_PageDossier> createState() => _PageDossierState();
}

/// État de la page : confidentialité affichée.
class _PageDossierState extends State<_PageDossier> {
  late bool _confidentiel = _estConfidentiel(widget.dossier);

  bool get _personnel => widget.role == 'admin' || widget.role == 'responsible';

  /// Décisions rares selon le rôle et l'état (sans répéter les boutons
  /// principaux déjà affichés en haut de la page).
  List<(String, IconData, ActionDossier, bool)> _autresDecisions(SituationDossier situation) {
    final statut = _statut(widget.dossier);
    final liste = [
      if (widget.role == 'admin' && statut == 'soumis') ...[
        ('Accepter à la place de l’encadreur', Icons.check_circle_outline_rounded, ActionDossier.accepter, false),
        ('Corrections à la place de l’encadreur', Icons.edit_note_rounded, ActionDossier.demanderCorrections, false),
      ],
      if (_personnel && const {'soumis', 'a_corriger'}.contains(statut))
        ('Refuser le dossier', Icons.block_rounded, ActionDossier.refuser, true),
      if (_personnel && statut == 'recevable')
        ('Rouvrir le dossier', Icons.lock_open_rounded, ActionDossier.rouvrir, false),
    ];
    return liste.where((d) => !situation.actions.contains(d.$3)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final situation = situationDossier(widget.role, widget.dossier);
    final autres = _autresDecisions(situation);
    final details = _entrepriseEtSujet(widget.dossier);
    return SgPage(
      section: AppSection.documents,
      title: _nomEtudiant(widget.dossier),
      subtitle: details.isEmpty ? null : details,
      maxWidth: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SgCard(
            padding: const EdgeInsets.all(18),
            child: _CorpsDossier(
              dossier: widget.dossier,
              situation: situation,
              role: widget.role,
              enCours: false,
              onAction: (action) => Navigator.pop(context, action),
              onLire: widget.onLire,
            ),
          ),
          const SizedBox(height: 28),
          _SuiviDossier(
            service: widget.service,
            dossier: widget.dossier,
            role: widget.role,
            onLire: widget.onLireVersion,
          ),
          if (autres.isNotEmpty) ...[
            const SizedBox(height: 28),
            const SgSectionTitle('Autres décisions', subtitle: 'À utiliser seulement en cas de besoin.'),
            const SizedBox(height: 12),
            for (final (libelle, icone, action, danger) in autres)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  height: 52,
                  child: SgButton(
                    libelle,
                    icon: icone,
                    expand: true,
                    variant: danger ? SgBtnVariant.danger : SgBtnVariant.outline,
                    onPressed: () => Navigator.pop(context, action),
                  ),
                ),
              ),
          ],
          if (_personnel) ...[
            const SizedBox(height: 18),
            SgCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _confidentiel,
                onChanged: (valeur) async {
                  setState(() => _confidentiel = valeur);
                  await widget.onConfidentialite(valeur);
                },
                title: const Text('Rapport confidentiel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Seuls l’étudiant, ses encadreurs et les personnes habilitées pourront le lire.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ===========================================================================
// Fenêtre de décision
// ===========================================================================

/// Fenêtre « êtes-vous sûr ? » qui dit ce qui va se passer, avec un champ
/// de commentaire facultatif ou obligatoire.
class _DialogueDecision extends StatefulWidget {
  const _DialogueDecision({
    required this.titre,
    required this.message,
    required this.bouton,
    required this.icone,
    this.danger = false,
    this.champ,
    this.champObligatoire = false,
    this.exemple,
    this.longueurMax,
  });

  final String titre;
  final String message;
  final String bouton;
  final IconData icone;

  /// Décision lourde (refus) : couleurs rouges.
  final bool danger;

  /// Libellé du champ de commentaire, ou `null` pour ne pas en afficher.
  final String? champ;

  /// Vrai si le commentaire doit être rempli.
  final bool champObligatoire;

  /// Exemple affiché dans le champ vide.
  final String? exemple;

  /// Nombre maximal de caractères du champ (`null` : sans limite).
  final int? longueurMax;

  @override
  State<_DialogueDecision> createState() => _DialogueDecisionState();
}

/// État de la fenêtre : texte saisi et message d'erreur éventuel.
class _DialogueDecisionState extends State<_DialogueDecision> {
  final _texte = TextEditingController();
  String? _erreur;

  @override
  void dispose() {
    _texte.dispose();
    super.dispose();
  }

  /// Valide : un commentaire obligatoire vide est signalé sous le champ.
  void _valider() {
    final texte = _texte.text.trim();
    if (widget.champ != null && widget.champObligatoire && texte.isEmpty) {
      setState(() => _erreur = 'Écrivez quelques mots : la personne concernée saura quoi faire.');
      return;
    }
    Navigator.pop(context, texte);
  }

  @override
  Widget build(BuildContext context) {
    final couleur = widget.danger ? AppColors.danger : AppColors.goldDeep;
    return AlertDialog(
      icon: Icon(widget.icone, color: couleur, size: 34),
      title: Text(widget.titre, textAlign: TextAlign.center),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.message, style: const TextStyle(fontSize: 14, height: 1.45)),
            if (widget.champ != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _texte,
                autofocus: widget.champObligatoire,
                minLines: 2,
                maxLines: 5,
                maxLength: widget.longueurMax,
                onChanged: (_) {
                  if (_erreur != null) setState(() => _erreur = null);
                },
                decoration: InputDecoration(
                  labelText: widget.champObligatoire
                      ? widget.champ
                      : '${widget.champ} (facultatif)',
                  hintText: widget.exemple,
                  errorText: _erreur,
                  errorMaxLines: 2,
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        SgButton(
          widget.bouton,
          icon: widget.icone,
          variant: widget.danger ? SgBtnVariant.danger : SgBtnVariant.primary,
          onPressed: _valider,
        ),
      ],
    );
  }
}

// ===========================================================================
// Création / modification du dossier (étudiant)
// ===========================================================================

/// Boîte de dialogue de création / modification d'un dossier de stage
/// (entreprise d'accueil et sujet).
class _FolderDialog extends StatefulWidget {
  const _FolderDialog({this.entreprise, this.sujet});

  /// Entreprise actuelle (modification) ou `null` (création).
  final String? entreprise;

  /// Sujet actuel (modification) ou `null` (création).
  final String? sujet;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

/// État du formulaire de dossier.
class _FolderDialogState extends State<_FolderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _entreprise = TextEditingController(text: widget.entreprise ?? '');
  late final _sujet = TextEditingController(text: widget.sujet ?? '');

  @override
  void dispose() {
    _entreprise.dispose();
    _sujet.dispose();
    super.dispose();
  }

  /// Valide puis renvoie le couple (entreprise, sujet).
  void _valider() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (_entreprise.text.trim(), _sujet.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final creation = widget.entreprise == null;
    return AlertDialog(
      title: Text(creation ? 'Créer mon dossier de stage' : 'Mon stage'),
      content: SizedBox(
        width: 460,
        child: SgFormulaire(
          formKey: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _entreprise,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Entreprise d’accueil',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _sujet,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Sujet du stage',
                  prefixIcon: Icon(Icons.subject_rounded),
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 12),
              Text(
                creation
                    ? 'Étape suivante : ajouter votre rapport au format PDF.'
                    : 'Ceci change seulement l’entreprise et le sujet. Pour '
                          'ajouter un rapport, utilisez le bouton « Ajouter » '
                          'en haut de la page.',
                style: const TextStyle(fontSize: 12, color: AppColors.grey, height: 1.35),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        SgButton(creation ? 'Créer le dossier' : 'Enregistrer', onPressed: _valider),
      ],
    );
  }
}
