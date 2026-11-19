/// Visionneuse PDF hors navigateur (Android, version PC, tests) : le
/// fichier est proposé à l'enregistrement, puis ouvert par l'utilisateur
/// avec sa visionneuse habituelle.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Affiche (ici : enregistre) un PDF reçu du serveur.
class VisionneusePdf {
  /// Rien à préparer hors navigateur.
  void preparer() {}

  /// Propose d'enregistrer [octets] sous le nom [nom].
  ///
  /// Retourne `true` si l'utilisateur a choisi un emplacement.
  Future<bool> afficher(Uint8List octets, String nom) async {
    final chemin = await FilePicker.saveFile(
      dialogTitle: 'Enregistrer le rapport',
      fileName: nom,
      mimeType: 'application/pdf',
      bytes: octets,
    );
    return chemin != null;
  }

  /// Rien à fermer hors navigateur.
  void annuler() {}
}
