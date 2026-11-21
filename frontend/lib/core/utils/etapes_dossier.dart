/// Étapes à suivre pour un dossier de stage, vues par l'étudiant,
/// l'encadreur, le personnel et le jury : « que dois-je faire maintenant ? ».
///
/// Partagé par l'écran « Dossiers » et le tableau de bord, pour que les deux
/// disent toujours la même chose avec les mêmes mots.
library;

/// Actions principales qu'un utilisateur peut faire sur un dossier.
enum ActionDossier {
  /// Étudiant : déposer le rapport PDF (ou sa version corrigée).
  deposer,

  /// Étudiant : envoyer le rapport à l'encadreur (transition « soumettre »).
  envoyer,

  /// Encadreur : accepter la dernière version (avis favorable).
  accepter,

  /// Encadreur : demander des corrections (avis défavorable, commentaire
  /// obligatoire pour que l'étudiant sache quoi corriger).
  demanderCorrections,

  /// Personnel : autoriser la soutenance (dossier « prêt »).
  autoriser,

  /// Personnel : refuser le dossier (motif obligatoire).
  refuser,

  /// Personnel : rouvrir un dossier refusé (motif obligatoire).
  rouvrir,
}

/// Catégories proposées en filtres cliquables en haut de l'écran.
enum CategorieDossier {
  /// Une action de l'utilisateur est attendue.
  aTraiter,

  /// Le dossier avance, quelqu'un d'autre doit agir.
  enCours,

  /// Prêt pour la soutenance.
  prets,

  /// Refusé.
  refuses,
}

/// Catégorie du [dossier] pour un utilisateur de rôle [role].
CategorieDossier categorieDossier(String? role, Map<String, dynamic> dossier) {
  if (situationDossier(role, dossier).aTraiter) return CategorieDossier.aTraiter;
  return switch (dossier['status']?.toString()) {
    'recevable' => CategorieDossier.prets,
    'rejete' => CategorieDossier.refuses,
    _ => CategorieDossier.enCours,
  };
}

/// Vrai si l'étudiant peut déposer une nouvelle version de son rapport.
///
/// Le bouton de dépôt reste TOUJOURS visible sur sa page (il ne doit jamais
/// chercher « où ajouter mon rapport ») ; seul un dossier refusé l'en
/// empêche, car il doit d'abord être rouvert par le responsable.
bool peutDeposer(String? role, Map<String, dynamic> dossier) =>
    role == 'student' && dossier['status']?.toString() != 'rejete';

/// Vrai si, juste après avoir ajouté un fichier, l'étudiant peut l'envoyer
/// (ou le renvoyer) à son encadreur dans la foulée : dossier en brouillon ou
/// corrections demandées. Ailleurs, l'ajout suffit (un dossier déjà envoyé
/// ou accepté repasse de lui-même devant l'encadreur, voir STA05).
bool envoiPossible(Map<String, dynamic> dossier) =>
    const {'brouillon', 'a_corriger'}.contains(dossier['status']?.toString());

/// Vrai si la dernière version a été ajoutée mais PAS encore envoyée à
/// l'encadreur (brouillon, ou version corrigée ajoutée après l'avis).
bool versionNonEnvoyee(Map<String, dynamic> dossier) {
  if (numeroDerniereVersion(dossier) == null) return false;
  return switch (dossier['status']?.toString()) {
    'brouillon' => true,
    'a_corriger' => !_avisSurDerniereVersion(dossier),
    _ => false,
  };
}

/// Texte du grand bouton « Ajouter » de l'étudiant, dans ses mots :
/// premier dépôt, version corrigée demandée, remplacement d'un fichier pas
/// encore envoyé, ou nouvelle version.
String libelleAjout(Map<String, dynamic> dossier) {
  if (numeroDerniereVersion(dossier) == null) return 'Ajouter mon rapport';
  if (dossier['status']?.toString() == 'a_corriger' && _avisSurDerniereVersion(dossier)) {
    return 'Ajouter la version corrigée';
  }
  if (versionNonEnvoyee(dossier)) return 'Remplacer par un autre fichier';
  return 'Ajouter une nouvelle version';
}

