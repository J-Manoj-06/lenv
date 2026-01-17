import 'package:flutter/material.dart';
import './all_standards_performers_page.dart';

class InsightsTopPerformersCard extends StatelessWidget {
  const InsightsTopPerformersCard({
    super.key,
    required this.schoolCode,
    required this.range,
  });

  final String schoolCode;
  final String range;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AllStandardsPerformersPage(
              schoolCode: schoolCode,
              range: range,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF146D7A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.emoji_events, color: Color(0xFF146D7A), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Top Performers', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Tap to view insights', style: TextStyle(color: subtitleColor, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(child: Text('Data loads when tapped', style: TextStyle(color: subtitleColor, fontSize: 14))),
        ],
      ),
      )
    );
  }
}
