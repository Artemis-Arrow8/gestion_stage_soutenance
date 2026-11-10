import 'package:flutter/material.dart';

class TrackingStepper extends StatelessWidget {
  final int currentStep;

  const TrackingStepper({
    super.key,
    required this.currentStep,
  });

  static const List<String> steps = [
    'Dossier créé',
    'Documents déposés',
    'Vérification',
    'Dossier validé',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length, (index) {
        final completed = index <= currentStep;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: completed ? Colors.green : Colors.grey.shade300,
            child: Icon(
              completed ? Icons.check : Icons.circle_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          title: Text(
            steps[index],
            style: TextStyle(
              fontWeight: completed ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          trailing: index == currentStep
              ? const Text(
                  'En cours',
                  style: TextStyle(color: Colors.blue),
                )
              : null,
        );
      }),
    );
  }
}