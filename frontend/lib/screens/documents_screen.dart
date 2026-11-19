/// Dossiers de stage et rapports : écran conçu pour être compris SANS
/// formation.
///
/// Règles d'ergonomie appliquées :
/// 1. **Chaque dossier est une carte toujours visible** (rien à déplier) :
///    qui (nom de l'étudiant), quoi (entreprise, sujet), où on en est (une
///    phrase en mots simples + une barre de 4 étapes).
/// 2. **Un gros bouton par décision possible, et seulement celles-là** :
///    l'étudiant voit « Déposer mon rapport » puis « Envoyer à mon
///    encadreur » ; l'encadreur voit « Lire le rapport », « Accepter le
///    rapport » et « Demander des corrections » ; le responsable voit
///    « Autoriser la soutenance » et « Refuser le dossier ». Les choix
///    viennent de `core/utils/etapes_dossier.dart`.
/// 3. **Ce qui attend l'utilisateur est en haut** (« À traiter
///    maintenant »), le reste en dessous.
/// 4. **Chaque décision est confirmée** par une fenêtre qui dit ce qui va se
///    passer ; un refus ou une demande de corrections exige un commentaire,
///    pour que la personne concernée sache quoi faire.
/// 5. **En haut, un mode d'emploi en 3 petites cartes** (selon le rôle) et,
///    pour l'encadreur et le personnel, des **compteurs cliquables** qui
///    filtrent la liste (À traiter, En cours, Prêts, Refusés, Tous).
/// 6. Les actions rares (confidentialité, anciennes versions, historique)
///    sont rangées dans « Plus d'actions et historique ».
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
import '../core/utils/etapes_dossier.dart';
import '../providers/auth_provider.dart';
import '../services/document_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

/// Taille maximale d'un PDF déposé (identique à la limite du serveur).
const _tailleMaxPdf = 10 * 1024 * 1024;

/// Au-delà de ce nombre de dossiers, un champ de recherche est proposé.
const _seuilRecherche = 6;

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

/// Nom de l'étudiant du dossier (repli : « Dossier n° … »).
String _nomEtudiant(Map<String, dynamic> dossier) {
  final nom = (dossier['student_name'] ?? '').toString().trim();
  return nom.isEmpty ? 'Dossier n° ${_id(dossier)}' : nom;
}

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
  final lettres = mots.take(2).map((m) => m[0].toUpperCase()).join();
  return lettres;
}

/// Couleurs (texte, fond) et icône associées à une [HumeurDossier].
(Color, Color, IconData) _styleHumeur(HumeurDossier humeur) => switch (humeur) {
  HumeurDossier.aFaire => (AppColors.goldDeep, AppColors.goldSoft, Icons.touch_app_rounded),
  HumeurDossier.attente => (AppColors.grey, AppColors.neutralBg, Icons.hourglass_top_rounded),
  HumeurDossier.succes => (AppColors.success, AppColors.successBg, Icons.check_circle_rounded),
  HumeurDossier.alerte => (AppColors.danger, AppColors.dangerBg, Icons.error_outline_rounded),
};

