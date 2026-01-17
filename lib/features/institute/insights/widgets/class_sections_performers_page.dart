import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/student_model.dart';
import './section_all_students_page.dart';

class ClassSectionsPerformersPage extends StatefulWidget {
  const ClassSectionsPerformersPage({
    super.key,
    required this.className,
    required this.schoolCode,
    required this.range,
  });

  final String className;
  final String schoolCode;
  final String range;

  @override
  State<ClassSectionsPerformersPage> createState() =>
      _ClassSectionsPerformersPageState();
}

class _ClassSectionsPerformersPageState
    extends State<ClassSectionsPerformersPage> {
  bool _isLoading = true;
  Map<String, List<StudentModel>> _sectionStudents = {};

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    try {
      // Extract just the number from className (e.g., "Grade 10" -> "10")
      final classNumber = widget.className.replaceAll(RegExp(r'[^0-9]'), '');

      print('DEBUG: Looking for class number: $classNumber');
      print('DEBUG: School code: ${widget.schoolCode}');

      // Fetch all students in this school first
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .get();

      print('DEBUG: Total students in school: ${snapshot.docs.length}');

      // First pass: Filter students by class and collect UIDs
      final List<StudentModel> matchingStudents = [];
      final Set<String> seenUids = {};
      final List<String> uidsToFetch = [];

      for (var doc in snapshot.docs) {
        final student = StudentModel.fromFirestore(doc);

        // Skip duplicates
        if (seenUids.contains(student.uid)) continue;

        final studentClassNumber = (student.className ?? '').replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );

        // Match if the class numbers are the same
        if (studentClassNumber == classNumber) {
          seenUids.add(student.uid);
          matchingStudents.add(student);
          uidsToFetch.add(student.uid);
        }
      }

      print('DEBUG: Found ${matchingStudents.length} matching students');

      // Batch fetch user data (Firestore supports up to 10 items in whereIn)
      final Map<String, Map<String, dynamic>> userDataMap = {};

      for (int i = 0; i < uidsToFetch.length; i += 10) {
        final batch = uidsToFetch.skip(i).take(10).toList();
        try {
          final userDocs = await FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: batch)
              .get();

          for (var doc in userDocs.docs) {
            if (doc.exists) {
              userDataMap[doc.id] = doc.data();
            }
          }
        } catch (e) {
          print('DEBUG: Error fetching user batch: $e');
        }
      }

      // Enrich students with user data and group by section
      final Map<String, List<StudentModel>> grouped = {};

      for (var student in matchingStudents) {
        final userData = userDataMap[student.uid];

        if (userData != null) {
          final rewardPoints =
              (userData['rewardPoints'] ?? userData['totalPoints'] ?? 0) as int;
          final completedTests = (userData['completedTests'] ?? 0) as int;
          final studentId = userData['studentId'] as String?;
          final userName = userData['name'] as String?;

          student = student.copyWith(
            name: (userName != null && userName.isNotEmpty)
                ? userName
                : student.name,
            rewardPoints: rewardPoints,
            completedTests: completedTests,
            studentId: studentId ?? student.studentId,
          );
        }

        final section = student.section ?? 'Unknown';
        if (!grouped.containsKey(section)) {
          grouped[section] = [];
        }
        grouped[section]!.add(student);
      }

      // Sort students by reward points (descending - highest first) within each section
      for (var section in grouped.keys) {
        grouped[section]!.sort(
          (a, b) => b.rewardPoints.compareTo(a.rewardPoints),
        );
      }

      print('DEBUG: Grouped sections: ${grouped.keys.toList()}');

      // Sort sections alphabetically
      final sortedSections = Map.fromEntries(
        grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );

      if (mounted) {
        setState(() {
          _sectionStudents = sortedSections;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

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
        title: Text('Class ${widget.className} Sections'),
        backgroundColor: cardColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sectionStudents.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: subtitleColor),
                  const SizedBox(height: 16),
                  Text(
                    'No students found in Class ${widget.className}',
                    style: TextStyle(color: subtitleColor, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sectionStudents.length,
              itemBuilder: (context, index) {
                final section = _sectionStudents.keys.elementAt(index);
                final students = _sectionStudents[section]!;
                final top3 = students.take(3).toList();

                return Card(
                  color: cardColor,
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF146D7A).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.group,
                                color: Color(0xFF146D7A),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Section $section',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF146D7A).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${students.length} students',
                                style: const TextStyle(
                                  color: Color(0xFF146D7A),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Top 3 students
                        ...top3.asMap().entries.map((entry) {
                          final rank = entry.key + 1;
                          final student = entry.value;
                          final medalColors = [
                            const Color(0xFFFFD700), // Gold
                            const Color(0xFFC0C0C0), // Silver
                            const Color(0xFFCD7F32), // Bronze
                          ];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: rank == 1
                                  ? Border.all(
                                      color: medalColors[0].withOpacity(0.3),
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                // Rank badge
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: medalColors[rank - 1],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$rank',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Student info
                                Expanded(
                                  child: Text(
                                    student.name,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                                // Student stats
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF146D7A,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${student.completedTests} tests',
                                        style: const TextStyle(
                                          color: Color(0xFF146D7A),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${student.rewardPoints} pts',
                                      style: TextStyle(
                                        color: subtitleColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),

                        // View More button
                        if (students.length > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SectionAllStudentsPage(
                                            className: widget.className,
                                            section: section,
                                            students: students,
                                            schoolCode: widget.schoolCode,
                                          ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.expand_more, size: 20),
                                label: Text(
                                  'View All ${students.length} Students',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF146D7A),
                                  side: const BorderSide(
                                    color: Color(0xFF146D7A),
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
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
