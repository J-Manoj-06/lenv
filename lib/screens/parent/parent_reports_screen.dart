import 'package:flutter/material.dart';
import '../../widgets/student_selection/student_avatar_row.dart';

class ParentReportsScreen extends StatelessWidget {
  const ParentReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF151022)
          : const Color(0xFFF6F6F8),
      appBar: AppBar(
        title: const Text('Reports'),
        backgroundColor: isDark ? const Color(0xFF151022) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF110D1B),
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // Student Selection Row
          const StudentAvatarRow(),

          // Content
          Expanded(
            child: Center(
              child: Text(
                'Academic reports will appear here',
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
