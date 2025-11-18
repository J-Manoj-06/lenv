import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get teacher details by email
  Future<Map<String, dynamic>?> getTeacherByEmail(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection('teachers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        data['id'] = querySnapshot.docs.first.id;
        return data;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Normalize sections input (supports string like "A, B" or list like ["A","B"]) to a String list
  List<String> _normalizeSections(dynamic sections) {
    if (sections == null) return <String>[];
    if (sections is List) {
      return sections
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (sections is String) {
      return sections
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  /// Get students by class sections that teacher handles
  /// classesHandled format: ["Grade 5"]
  /// sections format: "A, B, C" OR ["A","B"]
  Future<List<Map<String, dynamic>>> getStudentsByTeacher(
    String schoolId,
    List<dynamic>? classesHandled,
    dynamic sections, {
    List<dynamic>? classAssignments,
  }) async {
    try {
      final List<Map<String, dynamic>> allStudents = [];

      // First, try using classesHandled + sections if available
      if (classesHandled != null && classesHandled.isNotEmpty) {
        final sectionList = _normalizeSections(sections);
        if (sectionList.isEmpty) {
          return [];
        }

        for (final classItem in classesHandled) {
          final className = classItem.toString(); // e.g., "Grade 5"

          for (final section in sectionList) {
            if (section.isEmpty) continue;

            final querySnapshot = await _firestore
                .collection('students')
                .where('schoolCode', isEqualTo: schoolId)
                .where('className', isEqualTo: className)
                .where('section', isEqualTo: section)
                .get();

            for (var doc in querySnapshot.docs) {
              final studentData = doc.data();
              studentData['id'] = doc.id;

              // Fetch rewardPoints from users collection
              try {
                final studentEmail =
                    studentData['email'] as String? ??
                    studentData['studentEmail'] as String?;
                String? actualUid;
                int rewardPoints = 0;

                // Step 1: Find the user by email to get the real Auth UID
                if (studentEmail != null && studentEmail.isNotEmpty) {
                  final userQuery = await _firestore
                      .collection('users')
                      .where('email', isEqualTo: studentEmail)
                      .limit(1)
                      .get();

                  if (userQuery.docs.isNotEmpty) {
                    final userDoc = userQuery.docs.first;
                    final userData = userDoc.data();
                    actualUid = userData['uid'] as String? ?? userDoc.id;

                    final rpRaw = userData['rewardPoints'];
                    if (rpRaw is int) {
                      rewardPoints = rpRaw;
                    } else if (rpRaw is num) {
                      rewardPoints = rpRaw.toInt();
                    } else if (rpRaw is String) {
                      rewardPoints = int.tryParse(rpRaw) ?? 0;
                    }
                  }
                }

                // Step 2: If rewardPoints is 0 or user not found, aggregate from student_rewards
                if (rewardPoints == 0 && actualUid != null) {
                  final rewardsSnap = await _firestore
                      .collection('student_rewards')
                      .where('studentId', isEqualTo: actualUid)
                      .get();
                  int aggregated = 0;
                  for (final rd in rewardsSnap.docs) {
                    aggregated +=
                        (rd.data()['pointsEarned'] as num?)?.toInt() ?? 0;
                  }
                  if (aggregated > 0) {
                    studentData['aggregatedRewardPoints'] = aggregated;
                  }
                  rewardPoints = aggregated;
                }

                studentData['rewardPoints'] = rewardPoints;
              } catch (e) {
                studentData['rewardPoints'] = 0;
              }

              allStudents.add(studentData);
            }
          }
        }
        return allStudents;
      }

      // Fallback: Use classAssignments (e.g., "Grade 10: A, Science")
      final formatted = getTeacherClasses(
        null,
        null,
        classAssignments: classAssignments,
      );
      if (formatted.isEmpty) {
        return [];
      }

      for (final fc in formatted) {
        // fc like "10 - A" -> className="Grade 10", section="A"
        final parts = fc.split(' - ');
        if (parts.length != 2) continue;
        final className = 'Grade ${parts[0].trim()}';
        final section = parts[1].trim();

        final querySnapshot = await _firestore
            .collection('students')
            .where('schoolCode', isEqualTo: schoolId)
            .where('className', isEqualTo: className)
            .where('section', isEqualTo: section)
            .get();

        for (var doc in querySnapshot.docs) {
          final studentData = doc.data();
          studentData['id'] = doc.id;

          // Fetch rewardPoints from users collection
          try {
            final studentEmail =
                studentData['email'] as String? ??
                studentData['studentEmail'] as String?;
            String? actualUid;
            int rewardPoints = 0;

            // Step 1: Find the user by email to get the real Auth UID
            if (studentEmail != null && studentEmail.isNotEmpty) {
              final userQuery = await _firestore
                  .collection('users')
                  .where('email', isEqualTo: studentEmail)
                  .limit(1)
                  .get();

              if (userQuery.docs.isNotEmpty) {
                final userDoc = userQuery.docs.first;
                final userData = userDoc.data();
                actualUid = userData['uid'] as String? ?? userDoc.id;

                final rpRaw = userData['rewardPoints'];
                if (rpRaw is int) {
                  rewardPoints = rpRaw;
                } else if (rpRaw is num) {
                  rewardPoints = rpRaw.toInt();
                } else if (rpRaw is String) {
                  rewardPoints = int.tryParse(rpRaw) ?? 0;
                }
              }
            }

            // Step 2: If rewardPoints is 0 or user not found, aggregate from student_rewards
            if (rewardPoints == 0 && actualUid != null) {
              final rewardsSnap = await _firestore
                  .collection('student_rewards')
                  .where('studentId', isEqualTo: actualUid)
                  .get();
              int aggregated = 0;
              for (final rd in rewardsSnap.docs) {
                aggregated += (rd.data()['pointsEarned'] as num?)?.toInt() ?? 0;
              }
              if (aggregated > 0) {
                studentData['aggregatedRewardPoints'] = aggregated;
              }
              rewardPoints = aggregated;
            }

            studentData['rewardPoints'] = rewardPoints;
          } catch (e) {
            studentData['rewardPoints'] = 0;
          }

          allStudents.add(studentData);
        }
      }

      return allStudents;
    } catch (e) {
      return [];
    }
  }

  /// Get subject-specific students (for subject teachers)
  /// subjectsHandled format: ["English"]
  Future<List<Map<String, dynamic>>> getStudentsBySubject(
    String schoolId,
    List<dynamic>? classesHandled,
    dynamic sections,
    List<dynamic>? subjectsHandled,
  ) async {
    try {
      if (subjectsHandled == null || subjectsHandled.isEmpty) {
        // If no specific subjects, return all students in teacher's classes
        return await getStudentsByTeacher(schoolId, classesHandled, sections);
      }

      print('📚 Fetching students for subjects: $subjectsHandled');

      final students = await getStudentsByTeacher(
        schoolId,
        classesHandled,
        sections,
      );

      // Filter students who take the teacher's subjects
      // (In a real system, you'd have a student-subject mapping)
      return students;
    } catch (e) {
      return [];
    }
  }

  /// Get class summary statistics
  Future<Map<String, dynamic>> getClassSummary(
    String schoolId,
    List<dynamic>? classesHandled,
    dynamic sections,
  ) async {
    try {
      final students = await getStudentsByTeacher(
        schoolId,
        classesHandled,
        sections,
      );

      return {
        'totalStudents': students.length,
        'activeStudents': students.where((s) => s['isActive'] == true).length,
        'grades': classesHandled?.isNotEmpty == true
            ? classesHandled![0]
            : 'N/A',
        'sections': sections ?? 'N/A',
      };
    } catch (e) {
      print('❌ Error calculating class summary: $e');
      return {
        'totalStudents': 0,
        'activeStudents': 0,
        'grades': 'N/A',
        'sections': 'N/A',
      };
    }
  }

  /// Get teacher's classes formatted for dropdown
  /// Input: classesHandled=["Grade 4", "Grade 5", "Grade 6"], sections=["A", "B"]
  /// Output: ["4 - A", "4 - B", "5 - A", "5 - B", "6 - A", "6 - B"]
  ///
  /// OR fallback: classAssignments=["Grade 10: A, Science", "Grade 10: B, Science"]
  /// Output: ["10 - A", "10 - B"]
  List<String> getTeacherClasses(
    List<dynamic>? classesHandled,
    dynamic sections, {
    List<dynamic>? classAssignments,
  }) {
    try {
      // Try primary format first: classesHandled + sections
      if (classesHandled != null && classesHandled.isNotEmpty) {
        // Normalize sections input (supports list or comma-separated string)
        final sectionList = _normalizeSections(sections);

        if (sectionList.isEmpty) {
          return _parseClassAssignments(classAssignments);
        }

        final List<String> result = [];

        // Loop through ALL classes, not just the first one
        for (final classItem in classesHandled) {
          // Extract grade/standard (could be "Grade 5" or just "5")
          String grade = classItem.toString();
          grade = grade
              .replaceAll('Grade ', '')
              .replaceAll('grade ', '')
              .trim();

          // Add all sections for this grade
          for (final section in sectionList) {
            result.add('$grade - $section');
          }
        }

        return result;
      }

      // Fallback: Parse from classAssignments
      return _parseClassAssignments(classAssignments);
    } catch (e) {
      return [];
    }
  }

  /// Parse classes from classAssignments format
  /// Input: ["Grade 10: A, Science", "Grade 10: B, Science"]
  /// Output: ["10 - A", "10 - B"]
  List<String> _parseClassAssignments(List<dynamic>? classAssignments) {
    if (classAssignments == null || classAssignments.isEmpty) {
      return [];
    }

    final Set<String> uniqueClasses = {};

    for (final assignment in classAssignments) {
      final assignmentStr = assignment.toString();
      // Format: "Grade 10: A, Science" or "Grade 10: B, Science"

      final parts = assignmentStr.split(':');
      if (parts.length < 2) continue;

      final gradePart = parts[0].trim(); // "Grade 10"
      final sectionPart = parts[1].split(',')[0].trim(); // "A" or "B"

      // Extract just the number from "Grade 10" -> "10"
      final grade = gradePart
          .replaceAll('Grade ', '')
          .replaceAll('grade ', '')
          .trim();

      uniqueClasses.add('$grade - $sectionPart');
    }

    final result = uniqueClasses.toList()..sort();
    print('✅ Parsed classes: $result');
    return result;
  }
}
