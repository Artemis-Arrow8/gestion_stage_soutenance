import 'package:flutter/material.dart';

class DocumentStatusBadge extends StatelessWidget {
  final String status;

  const DocumentStatusBadge({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();

    Color color;
    String label;

    switch (normalized) {
      case 'valide':
      case 'validé':
      case 'approved':
        color = Colors.green;
        label = 'Validé';
        break;

      case 'rejete':
      case 'rejeté':
      case 'rejected':
        color = Colors.red;
        label = 'Rejeté';
        break;

      case 'en_cours':
      case 'processing':
        color = Colors.blue;
        label = 'En cours';
        break;

      default:
        color = Colors.orange;
        label = 'En attente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}