/// Bouton de l'accueil de l'étudiant : sa prochaine étape en deux ou trois
/// mots (il mène à la page du rapport), ou `null` s'il n'a rien à faire.
String? boutonAccueilEtudiant(Map<String, dynamic> dossier) {
  final situation = situationDossier('student', dossier);
  if (!situation.aTraiter || situation.actions.isEmpty) return null;
  final correction = dossier['status']?.toString() == 'a_corriger';
  return switch (situation.actions.first) {
    ActionDossier.envoyer => correction ? 'Renvoyer ma version corrigée' : 'Envoyer mon rapport',
    _ => correction ? 'Corriger mon rapport' : 'Ajouter mon rapport',
  };
}

/// Mot laissé par l'étudiant à son encadreur en envoyant son rapport (ex.
/// « J'ai repris le chapitre 2 »), tant que le rapport attend l'avis ;
/// `null` sinon.
String? messageEtudiant(Map<String, dynamic> dossier) {
  if (dossier['status']?.toString() != 'soumis') return null;
  final etape = dossier['derniere_etape'];
  if (etape is! Map || etape['evenement']?.toString() != 'soumettre') return null;
  final texte = (etape['motif'] ?? '').toString().trim();
  return texte.isEmpty ? null : texte;
}

/// Couleur de la situation, du point de vue de l'utilisateur.
enum HumeurDossier {
  /// Une action de l'utilisateur est attendue (or).
  aFaire,

  /// Rien à faire pour l'instant : quelqu'un d'autre doit agir.
  attente,

  /// Étape franchie avec succès (vert).
  succes,

  /// Refus ou corrections demandées (rouge / orange).
  alerte,
}

/// Les quatre étapes du parcours d'un dossier, affichées en barre de
/// progression (la même pour tous les rôles).
const etapesParcours = <String>[
  // Formulée comme une étape à franchir (et non « Rapport déposé ») : tant
  // qu'aucun rapport n'est déposé, le libellé ne doit pas laisser croire
  // que c'est déjà fait.
  'Dépôt du rapport',
  'Avis de l encadreur',
  'Autorisation',
  'Prêt',
];

/// Situation d'un dossier pour un rôle donné.
class SituationDossier {
  /// Crée une situation.
  const SituationDossier({
    required this.etape,
    required this.titre,
    required this.explication,
    this.actions = const [],
    this.aTraiter = false,
    required this.humeur,
  });

  /// Étape atteinte dans [etapesParcours] (0 à 3), ou -1 si le dossier est
  /// refusé. 3 signifie que tout le parcours est terminé.
  final int etape;

  /// Phrase courte, en gros caractères (ex. « Votre avis est attendu »).
  final String titre;

  /// Une phrase qui dit ce qui se passe ou ce qu'il faut faire.
  final String explication;

  /// Actions à afficher en gros boutons ; la première est la plus
  /// importante. Vide quand l'utilisateur n'a rien à faire.
  final List<ActionDossier> actions;

  /// Vrai si une action de CET utilisateur est attendue (le dossier
  /// apparaît alors dans « À traiter » et compte sur l'accueil).
  final bool aTraiter;

  /// Couleur de la situation.
  final HumeurDossier humeur;
}

/// Numéro de la dernière version déposée, ou `null` sans dépôt.
int? numeroDerniereVersion(Map<String, dynamic> dossier) {
  final version = dossier['derniere_version'];
  if (version is! Map) return null;
  return int.tryParse(version['version_number']?.toString() ?? '');
}

/// Nombre de versions déposées (0 si l'information manque).
int nombreVersions(Map<String, dynamic> dossier) {
  final nombre = int.tryParse(dossier['nombre_versions']?.toString() ?? '');
  if (nombre != null) return nombre;
  return numeroDerniereVersion(dossier) == null ? 0 : 1;
}

/// Commentaire du dernier avis s'il demande des corrections, sinon `null`.
String? commentaireCorrections(Map<String, dynamic> dossier) {
  final avis = dossier['dernier_avis'];
  if (avis is! Map || avis['decision']?.toString() != 'defavorable') {
    return null;
  }
  final texte = (avis['comments'] ?? '').toString().trim();
  return texte.isEmpty ? null : texte;
}

/// Motif du refus si le dossier est refusé, sinon `null`.
String? motifRefus(Map<String, dynamic> dossier) {
  if (dossier['status']?.toString() != 'rejete') return null;
  final etape = dossier['derniere_etape'];
  if (etape is! Map) return null;
  final motif = (etape['motif'] ?? '').toString().trim();
  return motif.isEmpty ? null : motif;
}

