/// Tableau de bord : page d'accueil de l'espace connecté.
///
/// Conception volontairement simple, identique pour tous les profils :
///   1. une carte « À la une » avec l'information la plus utile du moment
///      (prochaine soutenance, état du dossier…), qui s'ouvre au toucher ;
///   2. une grille de grandes cartes « Vos espaces » : une carte par module,
///      avec une information en direct ; toucher la carte ouvre le module.
/// Ce qui attend l'utilisateur est dit en toutes lettres avec un bouton
/// (« 3 rapports attendent votre avis », « Déposez votre rapport ») : les
/// règles viennent de `core/utils/etapes_dossier.dart`, comme dans l'écran
/// des dossiers, pour que l'accueil et l'écran disent la même chose.
/// Pas de tableaux ni de listes entassées : le détail se trouve dans chaque
/// module. Les cartes sont larges pour un usage confortable à une main.
library;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../core/utils/etapes_dossier.dart';
import '../models/defense.dart';
import '../providers/auth_provider.dart';
import '../providers/planning_store.dart';
import '../services/conflict_report.dart';
import '../services/document_service.dart';
import '../services/planning_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import 'defense_detail_screen.dart';
import 'defense_form_screen.dart';

/// Écran du tableau de bord.
class DashboardScreen extends StatefulWidget {
  /// Crée le tableau de bord.
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

/// État du tableau de bord : charge le planning et les dossiers de stage.
class _DashboardScreenState extends State<DashboardScreen> {
  /// Dossiers de stage visibles (pour « à traiter »), `null` tant qu'ils ne
  /// sont pas chargés ou si le chargement a échoué (l'accueil reste utile).
  List<Map<String, dynamic>>? _dossiers;

