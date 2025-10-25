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
    dynamic sections,
  ) async {
    try {
      if (classesHandled == null || classesHandled.isEmpty) {
        print('⚠️ No classes handled by teacher');
        return [];
      }

      print(
        '📚 Fetching students for classes: $classesHandled and sections: $sections',
      );

      // Keep the full className format as it appears in Firestore (e.g., "Grade 5")
      String className = classesHandled[0].toString();

      // Normalize sections from string or list
      final sectionList = _normalizeSections(sections);

      print('  Class: $className, Sections: $sectionList');

      final List<Map<String, dynamic>> allStudents = [];

      // Query students by school, className, and sections
      // NOTE: Using 'schoolCode' and 'className' to match actual Firestore field names
      for (var section in sectionList) {
        if (section.isEmpty) continue;

        print('  🔍 Querying section: $section');
        print('     WHERE schoolCode == "$schoolId"');
        print('     AND className == "$className"');
        print('     AND section == "$section"');

        final querySnapshot = await _firestore
            .collection('students')
            .where('schoolCode', isEqualTo: schoolId)
            .where('className', isEqualTo: className)
            .where('section', isEqualTo: section)
            .get();

        print(
          '     ✅ Found ${querySnapshot.docs.length} students in section $section',
        );

        for (var doc in querySnapshot.docs) {
          final studentData = doc.data();
          studentData['id'] = doc.id;
          allStudents.add(studentData);
        }
      }

      print('✅ Found ${allStudents.length} students');
      return allStudents;
    } catch (e) {
      print('❌ Error fetching students: $e');
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
      print('✅ Found ${students.length} students taking subjects');
      return students;
    } catch (e) {
      print('❌ Error fetching students by subject: $e');
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
  /// Input: classesHandled=["Grade 5"], sections="A, B, C"
  /// Output: ["5 - A", "5 - B", "5 - C"]
  List<String> getTeacherClasses(
    List<dynamic>? classesHandled,
    dynamic sections,
  ) {
    try {
      if (classesHandled == null || classesHandled.isEmpty) {
        print('⚠️ No classesHandled data');
        return [];
      }

      print(
        '📋 Formatting classes from: $classesHandled and sections: $sections',
      );

      // Extract grade/standard (could be "Grade 5" or just "5")
      String grade = classesHandled[0].toString();
      grade = grade.replaceAll('Grade ', '').replaceAll('grade ', '').trim();

      // Normalize sections input (supports list or comma-separated string)
      final sectionList = _normalizeSections(sections);

      print('  Grade: $grade');
      print('  Sections: $sectionList');

      final result = sectionList.map((section) => '$grade - $section').toList();
      print('✅ Formatted classes: $result');

      return result;
    } catch (e) {
      print('❌ Error formatting classes: $e');
      return [];
    }
  }
}
