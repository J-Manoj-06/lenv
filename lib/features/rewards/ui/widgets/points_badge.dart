import 'package:flutter/material.dart';
import '../../utils/points_calculator.dart';

/// Badge widget to display points
class PointsBadge extends StatelessWidget {
  final int points;
  final int? required;
  final String label;
  final bool highlighted;

  const PointsBadge({
    super.key,
    required this.points,
    this.required,
    this.label = 'Points',
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSufficient = required == null || points >= required!;
    final color = isSufficient ? const Color(0xFFF97316) : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stars_rounded, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            required != null
                ? '${PointsCalculator.formatPoints(points)} / ${PointsCalculator.formatPoints(required!)}'
                : PointsCalculator.formatPoints(points),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