/// Vrai si le dernier avis porte sur la DERNIÈRE version (aucune version
/// corrigée n'a encore été déposée depuis la demande de corrections).
bool _avisSurDerniereVersion(Map<String, dynamic> dossier) {
  final avis = dossier['dernier_avis'];
  if (avis is! Map) return false;
  return int.tryParse(avis['version_number']?.toString() ?? '') ==
      numeroDerniereVersion(dossier);
}

/// Étape de la barre de progression correspondant au statut.
int _etapeDuStatut(String statut) => switch (statut) {
  'soumis' => 1,
  'valide' => 2,
  'recevable' => 3,
  'rejete' => -1,
  _ => 0, // brouillon, a_corriger
};

/// Calcule la situation du [dossier] pour un utilisateur de rôle [role]
/// (`student`, `supervisor`, `admin`, `responsible`, `jury`).
SituationDossier situationDossier(String? role, Map<String, dynamic> dossier) {
  final statut = dossier['status']?.toString() ?? '';
  final etape = _etapeDuStatut(statut);
  final version = numeroDerniereVersion(dossier);
  final libelleVersion = version == null ? 'le rapport' : 'la version $version';
  final motif = motifRefus(dossier);

  // Situation commune à tous les rôles ; seul le personnel peut rouvrir.
  final personnel = role == 'admin' || role == 'responsible';
  final refus = SituationDossier(
    etape: -1,
    titre: 'Dossier refusé',
    explication: motif == null ? 'Le motif figure dans l’historique.' : 'Motif : $motif',
    actions: personnel ? const [ActionDossier.rouvrir] : const [],
    humeur: HumeurDossier.alerte,
  );
  if (statut == 'rejete') return refus;

  switch (role) {
    case 'student':
      return _situationEtudiant(statut, etape, dossier, version);
    case 'supervisor':
      return switch (statut) {
        'soumis' => SituationDossier(
          etape: etape,
          titre: 'Votre avis est attendu',
          explication:
              'Lisez $libelleVersion du rapport, puis acceptez-la ou '
              'demandez des corrections.',
          actions: const [ActionDossier.accepter, ActionDossier.demanderCorrections],
          aTraiter: true,
          humeur: HumeurDossier.aFaire,
        ),
        'a_corriger' => SituationDossier(
          etape: etape,
          titre: 'Corrections demandées',
          explication: 'L’étudiant prépare une version corrigée.',
          humeur: HumeurDossier.attente,
        ),
        'valide' => SituationDossier(
          etape: etape,
          titre: 'Vous avez accepté le rapport',
          explication: 'Le responsable des stages doit autoriser la soutenance.',
          humeur: HumeurDossier.succes,
        ),
        'recevable' => _pret(etape, 'Le dossier peut être planifié.'),
        _ => SituationDossier(
          etape: etape,
          titre: 'Rapport pas encore envoyé',
          explication: 'L’étudiant n’a pas encore envoyé son rapport.',
          humeur: HumeurDossier.attente,
        ),
      };
    case 'admin' || 'responsible':
      return switch (statut) {
        'valide' => SituationDossier(
          etape: etape,
          titre: 'Soutenance à autoriser',
          explication:
              'L’encadreur a accepté $libelleVersion. Autorisez la '
              'soutenance ou refusez le dossier.',
          actions: const [ActionDossier.autoriser, ActionDossier.refuser],
          aTraiter: true,
          humeur: HumeurDossier.aFaire,
        ),
        'soumis' => SituationDossier(
          etape: etape,
          titre: 'En attente de l’encadreur',
          explication: 'L’encadreur doit donner son avis sur $libelleVersion.',
          humeur: HumeurDossier.attente,
        ),
        'a_corriger' => SituationDossier(
          etape: etape,
          titre: 'Corrections demandées',
          explication: 'L’étudiant doit déposer une version corrigée.',
          humeur: HumeurDossier.attente,
        ),
        'recevable' => _pret(etape, 'Le dossier peut être planifié.'),
        _ => SituationDossier(
          etape: etape,
          titre: 'Rapport pas encore envoyé',
          explication: 'L’étudiant n’a pas encore envoyé son rapport.',
          humeur: HumeurDossier.attente,
        ),
      };
    case 'jury':
      // Le jury lit le rapport AVANT la soutenance pour préparer ses
      // questions : il n'a aucune décision à prendre sur le dossier.
      return version == null
          ? SituationDossier(
              etape: etape,
              titre: 'Rapport pas encore disponible',
              explication: 'L’étudiant n’a pas encore déposé son rapport.',
              humeur: HumeurDossier.attente,
            )
          : SituationDossier(
              etape: etape,
              titre: 'Rapport à lire',
              explication:
                  'Lisez $libelleVersion avant la soutenance et préparez '
                  'vos questions.',
              humeur: HumeurDossier.aFaire,
            );
    default:
      // Rôle inconnu : consultation seule.
      return statut == 'recevable'
          ? _pret(etape, 'Le dossier peut être planifié.')
          : SituationDossier(
              etape: etape,
              titre: 'Dossier en cours',
              explication: 'Le dossier suit son parcours de validation.',
              humeur: HumeurDossier.attente,
            );
  }
}

