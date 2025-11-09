import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get teacher details by email
  Future<Map<String, dynamic>?> getTeacherByEmail(String email) async {
    try {
      print('📚 Fetching teacher data for: $email');
      final querySnapshot = await _firestore
          .collection('teachers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        data['id'] = querySnapshot.docs.first.id;
        print('✅ Teacher found: ${data['teacherName']}');
        print('   classesHandled: ${data['classesHandled']}');
        print('   section: ${data['section']}');
        print('   sections: ${data['sections']}');
        return data;
      }

      print('⚠️ No teacher found with email: $email');
      return null;
    } catch (e) {
      print('❌ Error fetching teacher: $e');
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
        print(
          '📚 Fetching students for classes: $classesHandled and sections: $sections',
        );

        final sectionList = _normalizeSections(sections);
        if (sectionList.isEmpty) {
          print('⚠️ No sections provided, cannot query students');
          return [];
        }

        for (final classItem in classesHandled) {
          final className = classItem.toString(); // e.g., "Grade 5"
          print('  Class: $className, Sections: $sectionList');

          for (final section in sectionList) {
            if (section.isEmpty) continue;

            print(
              '  🔍 Querying WHERE schoolCode == "$schoolId" AND className == "$className" AND section == "$section"',
            );
            final querySnapshot = await _firestore
                .collection('students')
                .where('schoolCode', isEqualTo: schoolId)
                .where('className', isEqualTo: className)
                .where('section', isEqualTo: section)
                .get();

            print(
              '     ✅ Found ${querySnapshot.docs.length} students in $className - $section',
            );
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
                  print(
                    '   💰 ${studentData['studentName']}: $totalPoints points (from ${rewardsSnapshot.docs.length} rewards)',
                  );
                } else {
                  studentData['rewardPoints'] = 0;
                }
              } catch (e) {
                print(
                  '   ⚠️ Error fetching rewardPoints for ${studentData['studentName']}: $e',
                );
                studentData['rewardPoints'] = 0;
              }

              allStudents.add(studentData);
            }
          }
        }
        print('✅ Found ${allStudents.length} students');
        return allStudents;
      }

      // Fallback: Use classAssignments (e.g., "Grade 10: A, Science")
      print('⚠️ No classesHandled; trying classAssignments fallback');
      final formatted = getTeacherClasses(
        null,
        null,
        classAssignments: classAssignments,
      );
      if (formatted.isEmpty) {
        print('⚠️ No formatted classes from assignments; returning empty');
        return [];
      }

      print('📚 Fetching students for formatted classes: $formatted');
      for (final fc in formatted) {
        // fc like "10 - A" -> className="Grade 10", section="A"
        final parts = fc.split(' - ');
        if (parts.length != 2) continue;
        final className = 'Grade ${parts[0].trim()}';
        final section = parts[1].trim();

        print(
          '  🔍 Querying WHERE schoolCode == "$schoolId" AND className == "$className" AND section == "$section"',
        );
        final querySnapshot = await _firestore
            .collection('students')
            .where('schoolCode', isEqualTo: schoolId)
            .where('className', isEqualTo: className)
            .where('section', isEqualTo: section)
            .get();

        print(
          '     ✅ Found ${querySnapshot.docs.length} students in $className - $section',
        );
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
              print(
                '   💰 ${studentData['studentName']}: $totalPoints points (from ${rewardsSnapshot.docs.length} rewards)',
              );
            } else {
              studentData['rewardPoints'] = 0;
            }
          } catch (e) {
            print(
              '   ⚠️ Error fetching rewardPoints for ${studentData['studentName']}: $e',
            );
            studentData['rewardPoints'] = 0;
          }

          allStudents.add(studentData);
        }
      }

      print('✅ Found ${allStudents.length} students (assignments fallback)');
      return allStudents;
    } catch (e) {
      print('❌ Error fetching students: $e');
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
        print('! No valid sections found for classes: $classesHandled');
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
      print('✅ Formatted classes: $result');
      return result;
    }

    // Fallback: Try classAssignments
    if (classAssignments != null && classAssignments.isNotEmpty) {
      print('! No classesHandled data, trying classAssignments fallback');
      print('📋 Parsing from classAssignments: $classAssignments');
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
      print('✅ Parsed classes: ${result.toList()}');
      return result.toList();
    }

    print('! No classesHandled or classAssignments found');
    return [];
  }
}
