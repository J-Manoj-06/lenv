import 'package:flutter/material.dart';
import '../models/attendance_summary_model.dart';

class AttendanceSummaryCard extends StatelessWidget {
  final AttendanceSummaryModel summary;
  final Color cardColor;
  final Color textColor;
  final Color subtitleColor;

  const AttendanceSummaryCard({
    super.key,
    required this.summary,
    required this.cardColor,
    required this.textColor,
    required this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat(
                'Total',
                summary.totalStudents.toString(),
                Icons.people,
                textColor,
                subtitleColor,
              ),
              _buildStat(
                'Present',
                summary.totalPresent.toString(),
                Icons.check_circle,
                const Color(0xFF34D399),
                subtitleColor,
              ),
              _buildStat(
                'Absent',
                summary.totalAbsent.toString(),
                Icons.cancel,
                const Color(0xFFFB7185),
                subtitleColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '${summary.percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: summary.statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      summary.attendanceStatus,
                      style: TextStyle(
                        color: summary.statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(
    String label,
    String value,
    IconData icon,
    Color valueColor,
    Color labelColor,
  ) {
    return Column(
      children: [
        Icon(icon, color: valueColor, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
      ],
    );
  }
}
