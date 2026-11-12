import 'package:flutter/material.dart';
import '../models/defense.dart';
import '../theme/app_theme.dart';
import '../utils/dates.dart';
import 'ui_kit.dart';

class DefenseTile extends StatelessWidget {
  const DefenseTile({super.key, required this.defense, this.onTap, this.trailing});

  final Defense defense;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = parseDefenseDate(defense.date);
    return SgCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
                color: AppColors.ink, borderRadius: BorderRadius.circular(9)),
            child: Column(
              children: [
                Text(
                  d == null ? '--' : d.day.toString().padLeft(2, '0'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.1),
                ),
                Text(
                  d == null ? '' : joursCourts[d.weekday - 1].toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 8.5,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(defense.studentName,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(defense.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _meta(Icons.schedule_rounded,
                        '${defense.startTime} – ${defense.endTime}'),
                    _meta(Icons.meeting_room_outlined, defense.roomName),
                    _meta(Icons.groups_2_outlined, defense.juryName),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing ??
              SgBadge(defense.status, tone: sgToneForStatus(defense.status)),
        ],
      ),
    );
  }

  Widget _meta(IconData i, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 13, color: AppColors.greyLight),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 11.5, color: AppColors.grey)),
        ],
      );
}