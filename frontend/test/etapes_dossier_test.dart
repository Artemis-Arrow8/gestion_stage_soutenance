/// Tests de « Que dois-je faire maintenant ? » (core/utils/etapes_dossier.dart).
///
/// Chaque test vérifie qu'un rôle donné, face à un dossier dans un état
/// donné, voit EXACTEMENT les boutons qui ont un sens : ni plus (il
/// tâtonnerait), ni moins (il serait bloqué).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/core/utils/etapes_dossier.dart';

/// Dossier fictif au [statut] donné, avec sa dernière version et son
/// dernier avis éventuels (même forme que la réponse de l'API).
Map<String, dynamic> dossier(
  String statut, {
  int? version,
  Map<String, dynamic>? avis,
  String? motif,
  String? evenement,
}) => {
  'id': 5,
  'status': statut,
  'student_name': 'Awa Traoré',
  'nombre_versions': version ?? 0,
  'derniere_version': version == null
      ? null
      : {'id': 70 + version, 'version_number': version, 'uploaded_at': '2026-11-12T10:00:00Z'},
  'dernier_avis': avis,
  'derniere_etape': motif == null
      ? null
      : {'evenement': evenement, 'statut_apres': statut, 'motif': motif},
};

void main() {
  group('étudiant', () {
    test('sans rapport : un seul bouton, « déposer »', () {
      final s = situationDossier('student', dossier('brouillon'));
      expect(s.titre, 'Ajoutez votre rapport');
      expect(s.actions, [ActionDossier.deposer]);
      expect(s.aTraiter, isTrue);
      expect(s.etape, 0);
    });

    test('rapport déposé : « envoyer » passe en premier', () {
      final s = situationDossier('student', dossier('brouillon', version: 1));
      expect(s.actions, [ActionDossier.envoyer, ActionDossier.deposer]);
      expect(s.explication, contains('version 1'));
    });

    test('corrections demandées : déposer d’abord, envoyer ensuite', () {
      final avis = {'decision': 'defavorable', 'comments': 'Revoir le plan.', 'version_number': 1};
      final avant = situationDossier('student', dossier('a_corriger', version: 1, avis: avis));
      expect(avant.actions, [ActionDossier.deposer]);
      expect(avant.humeur, HumeurDossier.alerte);

      // Version 2 déposée après l'avis sur la version 1 : il reste à l'envoyer.
      final apres = situationDossier('student', dossier('a_corriger', version: 2, avis: avis));
      expect(apres.actions, [ActionDossier.envoyer, ActionDossier.deposer]);
    });

    test('rapport envoyé : rien à faire, on attend', () {
      final s = situationDossier('student', dossier('soumis', version: 1));
      expect(s.actions, isEmpty);
      expect(s.aTraiter, isFalse);
      expect(s.etape, 1);
    });

    test('dossier prêt : parcours terminé', () {
      final s = situationDossier('student', dossier('recevable', version: 1));
      expect(s.titre, 'Prêt pour la soutenance');
      expect(s.etape, 3);
      expect(s.actions, isEmpty);
    });
  });

  group('encadreur', () {
    test('rapport envoyé : accepter ou demander des corrections', () {
      final s = situationDossier('supervisor', dossier('soumis', version: 2));
      expect(s.titre, 'Votre avis est attendu');
      expect(s.actions, [ActionDossier.accepter, ActionDossier.demanderCorrections]);
      expect(s.aTraiter, isTrue);
      expect(s.explication, contains('version 2'));
    });

    test('après son avis : plus aucun bouton de décision', () {
      for (final statut in ['valide', 'a_corriger', 'recevable', 'brouillon']) {
        final s = situationDossier('supervisor', dossier(statut, version: 1));
        expect(s.actions, isEmpty, reason: statut);
        expect(s.aTraiter, isFalse, reason: statut);
      }
    });
  });

  group('personnel', () {
    test('rapport accepté : autoriser ou refuser', () {
      for (final role in ['responsible', 'admin']) {
        final s = situationDossier(role, dossier('valide', version: 1));
        expect(s.titre, 'Soutenance à autoriser');
        expect(s.actions, [ActionDossier.autoriser, ActionDossier.refuser]);
        expect(s.aTraiter, isTrue);
        expect(s.etape, 2);
      }
    });

    test('en attente de l’encadreur : pas de décision à prendre', () {
      final s = situationDossier('responsible', dossier('soumis', version: 1));
      expect(s.actions, isEmpty);
      expect(s.aTraiter, isFalse);
    });
  });

  test('un refus montre son motif à tous ; seul le personnel peut rouvrir', () {
    for (final role in ['student', 'supervisor', 'responsible']) {
      final s = situationDossier(role, dossier('rejete', motif: 'Stage hors période.'));
      expect(s.titre, 'Dossier refusé');
      expect(s.explication, 'Motif : Stage hors période.');
      expect(s.etape, -1);
      expect(s.aTraiter, isFalse);
      expect(
        s.actions,
        role == 'responsible' ? [ActionDossier.rouvrir] : isEmpty,
        reason: role,
      );
    }
  });

  test('les filtres classent chaque dossier dans une seule catégorie', () {
    expect(categorieDossier('supervisor', dossier('soumis', version: 1)), CategorieDossier.aTraiter);
    expect(categorieDossier('responsible', dossier('soumis', version: 1)), CategorieDossier.enCours);
    expect(categorieDossier('responsible', dossier('recevable', version: 1)), CategorieDossier.prets);
    expect(categorieDossier('responsible', dossier('rejete')), CategorieDossier.refuses);
  });

  test('le jury ne voit jamais de bouton de décision', () {
    for (final statut in ['brouillon', 'soumis', 'valide', 'recevable']) {
      expect(situationDossier('jury', dossier(statut, version: 1)).actions, isEmpty);
    }
  });

  group('bouton « Ajouter » de l’étudiant', () {
    final avis = {'decision': 'defavorable', 'comments': 'Revoir le plan.', 'version_number': 1};

    test('le libellé dit exactement ce que l’on ajoute', () {
      expect(libelleAjout(dossier('brouillon')), 'Ajouter mon rapport');
      expect(libelleAjout(dossier('a_corriger', version: 1, avis: avis)), 'Ajouter la version corrigée');
      // Fichier ajouté mais pas encore envoyé : on le remplace.
      expect(libelleAjout(dossier('brouillon', version: 1)), 'Remplacer par un autre fichier');
      expect(libelleAjout(dossier('a_corriger', version: 2, avis: avis)), 'Remplacer par un autre fichier');
      for (final statut in ['soumis', 'valide', 'recevable']) {
        expect(libelleAjout(dossier(statut, version: 1)), 'Ajouter une nouvelle version', reason: statut);
      }
    });

    test('l’envoi dans la foulée n’est proposé qu’en brouillon ou à corriger', () {
      expect(envoiPossible(dossier('brouillon')), isTrue);
      expect(envoiPossible(dossier('a_corriger', version: 1)), isTrue);
      for (final statut in ['soumis', 'valide', 'recevable', 'rejete']) {
        expect(envoiPossible(dossier(statut, version: 1)), isFalse, reason: statut);
      }
    });

    test('le dépôt reste possible partout, sauf dossier refusé', () {
      for (final statut in ['brouillon', 'a_corriger', 'soumis', 'valide', 'recevable']) {
        expect(peutDeposer('student', dossier(statut, version: 1)), isTrue, reason: statut);
      }
      expect(peutDeposer('student', dossier('rejete')), isFalse);
      expect(peutDeposer('supervisor', dossier('brouillon')), isFalse);
    });

    test('l’accueil donne la prochaine étape en mots d’action', () {
      expect(boutonAccueilEtudiant(dossier('brouillon')), 'Ajouter mon rapport');
      expect(boutonAccueilEtudiant(dossier('brouillon', version: 1)), 'Envoyer mon rapport');
      expect(boutonAccueilEtudiant(dossier('a_corriger', version: 1, avis: avis)), 'Corriger mon rapport');
      expect(boutonAccueilEtudiant(dossier('a_corriger', version: 2, avis: avis)), 'Renvoyer ma version corrigée');
      expect(boutonAccueilEtudiant(dossier('soumis', version: 1)), isNull);
    });
  });

  test('le mot de l’étudiant n’est montré que tant que le rapport attend l’avis', () {
    final envoye = dossier('soumis', version: 2, motif: ' J’ai repris le chapitre 2. ', evenement: 'soumettre');
    expect(messageEtudiant(envoye), 'J’ai repris le chapitre 2.');
    // Une autre étape (réouverture, nouvelle version…) n'est pas un message.
    expect(messageEtudiant(dossier('soumis', version: 2, motif: 'Erreur', evenement: 'rouvrir')), isNull);
    expect(messageEtudiant(dossier('valide', version: 2, motif: 'Bien', evenement: 'soumettre')), isNull);
    expect(messageEtudiant(dossier('soumis', version: 2, motif: '  ', evenement: 'soumettre')), isNull);
  });

  test('seul un avis défavorable commenté est cité', () {
    expect(
      commentaireCorrections(dossier('a_corriger', avis: {'decision': 'defavorable', 'comments': ' Revoir. '})),
      'Revoir.',
    );
    expect(commentaireCorrections(dossier('valide', avis: {'decision': 'favorable', 'comments': 'Bien.'})), isNull);
    expect(commentaireCorrections(dossier('a_corriger')), isNull);
  });
}