  @override
  void initState() {
    super.initState();
    // Chargement après la première image : le contexte est alors prêt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(force: false);
    });
  }

  /// Vrai si le rôle courant a accès au planning des soutenances.
  bool _voitPlanning(AuthProvider auth) =>
      auth.canManage || auth.role == 'jury';

  /// Vrai si le rôle courant suit des dossiers de stage.
  bool _suitDossiers(AuthProvider auth) => const {
    'student',
    'supervisor',
    'admin',
    'responsible',
    // Le jury : rapports des soutenances où il siège, à lire avant.
    'jury',
  }.contains(auth.role);

  /// Charge (ou recharge si [force]) le planning et les dossiers.
  Future<void> _load({required bool force}) async {
    final auth = context.read<AuthProvider>();
    // Le profil (dossier, soutenance de l'étudiant) est aussi rafraîchi.
    if (force) await auth.fetchUserProfile();
    if (!mounted) return;
    await Future.wait([_chargerPlanning(auth, force), _chargerDossiers(auth)]);
  }

  /// Charge les dossiers de stage ; une erreur est silencieuse (l'accueil
  /// affiche alors un texte général au lieu du nombre de dossiers).
  Future<void> _chargerDossiers(AuthProvider auth) async {
    if (!_suitDossiers(auth)) return;
    try {
      final dossiers = await DocumentService(auth.api).getFolders();
      if (mounted) setState(() => _dossiers = dossiers);
    } catch (_) {
      // Hors ligne ou serveur indisponible : rien de bloquant ici.
    }
  }

  /// Charge (ou recharge si [force]) le planning partagé.
  Future<void> _chargerPlanning(AuthProvider auth, bool force) async {
    if (!_voitPlanning(auth)) return;
    final service = PlanningService(auth.api);
    if (force) {
      try {
        await PlanningStore.refresh(service, loadCatalog: auth.canManage);
      } catch (_) {
        // L'erreur est publiée dans PlanningStore.error et affichée.
      }
    } else {
      await PlanningStore.ensureLoaded(service, loadCatalog: auth.canManage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Prénom seul pour une salutation plus naturelle.
    final prenom = auth.displayName.split(' ').first;

    return SgPage(
      section: AppSection.dashboard,
      title: 'Bonjour, $prenom',
      subtitle:
          '${Session.roleLabel(auth.role)} · année universitaire '
          '${anneeScolaire(DateTime.now())}',
      maxWidth: 1100,
      onRefresh: () => _load(force: true),
      // Les trois états partagés du planning pilotent l'affichage.
      child: ValueListenableBuilder<bool>(
        valueListenable: PlanningStore.loading,
        builder: (context, loading, _) => ValueListenableBuilder<String?>(
          valueListenable: PlanningStore.error,
          builder: (context, error, _) => ValueListenableBuilder<List<Defense>>(
            valueListenable: PlanningStore.defenses,
            builder: (context, defenses, _) {
              final etat = _EtatAccueil(
                auth: auth,
                defenses: defenses,
                loading: loading,
                dossiers: _dossiers,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null && _voitPlanning(auth)) ...[
                    SgBanner(
                      message: 'Le planning n’a pas pu être chargé : $error',
                      tone: SgTone.danger,
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Personnel : décisions en attente, avant le planning.
                  if (auth.canManage && etat.aTraiter > 0) ...[
                    _CarteAFaire(nombre: etat.aTraiter),
                    const SizedBox(height: 16),
                  ],
                  _CarteUne(etat: etat),
                  const SizedBox(height: 28),
                  const SgSectionTitle(
                    'Vos espaces',
                    subtitle: 'Touchez une carte pour ouvrir le module.',
                  ),
                  const SizedBox(height: 14),
                  _GrilleEspaces(etat: etat),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Données calculées pour l'accueil
// ===========================================================================

/// Regroupe les informations affichées par l'accueil, calculées une fois.
class _EtatAccueil {
  _EtatAccueil({
    required this.auth,
    required List<Defense> defenses,
    required this.loading,
    this.dossiers,
  }) {
    final now = DateTime.now();
    final debutJour = DateTime(now.year, now.month, now.day);
    // Soutenances à venir (aujourd'hui inclus, hors annulées), triées.
    aVenir =
        defenses.where((d) {
          final p = parseDefenseDate(d.date);
          return p != null && !p.isBefore(debutJour) && d.status != 'annule';
        }).toList()..sort(
          (a, b) =>
              '${a.date}${a.startTime}'.compareTo('${b.date}${b.startTime}'),
        );
    aujourdhui = aVenir
        .where((d) => parseDefenseDate(d.date) == debutJour)
        .length;
    conflits = auth.canManage ? ConflictScanner.scan(defenses).length : 0;
    aTraiter = dossiers == null
        ? 0
        : dossiers!.where((d) => situationDossier(auth.role, d).aTraiter).length;
    situationEtudiant = auth.role == 'student' && (dossiers?.isNotEmpty ?? false)
        ? situationDossier('student', dossiers!.first)
        : null;
  }

  /// Dossiers de stage visibles, ou `null` s'ils ne sont pas chargés.
  final List<Map<String, dynamic>>? dossiers;

  /// Nombre de dossiers qui attendent une action de l'utilisateur.
  late final int aTraiter;

  /// Étudiant : situation de son dossier (prochaine étape), sinon `null`.
  late final SituationDossier? situationEtudiant;

  /// Session courante (rôle, profil).
  final AuthProvider auth;

  /// Vrai pendant le chargement du planning.
  final bool loading;

  /// Soutenances à venir, par ordre chronologique.
  late final List<Defense> aVenir;

  /// Nombre de soutenances du jour.
  late final int aujourdhui;

  /// Nombre de conflits détectés (personnel uniquement).
  late final int conflits;

  /// Rôle de l'utilisateur.
  String? get role => auth.role;
}

// ===========================================================================
// Carte « À la une »
// ===========================================================================

/// Grande carte noire et or : l'information la plus utile selon le rôle.
class _CarteUne extends StatelessWidget {
  const _CarteUne({required this.etat});

  /// Données de l'accueil.
  final _EtatAccueil etat;

  @override
  Widget build(BuildContext context) {
    return switch (etat.role) {
      'admin' || 'responsible' || 'jury' => _uneSoutenance(context),
      'student' => _uneEtudiant(context),
      _ => _uneEncadreur(context),
    };
  }

  /// Personnel et jury : prochaine soutenance (ou invitation à planifier).
  Widget _uneSoutenance(BuildContext context) {
    final prochaine = etat.aVenir.isEmpty ? null : etat.aVenir.first;
    final personnel = etat.auth.canManage;

    if (prochaine == null) {
      return _CadreUne(
        surtitre: 'À LA UNE',
        titre: etat.loading
            ? 'Chargement du planning…'
            : 'Aucune soutenance à venir',
        texte: personnel
            ? 'Planifiez une soutenance pour remplir le calendrier.'
            : 'Aucune soutenance n’est encore affectée à votre jury.',
        action: personnel
            ? SgButton(
                'Nouvelle soutenance',
                icon: Icons.add_rounded,
                onPressed: () => pushPage(context, const DefenseFormScreen()),
              )
            : null,
      );
    }

    final date = parseDefenseDate(prochaine.date);
    return _CadreUne(
      surtitre: 'PROCHAINE SOUTENANCE',
      titre: prochaine.studentName,
      texte: prochaine.subject,
      onTap: () => pushPage(context, DefenseDetailScreen(defense: prochaine)),
      details: [
        (Icons.event_rounded, date == null ? prochaine.date : longDate(date)),
        (
          Icons.schedule_rounded,
          '${prochaine.startTime} – ${prochaine.endTime}',
        ),
        (Icons.meeting_room_outlined, prochaine.roomName),
        (Icons.groups_2_outlined, prochaine.juryName),
      ],
      // Pastilles d'alerte : soutenances du jour et conflits à traiter.
      pastilles: [
        if (etat.aujourdhui > 0)
          SgBadge('${etat.aujourdhui} aujourd’hui', tone: SgTone.gold),
        if (etat.conflits > 0)
          SgBadge('${etat.conflits} conflit(s)', tone: SgTone.danger),
      ],
    );
  }

  /// Étudiant : son dossier et sa soutenance (ou invitation à créer le dossier).
  Widget _uneEtudiant(BuildContext context) {
    final user = etat.auth.user ?? const <String, dynamic>{};
    final statut = user['folder_status']?.toString();
    final s = user['defense'] is Map
        ? Map<String, dynamic>.from(user['defense'] as Map)
        : null;

    if (statut == null) {
      return _CadreUne(
        surtitre: 'MON STAGE',
        titre: 'Créez votre dossier de stage',
        texte: 'Indiquez votre entreprise d’accueil et votre sujet pour commencer.',
        action: SgButton(
          'Créer mon dossier',
          icon: Icons.create_new_folder_outlined,
          onPressed: () => navigateToSection(context, AppSection.documents),
        ),
      );
    }

    final debut = DateTime.tryParse(s?['slot_start']?.toString() ?? '')
        ?.toLocal();
    final fin = DateTime.tryParse(s?['slot_end']?.toString() ?? '')?.toLocal();
    String heure(DateTime? d) => d == null
        ? '--:--'
        : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final note = s?['final_average']?.toString();
    // Prochaine étape du dossier, dite en toutes lettres sur un bouton.
    final situation = etat.situationEtudiant;

    return _CadreUne(
      surtitre: 'MON STAGE',
      titre: user['folder_company']?.toString() ?? 'Mon dossier',
      texte: user['folder_subject']?.toString() ?? '',
      onTap: () => navigateToSection(context, AppSection.profil),
      action: situation != null && situation.aTraiter
          ? SgButton(
              situation.titre,
              icon: Icons.arrow_forward_rounded,
              onPressed: () => navigateToSection(context, AppSection.documents),
            )
          : null,
      pastilles: [
        SgStatusBadge(statut),
        if (note != null)
          SgBadge(
            'Note : ${note.replaceAll('.', ',')} / 20',
            tone: SgTone.gold,
            dot: false,
          ),
      ],
      details: s == null
          ? [(Icons.event_busy_outlined, 'Soutenance pas encore planifiée')]
          : [
              (Icons.event_rounded, debut == null ? '—' : longDate(debut)),
              (Icons.schedule_rounded, '${heure(debut)} – ${heure(fin)}'),
              (Icons.meeting_room_outlined, s['room_name']?.toString() ?? ''),
            ],
    );
  }

  /// Encadreur : nombre de rapports qui attendent son avis, et un bouton.
  Widget _uneEncadreur(BuildContext context) {
    final n = etat.aTraiter;
    final (titre, texte) = switch (etat.dossiers) {
      null => (
        'Vos rapports à examiner',
        'Lisez les rapports envoyés par vos étudiants et donnez votre avis.',
      ),
      _ when n == 0 => (
        'Aucun rapport en attente',
        'Les rapports envoyés par vos étudiants apparaîtront ici.',
      ),
      _ when n == 1 => (
        '1 rapport attend votre avis',
        'Lisez-le, puis acceptez-le ou demandez des corrections.',
      ),
      _ => (
        '$n rapports attendent votre avis',
        'Lisez-les, puis acceptez-les ou demandez des corrections.',
      ),
    };
    return _CadreUne(
      surtitre: 'ENCADREMENT',
      titre: titre,
      texte: texte,
      action: SgButton(
        n > 0 ? 'Examiner les rapports' : 'Voir mes dossiers',
        icon: Icons.arrow_forward_rounded,
        onPressed: () => navigateToSection(context, AppSection.documents),
      ),
    );
  }
}

/// Personnel : rappel des dossiers qui attendent une décision (autoriser
/// ou refuser la soutenance), avec un accès direct à l'écran des dossiers.
class _CarteAFaire extends StatelessWidget {
  const _CarteAFaire({required this.nombre});

  /// Nombre de dossiers en attente de décision.
  final int nombre;

  @override
  Widget build(BuildContext context) {
    return SgCard(
      padding: const EdgeInsets.all(16),
      onTap: () => navigateToSection(context, AppSection.documents),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.touch_app_rounded, color: AppColors.goldDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre == 1
                      ? '1 dossier attend votre décision'
                      : '$nombre dossiers attendent votre décision',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Autorisez la soutenance ou refusez le dossier.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: AppColors.goldDeep),
        ],
      ),
    );
  }
}

/// Mise en forme commune de la carte « À la une » (fond noir, accents or).
class _CadreUne extends StatelessWidget {
  const _CadreUne({
    required this.surtitre,
    required this.titre,
    required this.texte,
    this.details = const [],
    this.pastilles = const [],
    this.action,
    this.onTap,
  });

  /// Petit titre doré en capitales.
  final String surtitre;

  /// Titre principal.
  final String titre;

  /// Texte d'accompagnement.
  final String texte;

  /// Lignes « icône + texte » (date, horaires, salle…).
  final List<(IconData, String)> details;

  /// Badges affichés sous le titre.
  final List<Widget> pastilles;

  /// Bouton d'action facultatif.
  final Widget? action;

  /// Ouverture du détail au toucher de la carte (facultatif).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rayon = BorderRadius.circular(AppTheme.radius + 6);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppTheme.inkGradient,
          borderRadius: rayon,
        ),
        child: InkWell(
          borderRadius: rayon,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        surtitre,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    // Flèche : indique que la carte s'ouvre au toucher.
                    if (onTap != null)
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: AppColors.gold,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  titre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                if (texte.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    texte,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ],
                if (pastilles.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: pastilles),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  // Détails sur une ou plusieurs lignes selon la largeur.
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      for (final (icone, valeur) in details)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icone, size: 16, color: AppColors.gold),
                            const SizedBox(width: 6),
                            // Flexible : sur un téléphone étroit, une date
                            // longue passe à la ligne au lieu de déborder.
                            Flexible(
                              child: Text(
                                valeur,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 18), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Grille « Vos espaces »
// ===========================================================================

/// Grille de cartes-modules : 2 par ligne sur téléphone, 3 sur tablette,
/// 4 sur grand écran.
class _GrilleEspaces extends StatelessWidget {
  const _GrilleEspaces({required this.etat});

  /// Données de l'accueil.
  final _EtatAccueil etat;

  /// Titre de la carte, formulé selon le rôle quand c'est utile.
  String _titre(AppSection s) => switch (s) {
    AppSection.documents when etat.role == 'student' =>
      'Mon dossier et mes documents',
    AppSection.documents when etat.role == 'supervisor' => 'Rapports à examiner',
    AppSection.documents when etat.role == 'jury' => 'Rapports à lire',
    AppSection.planning when etat.role == 'jury' => 'Mon planning de jury',
    AppSection.campaigns => 'Gestion des campagnes',
    AppSection.accounts => 'Comptes et rôles',
    _ => s.label,
  };

  /// Information en direct affichée sous le titre, avec sa tonalité.
  (String, SgTone?) _info(AppSection s) {
    final pret = !etat.loading || etat.aVenir.isNotEmpty;
    return switch (s) {
      AppSection.planning when pret => (
        '${etat.aVenir.length} soutenance(s) à venir',
        null,
      ),
      AppSection.conflicts when pret =>
        etat.conflits > 0
            ? ('${etat.conflits} à traiter', SgTone.danger)
            : ('Aucun conflit', SgTone.success),
      AppSection.rooms when PlanningStore.rooms.isNotEmpty => (
        '${PlanningStore.rooms.length} salle(s) active(s)',
        null,
      ),
      AppSection.jury when PlanningStore.juryMembers.isNotEmpty => (
        '${PlanningStore.juryMembers.length} membre(s) de jury',
        null,
      ),
      AppSection.documents when etat.role == 'jury' && etat.dossiers != null => (
        etat.dossiers!.isEmpty
            ? 'Aucun rapport pour le moment'
            : '${etat.dossiers!.length} rapport(s) à lire avant la soutenance',
        etat.dossiers!.isEmpty ? null : SgTone.gold,
      ),
      AppSection.documents when etat.role != 'student' && etat.aTraiter > 0 => (
        etat.role == 'supervisor'
            ? '${etat.aTraiter} à examiner'
            : '${etat.aTraiter} à décider',
        SgTone.gold,
      ),
      // Les chiffres utiles des dossiers sont ici, sur l'accueil, plutôt
      // qu'en cartes muettes en haut de l'écran des dossiers.
      AppSection.documents when etat.role != 'student' && etat.dossiers != null => (
        '${etat.dossiers!.length} dossier(s) · rien à traiter',
        SgTone.success,
      ),
      AppSection.documents
          when etat.role == 'student' &&
              etat.auth.user?['folder_status'] != null =>
        (
          'Dossier : ${libelleStatut(etat.auth.user!['folder_status'].toString())}',
          sgToneForStatus(etat.auth.user!['folder_status'].toString()),
        ),
      _ => (s.description, null),
    };
  }

  @override
  Widget build(BuildContext context) {
    final sections = Session.sections(etat.role)
        .where((s) => s != AppSection.dashboard)
        .toList();
    if (sections.isEmpty) {
      return const SgEmpty(
        icon: Icons.lock_outline_rounded,
        title: 'Aucun module disponible',
        message: 'Le rôle de ce compte n’est pas reconnu. Contactez un administrateur.',
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final parLigne = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 600 ? 3 : 2);
        final largeur = (c.maxWidth - (parLigne - 1) * gap) / parLigne;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in sections)
              SizedBox(
                width: largeur,
                child: _CarteEspace(
                  section: s,
                  titre: _titre(s),
                  info: _info(s),
                  onTap: () => navigateToSection(context, s),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Carte d'un module : grande cible tactile, icône, titre et information.
class _CarteEspace extends StatelessWidget {
  const _CarteEspace({
    required this.section,
    required this.titre,
    required this.info,
    required this.onTap,
  });

  /// Module ouvert par la carte.
  final AppSection section;

  /// Titre affiché.
  final String titre;

  /// Information en direct et sa tonalité (null = texte gris).
  final (String, SgTone?) info;

  /// Action au toucher.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (texte, ton) = info;
    final couleurInfo = ton == null ? AppColors.grey : sgTones(ton).$1;
    return SgCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        // Hauteur minimale homogène : grille régulière, cibles confortables.
        constraints: const BoxConstraints(minHeight: 118),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.goldSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(section.iconActive, color: AppColors.goldDeep),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.greyLight,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              titre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              texte,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: couleurInfo,
                fontWeight: ton == null ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
