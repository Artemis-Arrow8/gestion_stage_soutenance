/// Ouverture d'un rapport PDF pour le LIRE, en un seul geste.
///
/// * Sur le Web : le PDF s'ouvre dans un nouvel onglet du navigateur, qui
///   l'affiche directement (aucune boîte « Enregistrer sous… »).
/// * Sur Android et la version PC : le système propose d'enregistrer le
///   fichier, puis l'utilisateur l'ouvre avec sa visionneuse habituelle.
///
/// Le bon fichier est choisi à la compilation (import conditionnel) : les
/// tests, exécutés hors navigateur, utilisent la version « fichier ».
///
/// Utilisation (l'ordre compte sur le Web) :
/// ```dart
/// final visionneuse = VisionneusePdf();
/// visionneuse.preparer();               // AVANT tout `await` (voir ci-dessous)
/// final octets = await telecharger();
/// await visionneuse.afficher(octets, 'rapport.pdf');
/// ```
/// `preparer` ouvre l'onglet tout de suite, pendant le geste de
/// l'utilisateur : un onglet ouvert après une attente réseau serait bloqué
/// par le navigateur comme une fenêtre publicitaire.
library;

export 'visionneuse_pdf_fichier.dart'
    if (dart.library.js_interop) 'visionneuse_pdf_web.dart';
