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

              // Fetch total points from student_rewards collection
              try {
                final studentId = studentData['studentId'];
                if (studentId != null && studentId.toString().isNotEmpty) {
                  // Query all rewards for this student
                  final rewardsSnapshot = await _firestore
                      .collection('student_rewards')
                      .where('studentId', isEqualTo: studentId)
                      .get();

                  // Sum up all pointsEarned
                  int totalPoints = 0;
                  for (var rewardDoc in rewardsSnapshot.docs) {
                    final rewardData = rewardDoc.data();
                    final pointsEarned = rewardData['pointsEarned'];
                    if (pointsEarned is int) {
                      totalPoints += pointsEarned;
                    } else if (pointsEarned is String) {
                      totalPoints += int.tryParse(pointsEarned) ?? 0;
                    }
                  }

                  studentData['rewardPoints'] = totalPoints;
                } else {
                  studentData['rewardPoints'] = 0;
                }
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

          // Fetch total points from student_rewards collection
          try {
            final studentId = studentData['studentId'];
            if (studentId != null && studentId.toString().isNotEmpty) {
              // Query all rewards for this student
              final rewardsSnapshot = await _firestore
                  .collection('student_rewards')
                  .where('studentId', isEqualTo: studentId)
                  .get();

              // Sum up all pointsEarned
              int totalPoints = 0;
              for (var rewardDoc in rewardsSnapshot.docs) {
                final rewardData = rewardDoc.data();
                final pointsEarned = rewardData['pointsEarned'];
                if (pointsEarned is int) {
                  totalPoints += pointsEarned;
                } else if (pointsEarned is String) {
                  totalPoints += int.tryParse(pointsEarned) ?? 0;
                }
              }

              studentData['rewardPoints'] = totalPoints;
            } else {
              studentData['rewardPoints'] = 0;
            }
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

  // ... rest of the methods (getTeacherClasses, etc.) remain the same

  /// Get formatted list of teacher classes
  List<String> getTeacherClasses(
    List<dynamic>? classesHandled,
    dynamic sections, {
    List<dynamic>? classAssignments,
  }) {
    // If classesHandled exists, combine with sections
    if (classesHandled != null && classesHandled.isNotEmpty) {
      final sectionList = _normalizeSections(sections);
      if (sectionList.isEmpty) {
        return [];
      }

      final result = <String>[];
      for (final classItem in classesHandled) {
        final className = classItem.toString();
        // Extract grade number from "Grade X" format
        final grade = className
            .replaceAll('Grade ', '')
            .replaceAll('grade ', '')
            .trim();
        for (final section in sectionList) {
          result.add('$grade - $section');
        }
      }
      return result;
    }

    // Fallback: Try classAssignments
    if (classAssignments != null && classAssignments.isNotEmpty) {
      final result = <String>{};
      for (final assignment in classAssignments) {
        final parts = assignment.toString().split(':');
        if (parts.length >= 2) {
          final grade = parts[0]
              .trim()
              .replaceAll('Grade ', '')
              .replaceAll('grade ', '');
          final section = parts[1].trim().split(',')[0].trim();
          result.add('$grade - $section');
        }
      }
      return result.toList();
    }

    return [];
  }
}