/// Choix faits dans le panneau « Détails et historique ».
enum _ChoixDetails { deposer, refuser, rouvrir, accepter, corrections }

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

  /// Texte de recherche (étudiant, entreprise ou sujet).
  String _recherche = '';

  /// Filtre choisi en haut de l'écran ; `null` = tous les dossiers.
  CategorieDossier? _filtre;

  bool get _estEtudiant => _role == 'student';

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _service = DocumentService(auth.api);
    _role = auth.role;
    _charger();
  }

  // -------------------------------------------------------------------------
  // Chargement
  // -------------------------------------------------------------------------

  /// Charge (ou recharge) la liste des dossiers.
  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final resultat = await _service.getFolders();
      if (!mounted) return;
      setState(() {
        _dossiers = resultat;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = _message(e);
      });
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
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Actions (une méthode par bouton)
  // -------------------------------------------------------------------------

  /// Exécute l'action principale [action] sur [dossier].
  void _agir(ActionDossier action, Map<String, dynamic> dossier) {
    switch (action) {
      case ActionDossier.deposer:
        _deposer(dossier);
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

  /// Étudiant (ou personnel) : choisit un PDF et le dépose ; propose
  /// ensuite à l'étudiant de l'envoyer tout de suite à son encadreur.
  Future<void> _deposer(Map<String, dynamic> dossier) async {
    final id = _id(dossier);
    final statut = dossier['status']?.toString() ?? '';

    // Une nouvelle version d'un dossier accepté relance l'examen (STA05) :
    // on prévient AVANT de choisir le fichier.
    if (statut == 'valide' || statut == 'recevable') {
      final ok = await _confirmer(
        titre: 'Déposer une nouvelle version ?',
        message:
            'Votre rapport a déjà été accepté. Une nouvelle version devra '
            'de nouveau être examinée par votre encadreur.',
        bouton: 'Choisir le fichier',
        icone: Icons.upload_file_rounded,
      );
      if (ok == null || !mounted) return;
    }

    final PlatformFile? fichier;
    try {
      fichier = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (e) {
      if (mounted) SgToast.show(context, _message(e), tone: SgTone.danger);
      return;
    }
    if (fichier == null || !mounted) return;

    // Contrôle immédiat (le serveur vérifie aussi taille et signature).
    final taille = (await fichier.length()) ?? 0;
    if (taille > _tailleMaxPdf) {
      if (mounted) {
        SgToast.show(
          context,
          'Ce fichier dépasse 10 Mo : réduisez-le (par exemple en '
          'compressant les images) puis réessayez.',
          tone: SgTone.danger,
        );
      }
      return;
    }

    final depose = await _executer(
      id,
      () => _service.uploadDocument(id, fichier!),
      'Rapport déposé.',
    );
    if (!depose || !mounted || !_estEtudiant) return;

    // Enchaînement naturel : « déposé » → « l'envoyer maintenant ? ».
    final aJour = _dossierParId(id);
    if (aJour == null) return;
    if (situationDossier(_role, aJour).actions.contains(ActionDossier.envoyer)) {
      await _envoyer(aJour, apresDepot: true);
    }
  }

  /// Étudiant : envoie le rapport à l'encadreur (transition « soumettre »).
  Future<void> _envoyer(Map<String, dynamic> dossier, {bool apresDepot = false}) async {
    final version = numeroDerniereVersion(dossier);
    final texte = await _confirmer(
      titre: apresDepot ? 'L’envoyer maintenant ?' : 'Envoyer votre rapport ?',
      message:
          '${version == null ? 'Votre rapport' : 'La version $version de votre rapport'} '
          'sera envoyée à votre encadreur, qui donnera son avis. Vous pourrez '
          'encore déposer une nouvelle version ensuite.',
      bouton: 'Envoyer à mon encadreur',
      icone: Icons.send_rounded,
    );
    if (texte == null || !mounted) return;
    await _executer(
      _id(dossier),
      () => _service.transition(_id(dossier), 'soumettre'),
      'Rapport envoyé à votre encadreur.',
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
          '${_nomEtudiant(dossier)} verra votre commentaire et déposera une '
          'version corrigée.',
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
            ? 'Dossier créé. Étape suivante : déposer votre rapport.'
            : 'Dossier mis à jour.',
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

  /// Ouvre « Détails et historique » puis exécute le choix éventuel.
  Future<void> _details(Map<String, dynamic> dossier) async {
    final choix = await showModalBottomSheet<_ChoixDetails>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetailsDossier(
        service: _service,
        dossier: dossier,
        role: _role,
        onLire: (versionId, numero) => _lire(dossier, versionId: versionId, numero: numero),
        onConfidentialite: (valeur) => _basculerConfidentialite(dossier, valeur),
      ),
    );
    if (choix == null || !mounted) return;
    switch (choix) {
      case _ChoixDetails.deposer:
        await _deposer(dossier);
      case _ChoixDetails.refuser:
        await _refuser(dossier);
      case _ChoixDetails.rouvrir:
        await _rouvrir(dossier);
      case _ChoixDetails.accepter:
        await _accepter(dossier);
      case _ChoixDetails.corrections:
        await _demanderCorrections(dossier);
    }
  }

  // -------------------------------------------------------------------------
  // Affichage
  // -------------------------------------------------------------------------

  /// Titre de la page, dans les mots du rôle.
  String get _titre => switch (_role) {
    'student' => 'Mon rapport de stage',
    'supervisor' => 'Rapports à examiner',
    _ => 'Dossiers de stage',
  };

  /// Sous-titre : ce que l'utilisateur doit savoir pour commencer.
  String get _sousTitre => switch (_role) {
    'student' => 'Suivez les étapes : à chaque fois, un seul bouton à toucher.',
    'supervisor' => 'Les rapports qui attendent votre avis sont en haut.',
    _ => 'Les dossiers qui attendent une décision sont en haut.',
  };

  @override
  Widget build(BuildContext context) {
    return SgPage(
      section: AppSection.documents,
      title: _titre,
      subtitle: _sousTitre,
      // Étudiant : une seule carte, largeur de lecture confortable ;
      // suivi : jusqu'à deux colonnes de cartes sur un grand écran.
      maxWidth: _estEtudiant ? 860 : 1240,
      // Pas de bouton « Actualiser » isolé : la liste se recharge après
      // chaque décision, et en tirant la page vers le bas.
      onRefresh: _charger,
      child: _chargement
          ? const SgLoading(message: 'Chargement des dossiers…')
          : _erreur != null
          ? SgErrorState(
              title: 'Impossible de charger les dossiers',
              message: _erreur!,
              onRetry: _charger,
            )
          : (_estEtudiant ? _vueEtudiant() : _vueSuivi()),
    );
  }

  /// Carte d'un dossier, branchée sur les actions de l'écran.
  Widget _carte(Map<String, dynamic> dossier) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _CarteDossier(
        dossier: dossier,
        situation: situationDossier(_role, dossier),
        vueEtudiant: _estEtudiant,
        enCours: _enCours.contains(_id(dossier)),
        onAction: (action) => _agir(action, dossier),
        onLire: () => _lire(dossier),
        onDetails: () => _details(dossier),
        // L'étudiant modifie son entreprise ou son sujet sans chercher :
        // le bouton est sur la carte (sauf une fois le dossier prêt).
        onModifier: _estEtudiant && dossier['status']?.toString() != 'recevable'
            ? () => _editerDossier(dossier: dossier)
            : null,
      ),
    );
  }

  /// Liste de cartes : une colonne sur téléphone et tablette étroite, deux
  /// colonnes dès 900 px, pour utiliser la largeur d'un ordinateur.
  Widget _grille(Iterable<Map<String, dynamic>> dossiers) {
    final liste = dossiers.toList();
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final dossier in liste) _carte(dossier)],
          );
        }
        const espace = 16.0;
        final largeur = (contraintes.maxWidth - espace) / 2;
        return Wrap(
          spacing: espace,
          children: [
            for (final dossier in liste) SizedBox(width: largeur, child: _carte(dossier)),
          ],
        );
      },
    );
  }

  /// Étudiant : son dossier (en général un seul), guidé pas à pas.
  Widget _vueEtudiant() {
    if (_dossiers.isEmpty) {
      return SgEmpty(
        icon: Icons.create_new_folder_outlined,
        title: 'Commencez par créer votre dossier',
        message:
            'Indiquez votre entreprise d’accueil et votre sujet. Vous '
            'déposerez ensuite votre rapport.',
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
        _Guide(etapes: guideDuRole(_role)),
        const SizedBox(height: 18),
        for (final dossier in _dossiers) _carte(dossier),
      ],
    );
  }

  /// Libellé d'une catégorie de filtre.
  static String _libelleCategorie(CategorieDossier c) => switch (c) {
    CategorieDossier.aTraiter => 'À traiter',
    CategorieDossier.enCours => 'En cours',
    CategorieDossier.prets => 'Prêts',
    CategorieDossier.refuses => 'Refusés',
  };

  /// Encadreur et personnel : mode d'emploi, compteurs cliquables (filtres),
  /// puis « À traiter maintenant » et les autres dossiers.
  Widget _vueSuivi() {
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
        _Guide(etapes: guideDuRole(_role)),
        const SizedBox(height: 18),
        if (_dossiers.isEmpty)
          SgEmpty(
            icon: Icons.folder_open_outlined,
            title: 'Aucun dossier pour le moment',
            message: _role == 'supervisor'
                ? 'Les dossiers des étudiants que vous encadrez apparaîtront ici.'
                : 'Les dossiers créés par les étudiants apparaîtront ici.',
          )
        else ...[
          // Compteurs cliquables : ils remplacent les statistiques muettes.
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
              _grille(parCategorie[_filtre]!),
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
              _grille(aTraiter),
            if (trouves.length > aTraiter.length) ...[
              const SizedBox(height: 22),
              SgSectionTitle('Autres dossiers (${trouves.length - aTraiter.length})'),
              const SizedBox(height: 12),
              _grille(trouves.where((d) => categorieDossier(_role, d) != CategorieDossier.aTraiter)),
            ],
          ],
          if (trouves.isEmpty && q.isNotEmpty)
            const SgEmpty(
              icon: Icons.search_off_rounded,
              title: 'Aucun résultat',
              message: 'Aucun dossier ne correspond à votre recherche.',
            ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Mode d'emploi (petites cartes en haut de l'écran)
// ===========================================================================

/// Trois petites cartes numérotées qui expliquent l'écran en un coup d'œil.
class _Guide extends StatelessWidget {
  const _Guide({required this.etapes});

  /// Étapes du mode d'emploi (voir `guideDuRole`).
  final List<EtapeGuide> etapes;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, etape) in etapes.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: AppColors.gold, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(etape.titre, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    etape.texte,
                    style: const TextStyle(fontSize: 11.5, height: 1.3, color: AppColors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ===========================================================================
// Carte d'un dossier
// ===========================================================================

/// Carte toujours dépliée : qui, quoi, où on en est, et les boutons utiles.
class _CarteDossier extends StatelessWidget {
  const _CarteDossier({
    required this.dossier,
    required this.situation,
    required this.vueEtudiant,
    required this.enCours,
    required this.onAction,
    required this.onLire,
    required this.onDetails,
    this.onModifier,
  });

  /// Dossier affiché (réponse de /api/internship-folders/).
  final Map<String, dynamic> dossier;

  /// Situation calculée pour le rôle de l'utilisateur.
  final SituationDossier situation;

  /// Vrai pour l'étudiant propriétaire (en-tête : entreprise et sujet).
  final bool vueEtudiant;

  /// Vrai pendant une action sur ce dossier (boutons en attente).
  final bool enCours;

  /// Action principale choisie.
  final ValueChanged<ActionDossier> onAction;

  /// « Lire le rapport ».
  final VoidCallback onLire;

  /// « Détails et historique ».
  final VoidCallback onDetails;

  /// « Modifier » (étudiant : entreprise et sujet), ou `null` si interdit.
  final VoidCallback? onModifier;

  /// Texte du bouton d'une action, adapté au dossier.
  String _libelle(ActionDossier action) => switch (action) {
    ActionDossier.deposer => switch (dossier['status']?.toString()) {
      _ when numeroDerniereVersion(dossier) == null => 'Déposer mon rapport (PDF)',
      'a_corriger' => 'Déposer la version corrigée',
      _ => 'Déposer une nouvelle version',
    },
    ActionDossier.envoyer => 'Envoyer à mon encadreur',
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

  /// Variante du bouton : la 1re action est mise en avant (or), un refus
  /// est en rouge, les autres sont discrètes.
  SgBtnVariant _variante(ActionDossier action, int rang) {
    if (action == ActionDossier.refuser) return SgBtnVariant.danger;
    // L'or est réservé à ce qui est attendu de l'utilisateur ; une action
    // possible mais non urgente (ex. rouvrir un dossier refusé) reste discrète.
    if (!situation.aTraiter) return SgBtnVariant.outline;
    return rang == 0 ? SgBtnVariant.primary : SgBtnVariant.outline;
  }

  @override
  Widget build(BuildContext context) {
    final nom = _nomEtudiant(dossier);
    final entreprise = (dossier['company_name'] ?? '').toString();
    final sujet = (dossier['subject'] ?? '').toString();
    final version = numeroDerniereVersion(dossier);
    final corrections = commentaireCorrections(dossier);
    final confidentiel = dossier['confidentialite']?.toString() == 'confidentiel';
    // Pour décider, on LIT d'abord : le bouton « Lire » passe avant les
    // décisions de l'encadreur et du personnel.
    final lireEnPremier = !vueEtudiant && situation.aTraiter;

    final boutonLire = version == null
        ? null
        : _GrosBouton(
            'Lire le rapport (version $version)',
            icon: confidentiel ? Icons.lock_outline_rounded : Icons.chrome_reader_mode_outlined,
            variant: SgBtnVariant.outline,
            onPressed: onLire,
          );

    return SgCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Qui et quoi -------------------------------------------------
          // Toucher le nom (geste naturel) ouvre « Plus d'actions et
          // historique » : on n'a jamais l'impression qu'il ne se passe rien.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: onDetails,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (vueEtudiant)
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.goldSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.work_outline_rounded, color: AppColors.goldDeep),
                        )
                      else
                        SgAvatar(initials: _initiales(nom), size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vueEtudiant ? (entreprise.isEmpty ? 'Mon stage' : entreprise) : nom,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              vueEtudiant
                                  ? sujet
                                  : [entreprise, sujet].where((s) => s.isNotEmpty).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (onModifier != null) ...[
                const SizedBox(width: 8),
                SgButton(
                  'Modifier',
                  icon: Icons.edit_outlined,
                  dense: true,
                  variant: SgBtnVariant.outline,
                  onPressed: onModifier,
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // --- Où on en est (phrase + étapes) ------------------------------
          _BandeauSituation(situation: situation),
          if (corrections != null &&
              (dossier['status']?.toString() == 'a_corriger' || situation.aTraiter && vueEtudiant)) ...[
            const SizedBox(height: 10),
            _Citation(titre: 'Commentaire de l’encadreur', texte: corrections),
          ],
          if (situation.etape >= 0) ...[
            const SizedBox(height: 14),
            _BarreEtapes(etape: situation.etape),
          ],
          const SizedBox(height: 16),

          // --- Les boutons utiles, et seulement eux ------------------------
          if (lireEnPremier && boutonLire != null) ...[boutonLire, const SizedBox(height: 10)],
          for (final (rang, action) in situation.actions.indexed) ...[
            _GrosBouton(
              _libelle(action),
              icon: _icone(action),
              variant: _variante(action, rang),
              loading: enCours && rang == 0,
              onPressed: enCours ? null : () => onAction(action),
            ),
            const SizedBox(height: 10),
          ],
          if (!lireEnPremier && boutonLire != null) ...[boutonLire, const SizedBox(height: 10)],
          if (version == null && !vueEtudiant)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Aucun rapport déposé pour le moment.',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onDetails,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: Text(
                vueEtudiant ? 'Versions et historique' : 'Plus d’actions et historique',
              ),
              style: TextButton.styleFrom(foregroundColor: AppColors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

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
  const _Citation({required this.titre, required this.texte});

  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(left: BorderSide(color: AppColors.warning, width: 3)),
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
// Panneau « Détails et historique »
// ===========================================================================

/// Panneau inférieur : versions du rapport (avec leurs avis), historique
/// des étapes, et actions rares selon le rôle.
class _DetailsDossier extends StatefulWidget {
  const _DetailsDossier({
    required this.service,
    required this.dossier,
    required this.role,
    required this.onLire,
    required this.onConfidentialite,
  });

  final DocumentService service;
  final Map<String, dynamic> dossier;
  final String? role;

  /// Lecture d'une version précise (identifiant, numéro).
  final void Function(int versionId, int numero) onLire;

  /// Changement de confidentialité (personnel).
  final Future<void> Function(bool confidentiel) onConfidentialite;

  @override
  State<_DetailsDossier> createState() => _DetailsDossierState();
}

/// Données du panneau, chargées à son ouverture.
class _DonneesDetails {
  const _DonneesDetails(this.versions, this.avis, this.historique);

  final List<Map<String, dynamic>> versions;
  final Map<int, List<Map<String, dynamic>>> avis;
  final List<Map<String, dynamic>> historique;
}

/// État du panneau : chargement et confidentialité affichée.
class _DetailsDossierState extends State<_DetailsDossier> {
  late final Future<_DonneesDetails> _donnees = _chargerDonnees();
  late bool _confidentiel = widget.dossier['confidentialite']?.toString() == 'confidentiel';

  int get _id => int.tryParse(widget.dossier['id']?.toString() ?? '') ?? 0;
  String get _statut => widget.dossier['status']?.toString() ?? '';
  bool get _personnel => widget.role == 'admin' || widget.role == 'responsible';

  /// Versions, avis (en un appel) et historique du dossier.
  Future<_DonneesDetails> _chargerDonnees() async {
    final versions = await widget.service.getDocuments(_id);
    versions.sort(
      (a, b) => (int.tryParse(b['version_number']?.toString() ?? '') ?? 0)
          .compareTo(int.tryParse(a['version_number']?.toString() ?? '') ?? 0),
    );
    final ids = versions.map((v) => int.tryParse(v['id']?.toString() ?? '') ?? 0);
    // Un rôle sans droit de lecture des avis reçoit simplement une liste vide.
    final avis = await widget.service.getReviewsParVersion(ids).catchError(
      (_) => <int, List<Map<String, dynamic>>>{},
    );
    final historique = await widget.service.historique(_id);
    return _DonneesDetails(versions, avis, historique);
  }

  /// Actions rares proposées selon le rôle et l'état du dossier.
  List<(String, IconData, _ChoixDetails, bool)> get _autresActions {
    final etudiant = widget.role == 'student';
    return [
      if (etudiant && const {'soumis', 'valide', 'recevable'}.contains(_statut))
        ('Déposer une nouvelle version', Icons.upload_file_rounded, _ChoixDetails.deposer, false),
      if (widget.role == 'admin' && _statut == 'soumis') ...[
        ('Accepter à la place de l’encadreur', Icons.check_circle_outline_rounded, _ChoixDetails.accepter, false),
        ('Demander des corrections', Icons.edit_note_rounded, _ChoixDetails.corrections, false),
      ],
      if (_personnel && const {'soumis', 'a_corriger'}.contains(_statut))
        ('Refuser le dossier', Icons.block_rounded, _ChoixDetails.refuser, true),
      if (_personnel && _statut == 'recevable')
        ('Rouvrir le dossier', Icons.lock_open_rounded, _ChoixDetails.rouvrir, false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final nom = _nomEtudiant(widget.dossier);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              widget.role == 'student' ? 'Mon dossier' : nom,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              [widget.dossier['company_name'], widget.dossier['subject']]
                  .where((v) => (v ?? '').toString().isNotEmpty)
                  .join(' · '),
              style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            const SizedBox(height: 18),
            FutureBuilder<_DonneesDetails>(
              future: _donnees,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SgLoading(message: 'Chargement…');
                }
                if (snapshot.hasError) {
                  return SgBanner(message: _message(snapshot.error!), tone: SgTone.danger);
                }
                return _contenu(snapshot.data!);
              },
            ),
            if (_autresActions.isNotEmpty) ...[
              const SizedBox(height: 18),
              const SgOverline('Autres actions'),
              const SizedBox(height: 8),
              for (final (libelle, icone, choix, danger) in _autresActions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SgButton(
                    libelle,
                    icon: icone,
                    expand: true,
                    variant: danger ? SgBtnVariant.danger : SgBtnVariant.outline,
                    onPressed: () => Navigator.pop(context, choix),
                  ),
                ),
            ],
            if (_personnel) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _confidentiel,
                onChanged: (valeur) async {
                  setState(() => _confidentiel = valeur);
                  await widget.onConfidentialite(valeur);
                },
                title: const Text('Rapport confidentiel', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Seuls l’étudiant, ses encadreurs et les personnes habilitées pourront le lire.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Versions (chacune avec ses avis et un bouton « Lire »), puis historique.
  Widget _contenu(_DonneesDetails d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SgOverline('Versions du rapport'),
        const SizedBox(height: 8),
        if (d.versions.isEmpty)
          const Text('Aucun rapport déposé pour le moment.', style: TextStyle(fontSize: 13, color: AppColors.grey))
        else
          for (final v in d.versions) _ligneVersion(v, d.avis),
        const SizedBox(height: 16),
        const SgOverline('Historique'),
        const SizedBox(height: 6),
        if (d.historique.isEmpty)
          const Text('Aucune étape enregistrée pour le moment.', style: TextStyle(fontSize: 13, color: AppColors.grey))
        else
          for (final l in d.historique.reversed) _ligneHistorique(l),
      ],
    );
  }

  /// Une version : numéro, date, avis reçus et bouton « Lire ».
  Widget _ligneVersion(Map<String, dynamic> v, Map<int, List<Map<String, dynamic>>> avis) {
    final id = int.tryParse(v['id']?.toString() ?? '') ?? 0;
    final numero = int.tryParse(v['version_number']?.toString() ?? '') ?? 0;
    final avisVersion = avis[id] ?? const [];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Version $numero', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      'Déposée le ${_fmtDate(v['uploaded_at']?.toString())}',
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
                onPressed: () => widget.onLire(id, numero),
              ),
            ],
          ),
          for (final a in avisVersion) ...[
            const SizedBox(height: 8),
            _ligneAvis(a),
          ],
        ],
      ),
    );
  }

  /// Un avis : favorable (vert) ou corrections demandées (orange).
  Widget _ligneAvis(Map<String, dynamic> a) {
    final favorable = a['decision']?.toString() == 'favorable';
    final commentaire = (a['comments'] ?? '').toString().trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          favorable ? Icons.check_circle_rounded : Icons.edit_note_rounded,
          size: 18,
          color: favorable ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${favorable ? 'Accepté' : 'Corrections demandées'} le '
            '${_fmtDate(a['created_at']?.toString())}'
            '${commentaire.isEmpty ? '' : ' : « $commentaire »'}',
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }

  /// Une étape de l'historique, en mots simples.
  Widget _ligneHistorique(Map<String, dynamic> l) {
    final motif = (l['motif'] ?? '').toString().trim();
    final details = [
      _fmtDate(l['created_at']?.toString()),
      if (l['acteur_nom'] != null) 'par ${l['acteur_nom']}',
      if (motif.isNotEmpty) '« $motif »',
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.radio_button_checked_rounded, color: AppColors.goldDeep, size: 18),
      title: Text(
        _evenementLisible(l['evenement']?.toString() ?? '', l['statut_apres']?.toString() ?? ''),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details, style: const TextStyle(fontSize: 12)),
    );
  }

  /// Traduit un événement technique de l'historique en phrase simple.
  String _evenementLisible(String evenement, String statutApres) => switch (evenement) {
    'nouvelle_version' => 'Nouvelle version déposée',
    'soumettre' => 'Rapport envoyé à l’encadreur',
    'avis_favorable' => 'Rapport accepté par l’encadreur',
    'demander_correction' => 'Corrections demandées',
    'autoriser_soutenance' => 'Soutenance autorisée',
    'refuser' => 'Dossier refusé',
    'rouvrir' => 'Dossier rouvert',
    _ => '${evenement.replaceAll('_', ' ')} → ${libelleStatut(statutApres)}',
  };
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
      title: Text(creation ? 'Créer mon dossier de stage' : 'Modifier mon dossier'),
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
              if (creation) ...[
                const SizedBox(height: 12),
                const Text(
                  'Étape suivante : déposer votre rapport au format PDF.',
                  style: TextStyle(fontSize: 12, color: AppColors.grey),
                ),
              ],
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
