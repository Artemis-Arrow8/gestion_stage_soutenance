/// Carte résumant une soutenance dans une liste (tableau de bord, jurys…).
library;

import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/dates.dart';
import '../models/defense.dart';
import 'ui_kit.dart';

/// Ligne de soutenance : pavé date, étudiant, sujet, horaires, salle, jury
/// et statut.
class DefenseTile extends StatelessWidget {
  /// Crée la carte de [defense] ; [onTap] ouvre généralement sa fiche.
  ///
  /// [trailing] remplace le badge de statut affiché à droite.
  const DefenseTile({
    super.key,
    required this.defense,
    this.onTap,
    this.trailing,
  });

  /// Soutenance affichée.
  final Defense defense;

  /// Action au clic.
  final VoidCallback? onTap;

  /// Widget de fin de ligne personnalisé.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = parseDefenseDate(defense.date);
    return SgCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Pavé calendrier : jour du mois et jour de la semaine.
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: AppTheme.inkGradient,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              children: [
                Text(
                  d == null ? '--' : d.day.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d == null ? '' : joursCourts[d.weekday - 1].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 9,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  defense.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  defense.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
                ),
                const SizedBox(height: 8),
                // Métadonnées qui passent à la ligne sur petit écran.
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _meta(
                      Icons.schedule_rounded,
                      '${defense.startTime} – ${defense.endTime}',
                    ),
                    _meta(Icons.meeting_room_outlined, defense.roomName),
                    _meta(Icons.groups_2_outlined, defense.juryName),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing ??
              SgStatusBadge(defense.status),
        ],
      ),
    );
  }

  /// Petite métadonnée « icône + texte ».
  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppColors.greyLight),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.grey)),
    ],
  );
}
