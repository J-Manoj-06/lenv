import 'package:cloud_firestore/cloud_firestore.dart';

class StudentProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get student subjects from profile
  Future<List<String>> getStudentSubjects(String studentId) async {
    try {
      // Force server read to avoid stale cache
      final doc = await _firestore
          .collection('students')
          .doc(studentId)
          .get(const GetOptions(source: Source.server));

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('subjects')) {
          return List<String>.from(data['subjects'] ?? []);
        }

        // Fallback: fetch from class collection
        final classId = data?['classId'] as String?;
        if (classId != null) {
          return await _getSubjectsFromClass(classId);
        }
      }

      // Default subjects if nothing found
      return ['Maths', 'Science', 'English', 'Social'];
    } catch (e) {
      print('Error fetching student subjects: $e');
      return ['Maths', 'Science', 'English', 'Social'];
    }
  }

  // Fallback: get subjects from class collection
  Future<List<String>> _getSubjectsFromClass(String classId) async {
    try {
      // Force server read to avoid stale cache
      final doc = await _firestore
          .collection('classes')
          .doc(classId)
          .get(const GetOptions(source: Source.server));
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('subjects')) {
          return List<String>.from(data['subjects'] ?? []);
        }
      }
      return [];
    } catch (e) {
      print('Error fetching subjects from class: $e');
      return [];
    }
  }

  // Update student profile with subjects
  Future<void> updateStudentSubjects(
    String studentId,
    List<String> subjects,
  ) async {
    try {
      await _firestore.collection('students').doc(studentId).update({
        'subjects': subjects,
      });
    } catch (e) {
      print('Error updating student subjects: $e');
      rethrow;
    }
  }

  // Get student profile data
  Future<Map<String, dynamic>> getStudentProfile(String studentId) async {
    try {
      // Force server read to avoid stale cache
      final doc = await _firestore
          .collection('students')
          .doc(studentId)
          .get(const GetOptions(source: Source.server));
      if (doc.exists) {
        return doc.data() ?? {};
      }
      return {};
    } catch (e) {
      print('Error fetching student profile: $e');
      return {};
    }
  }

  // Update student profile
  Future<void> updateStudentProfile(
    String studentId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _firestore.collection('students').doc(studentId).update(updates);
    } catch (e) {
      print('Error updating student profile: $e');
      rethrow;
    }
  }

  // Set complete profile (with merge)
  Future<void> setStudentProfile(
    String studentId,
    Map<String, dynamic> profile,
  ) async {
    try {
      await _firestore
          .collection('students')
          .doc(studentId)
          .set(profile, SetOptions(merge: true));
    } catch (e) {
      print('Error setting student profile: $e');
      rethrow;
    }
  }
}
