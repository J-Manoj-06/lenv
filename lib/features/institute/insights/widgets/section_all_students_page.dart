import 'package:flutter/material.dart';
import '../../../../models/student_model.dart';

class SectionAllStudentsPage extends StatelessWidget {
  const SectionAllStudentsPage({
    super.key,
    required this.className,
    required this.section,
    required this.students,
    required this.schoolCode,
  });

  final String className;
  final String section;
  final List<StudentModel> students;
  final String schoolCode;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Class $className - Section $section'),
        backgroundColor: cardColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: students.length,
        itemBuilder: (context, index) {
          final student = students[index];
          return Card(
            color: cardColor,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF146D7A).withOpacity(0.1),
                    backgroundImage:
                        student.photoUrl != null && student.photoUrl!.isNotEmpty
                        ? NetworkImage(student.photoUrl!)
                        : null,
                    child: student.photoUrl == null || student.photoUrl!.isEmpty
                        ? Text(
                            student.name.isNotEmpty
                                ? student.name[0].toUpperCase()
                                : 'S',
                            style: const TextStyle(
                              color: Color(0xFF146D7A),
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),

                  // Student info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name.isNotEmpty ? student.name : 'Student',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stats
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF146D7A).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.assignment_turned_in,
                              color: Color(0xFF146D7A),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${student.completedTests}',
                              style: const TextStyle(
                                color: Color(0xFF146D7A),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: Color(0xFFFFD700),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${student.rewardPoints} pts',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
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
