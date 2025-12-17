import 'package:flutter/material.dart';

class StudyPlanFullScreenPage extends StatelessWidget {
  final String planText;
  const StudyPlanFullScreenPage({super.key, required this.planText});

  List<_DayPlan> _parseDays(String raw) {
    final lines = raw.split(RegExp(r'\n+'));
    final List<_DayPlan> days = [];
    _DayPlan? current;
    final dayHeader = RegExp(r'^(Day\s*\d+|Day\s*\d+:)', caseSensitive: false);
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (dayHeader.hasMatch(trimmed)) {
        if (current != null) days.add(current);
        final title = trimmed.replaceAll(':', '');
        current = _DayPlan(title, []);
      } else {
        current ??= _DayPlan('Day 1', []);
        current.tasks.add(trimmed);
      }
    }
    if (current != null) days.add(current);
    return days.isEmpty
        ? [
            _DayPlan('Study Plan', [raw.trim()]),
          ]
        : days;
  }

  @override
  Widget build(BuildContext context) {
    final dayPlans = _parseDays(planText);
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme ? const Color(0xFF121212) : Colors.white;
    final appBarColor = isDarkTheme ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.grey.shade100;
    final secondaryTextColor = isDarkTheme ? Colors.white70 : Colors.black54;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Study Plan',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: dayPlans.length,
        itemBuilder: (context, index) {
          final dp = dayPlans[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.purple.withOpacity(0.35)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dp.title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...dp.tasks.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              t,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayPlan {
  final String title;
  final List<String> tasks;
  _DayPlan(this.title, this.tasks);
}