/// Situation « prêt pour la soutenance », commune à tous les rôles.
SituationDossier _pret(int etape, String explication) => SituationDossier(
  etape: etape,
  titre: 'Prêt pour la soutenance',
  explication: explication,
  humeur: HumeurDossier.succes,
);

/// Situation vue par l'étudiant propriétaire du dossier.
SituationDossier _situationEtudiant(
  String statut,
  int etape,
  Map<String, dynamic> dossier,
  int? version,
) {
  switch (statut) {
    case 'brouillon':
      if (version == null) {
        return SituationDossier(
          etape: etape,
          titre: 'Ajoutez votre rapport',
          explication:
              'Touchez « Ajouter mon rapport » et choisissez votre fichier PDF '
              '(10 Mo maximum). Vous pourrez l’envoyer à votre encadreur '
              'dans la foulée.',
          actions: const [ActionDossier.deposer],
          aTraiter: true,
          humeur: HumeurDossier.aFaire,
        );
      }
      return SituationDossier(
        etape: etape,
        titre: 'Envoyez votre rapport',
        explication:
            'La version $version est ajoutée mais pas encore envoyée : '
            'envoyez-la à votre encadreur pour qu’il donne son avis.',
        actions: const [ActionDossier.envoyer, ActionDossier.deposer],
        aTraiter: true,
        humeur: HumeurDossier.aFaire,
      );
    case 'a_corriger':
      // Tant qu'aucune version corrigée n'est déposée, seul le dépôt a un
      // sens ; ensuite, il faut l'envoyer.
      if (version == null || _avisSurDerniereVersion(dossier)) {
        return SituationDossier(
          etape: etape,
          titre: 'Corrections demandées',
          explication:
              'Votre encadreur demande des modifications. Corrigez votre '
              'rapport, puis ajoutez la version corrigée : vous pourrez la '
              'lui renvoyer aussitôt.',
          actions: const [ActionDossier.deposer],
          aTraiter: true,
          humeur: HumeurDossier.alerte,
        );
      }
      return SituationDossier(
        etape: etape,
        titre: 'Renvoyez la version corrigée',
        explication:
            'La version $version est ajoutée mais pas encore renvoyée : '
            'renvoyez-la à votre encadreur.',
        actions: const [ActionDossier.envoyer, ActionDossier.deposer],
        aTraiter: true,
        humeur: HumeurDossier.aFaire,
      );
    case 'soumis':
      return SituationDossier(
        etape: etape,
        titre: 'Rapport envoyé',
        explication:
            'Rien à faire pour l’instant : votre encadreur lit votre rapport. '
            'Sa réponse s’affichera ici. Vous pouvez encore ajouter une '
            'nouvelle version si besoin.',
        humeur: HumeurDossier.attente,
      );
    case 'valide':
      return SituationDossier(
        etape: etape,
        titre: 'Rapport accepté',
        explication: 'Le responsable des stages doit encore autoriser votre soutenance.',
        humeur: HumeurDossier.succes,
      );
    case 'recevable':
      return _pret(etape, 'Votre soutenance peut être planifiée. Sa date apparaîtra sur votre accueil.');
    default:
      return SituationDossier(
        etape: etape,
        titre: 'Dossier en cours',
        explication: 'Votre dossier suit son parcours de validation.',
        humeur: HumeurDossier.attente,
      );
  }
}
