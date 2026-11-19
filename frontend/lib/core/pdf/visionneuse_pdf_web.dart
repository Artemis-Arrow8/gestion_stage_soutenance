/// Visionneuse PDF du navigateur : le rapport s'affiche dans un nouvel
/// onglet (le navigateur intègre une visionneuse PDF).
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Affiche un PDF reçu du serveur dans un nouvel onglet.
class VisionneusePdf {
  /// Onglet ouvert par [preparer], ou `null` si le navigateur l'a bloqué.
  web.Window? _onglet;

  /// Ouvre tout de suite un onglet vide (pendant le geste de l'utilisateur,
  /// sinon le navigateur le bloquerait) avec un message d'attente.
  void preparer() {
    _onglet = web.window.open('', '_blank');
    _onglet?.document.title = 'Ouverture du rapport…';
    _onglet?.document.body?.textContent = 'Ouverture du rapport en cours…';
  }

  /// Affiche [octets] dans l'onglet préparé ; si aucun onglet n'a pu être
  /// ouvert, le fichier est téléchargé sous le nom [nom].
  Future<bool> afficher(Uint8List octets, String nom) async {
    final blob = web.Blob(
      [octets.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final adresse = web.URL.createObjectURL(blob);
    final onglet = _onglet;
    if (onglet != null) {
      onglet.location.href = adresse;
    } else {
      // Onglet bloqué : téléchargement classique, toujours possible.
      (web.HTMLAnchorElement()
            ..href = adresse
            ..download = nom)
          .click();
    }
    // L'adresse temporaire est libérée une fois le document chargé.
    Future<void>.delayed(const Duration(minutes: 1), () {
      web.URL.revokeObjectURL(adresse);
    });
    return true;
  }

  /// Ferme l'onglet préparé (échec du téléchargement).
  void annuler() {
    _onglet?.close();
    _onglet = null;
  }
}
