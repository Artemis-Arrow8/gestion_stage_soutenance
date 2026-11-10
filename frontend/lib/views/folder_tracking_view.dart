import 'package:flutter/material.dart';

import '../models/folder_tracking_model.dart';
import '../widgets/tracking_stepper.dart';

class FolderTrackingView extends StatelessWidget {
  final FolderTrackingModel folder;

  const FolderTrackingView({
    super.key,
    required this.folder,
  });

  int _getStep(String status) {
    switch (status.toLowerCase()) {
      case 'valide':
      case 'validé':
      case 'approved':
        return 3;
      case 'verification':
      case 'vérification':
        return 2;
      case 'documents_deposes':
        return 1;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de mon dossier')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: ListTile(
                title: Text(
                  folder.studentName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Année universitaire : ${folder.academicYear}'),
                trailing: Text('${folder.progress}%'),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'Progression du dossier',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            LinearProgressIndicator(
              value: (folder.progress.clamp(0, 100)) / 100,
              minHeight: 9,
            ),
            const SizedBox(height: 25),
            const Text(
              'Étapes de traitement',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            TrackingStepper(currentStep: _getStep(folder.status)),
          ],
        ),
      ),
    );
  }
}