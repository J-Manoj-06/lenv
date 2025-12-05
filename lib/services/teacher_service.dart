import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache to avoid redundant queries
  static final Map<String, Map<String, dynamic>> _teacherCache = {};
  static final Map<String, List<Map<String, dynamic>>> _studentsCache = {};
  static DateTime? _teacherCacheTime;
  static DateTime? _studentsCacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Get teacher details by email with caching
  Future<Map<String, dynamic>?> getTeacherByEmail(String email) async {
    try {
      // Check cache first
      final now = DateTime.now();
      if (_teacherCache.containsKey(email) &&
          _teacherCacheTime != null &&
          now.difference(_teacherCacheTime!) < _cacheDuration) {
        return _teacherCache[email];
      }

      final querySnapshot = await _firestore
          .collection('teachers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        data['id'] = querySnapshot.docs.first.id;

        // Cache the result
        _teacherCache[email] = data;
        _teacherCacheTime = now;

        return data;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Clear cache manually if needed
  static void clearCache() {
    _teacherCache.clear();
    _studentsCache.clear();
    _teacherCacheTime = null;
    _studentsCacheTime = null;
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
      // Create cache key from parameters
      final cacheKey = '$schoolId-$classesHandled-$sections-$classAssignments';

      // Check cache first
      final now = DateTime.now();
      if (_studentsCache.containsKey(cacheKey) &&
          _studentsCacheTime != null &&
          now.difference(_studentsCacheTime!) < _cacheDuration) {
        return _studentsCache[cacheKey]!;
      }

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

              // ✅ OPTIMIZED: Use cached rewardPoints from student document
              // The rewardPoints field is automatically updated when students earn points
              // No need to query users collection or aggregate student_rewards
              final rewardPoints =
                  studentData['rewardPoints'] as int? ??
                  studentData['totalPoints'] as int? ??
                  0;
              studentData['rewardPoints'] = rewardPoints;

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

          // ✅ OPTIMIZED: Use cached rewardPoints from student document
          final rewardPoints =
              studentData['rewardPoints'] as int? ??
              studentData['totalPoints'] as int? ??
              0;
          studentData['rewardPoints'] = rewardPoints;

          allStudents.add(studentData);
        }
      }

      // Cache the results
      _studentsCache[cacheKey] = allStudents;
      _studentsCacheTime = now;

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

  /// Stream version of getStudentsByTeacher for real-time updates
  Stream<List<Map<String, dynamic>>> getStudentsByTeacherStream(
    String schoolId,
    List<dynamic>? classesHandled,
    dynamic sections, {
    List<dynamic>? classAssignments,
  }) {
    try {
      // Parse class-section combinations from classAssignments
      List<Map<String, String>> classesInfo = [];

      if (classAssignments != null && classAssignments.isNotEmpty) {
        // Parse "Grade 10: A, Subject" format
        for (final assignment in classAssignments) {
          final assignmentStr = assignment.toString();
          final colonParts = assignmentStr.split(':');
          if (colonParts.length < 2) continue;

          final gradeRaw = colonParts[0].trim();
          final rightSide = colonParts[1];
          final commaParts = rightSide.split(',');
          if (commaParts.isEmpty) continue;

          final sectionPart = commaParts[0].trim();
          final className = gradeRaw; // e.g., "Grade 10"

          classesInfo.add({'className': className, 'section': sectionPart});
        }
      } else if (classesHandled != null && classesHandled.isNotEmpty) {
        final sectionList = _normalizeSections(sections);
        for (final classItem in classesHandled) {
          final className = classItem.toString();
          for (final section in sectionList) {
            if (section.isNotEmpty) {
              classesInfo.add({'className': className, 'section': section});
            }
          }
        }
      }

      if (classesInfo.isEmpty) {
        return Stream.value([]);
      }

      // ✅ OPTIMIZED: Query only the specific class-section combinations
      // Use the first class-section as the primary query
      final firstClass = classesInfo.first;

      return _firestore
          .collection('students')
          .where('schoolCode', isEqualTo: schoolId)
          .where('className', isEqualTo: firstClass['className'])
          .where('section', isEqualTo: firstClass['section'])
          .snapshots()
          .asyncMap((snapshot) async {
            final List<Map<String, dynamic>> allStudents = [];

            // Add students from first query
            for (var doc in snapshot.docs) {
              final studentData = doc.data();
              studentData['id'] = doc.id;
              // ✅ Use cached rewardPoints
              studentData['rewardPoints'] =
                  studentData['rewardPoints'] as int? ?? 0;
              allStudents.add(studentData);
            }

            // ✅ Fetch remaining classes in parallel (if any)
            if (classesInfo.length > 1) {
              final additionalQueries = classesInfo.skip(1).map((classInfo) {
                return _firestore
                    .collection('students')
                    .where('schoolCode', isEqualTo: schoolId)
                    .where('className', isEqualTo: classInfo['className'])
                    .where('section', isEqualTo: classInfo['section'])
                    .get();
              });

              final results = await Future.wait(additionalQueries);
              for (var result in results) {
                for (var doc in result.docs) {
                  final studentData = doc.data();
                  studentData['id'] = doc.id;
                  studentData['rewardPoints'] =
                      studentData['rewardPoints'] as int? ?? 0;
                  allStudents.add(studentData);
                }
              }
            }

            return allStudents;
          });
    } catch (e) {
      print('❌ Error in getStudentsStream: $e');
      return Stream.value([]);
    }
  }
}
