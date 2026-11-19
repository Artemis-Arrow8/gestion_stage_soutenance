/// Tests de l'usage à une main : geste « retour » et protection de la saisie.
///
/// Le geste « retour » du téléphone (glissement depuis le bord sur Samsung,
/// bouton retour du navigateur) est simulé par `handlePopRoute`, exactement
/// le message que le système envoie à l'application.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_stage_soutenance/widgets/ui_kit.dart';
import 'package:material_ui/material_ui.dart';

/// Clé du formulaire de l'écran de test.
final _cleFormulaire = GlobalKey<FormState>();

void main() {
  /// Ouvre l'écran « Saisie » (formulaire protégé) par-dessus l'accueil.
  Future<void> ouvrirSaisie(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Accueil()));
    await tester.tap(find.text('Ouvrir le formulaire'));
    await tester.pumpAndSettle();
    expect(find.text('Saisie'), findsOneWidget);
  }

  testWidgets('sans saisie, le geste « retour » ferme l’écran directement', (
    WidgetTester tester,
  ) async {
    await ouvrirSaisie(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Saisie'), findsNothing);
    expect(find.text('Quitter sans enregistrer ?'), findsNothing);
  });

  testWidgets('avec une saisie, le geste « retour » demande confirmation', (
    WidgetTester tester,
  ) async {
    await ouvrirSaisie(tester);
    await tester.enterText(find.byType(TextFormField), 'Texte important');
    await tester.pump();

    // Glissement accidentel : l'écran reste ouvert, une question s'affiche.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);

    // « Continuer la saisie » : rien n'est perdu.
    await tester.tap(find.text('Continuer la saisie'));
    await tester.pumpAndSettle();
    expect(find.text('Saisie'), findsOneWidget);
    expect(find.text('Texte important'), findsOneWidget);

    // Nouveau geste puis « Quitter » : retour à l'accueil.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitter'));
    await tester.pumpAndSettle();
    expect(find.text('Saisie'), findsNothing);
    expect(find.text('Ouvrir le formulaire'), findsOneWidget);
  });

  testWidgets(
    'après enregistrement, le geste « retour » ne demande plus rien',
    (WidgetTester tester) async {
      await ouvrirSaisie(tester);
      await tester.enterText(find.byType(TextFormField), 'Mot de passe');
      await tester.pump();

      // Enregistrement qui laisse l'écran ouvert (cas du mot de passe).
      await tester.tap(find.text('Enregistrer'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Quitter sans enregistrer ?'), findsNothing);
      expect(find.text('Saisie'), findsNothing);
    },
  );
}

/// Écran d'accueil de test : un bouton ouvre l'écran de saisie.
class _Accueil extends StatelessWidget {
  const _Accueil();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const _Saisie())),
          child: const Text('Ouvrir le formulaire'),
        ),
      ),
    );
  }
}

/// Écran de saisie de test, construit comme les vrais formulaires.
class _Saisie extends StatefulWidget {
  const _Saisie();

  @override
  State<_Saisie> createState() => _SaisieState();
}

/// État de l'écran de saisie : un champ et un bouton « Enregistrer ».
class _SaisieState extends State<_Saisie> {
  /// Champ unique du formulaire.
  final _champ = TextEditingController();

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SgFormulaire(
        formKey: _cleFormulaire,
        child: Column(
          children: [
            const Text('Saisie'),
            TextFormField(controller: _champ),
            TextButton(
              // Comme sur la page Profil : on vide puis on marque enregistré.
              onPressed: () {
                _champ.clear();
                SgFormulaire.marquerEnregistre(_cleFormulaire);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
