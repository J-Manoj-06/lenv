import 'package:cloud_firestore/cloud_firestore.dart';

class StudentProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get student subjects from profile
  Future<List<String>> getStudentSubjects(String studentId) async {
    try {
      // 1) Resolve profile robustly (student doc by uid/docId, then users fallback)
      final profile = await getStudentProfile(studentId);

      // 2) Try direct subject fields from profile
      final directSubjects = _extractSubjectsFromData(profile);
      if (directSubjects.isNotEmpty) return directSubjects;

      // 3) Try class-level sources
      String classId = _readStringField(profile, ['classId', 'classID']);
      if (classId.isEmpty) {
        classId = await _resolveClassIdFromProfile(profile);
      }
      if (classId.isNotEmpty) {
        final classSubjects = await _getSubjectsFromClass(classId);
        if (classSubjects.isNotEmpty) return classSubjects;

        final classSubcollectionSubjects =
            await _getSubjectsFromClassSubcollection(classId);
        if (classSubcollectionSubjects.isNotEmpty) {
          return classSubcollectionSubjects;
        }
      }

      return const <String>[];
    } catch (e) {
      return const <String>[];
    }
  }

  Future<String> _resolveClassIdFromProfile(
    Map<String, dynamic> profile,
  ) async {
    try {
      final fullClassName = _readStringField(profile, [
        'className',
        'class',
        'standard',
        'grade',
      ]);
      if (fullClassName.isEmpty) return '';

      String section = _readStringField(profile, ['section']);
      final schoolCode = _readStringField(profile, [
        'schoolCode',
        'schoolId',
        'instituteId',
      ]);

      String grade = '';
      final gradeMatch = RegExp(
        r'Grade\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(fullClassName);
      if (gradeMatch != null) {
        grade = 'Grade ${gradeMatch.group(1)}';
      }

      if (section.isEmpty) {
        final sectionMatch = RegExp(
          r'-\s*([A-Z])\s*$',
        ).firstMatch(fullClassName);
        if (sectionMatch != null) {
          section = sectionMatch.group(1) ?? '';
        }
      }

      if (grade.isEmpty) {
        grade = fullClassName;
      }

      if (schoolCode.isNotEmpty && section.isNotEmpty) {
        final q1 = await _firestore
            .collection('classes')
            .where('schoolCode', isEqualTo: schoolCode)
            .where('className', isEqualTo: grade)
            .where('section', isEqualTo: section)
            .limit(1)
            .get();
        if (q1.docs.isNotEmpty) return q1.docs.first.id;
      }

      if (section.isNotEmpty) {
        final q2 = await _firestore
            .collection('classes')
            .where('className', isEqualTo: grade)
            .where('section', isEqualTo: section)
            .limit(1)
            .get();
        if (q2.docs.isNotEmpty) return q2.docs.first.id;
      }

      final q3 = await _firestore
          .collection('classes')
          .where('className', isEqualTo: grade)
          .limit(10)
          .get();
      if (q3.docs.isNotEmpty) {
        if (section.isNotEmpty) {
          for (final d in q3.docs) {
            final docSection = (d.data()['section'] ?? '').toString();
            if (docSection == section) {
              return d.id;
            }
          }
        }
        return q3.docs.first.id;
      }

      final q4 = await _firestore
          .collection('classes')
          .where('className', isEqualTo: fullClassName)
          .limit(1)
          .get();
      if (q4.docs.isNotEmpty) return q4.docs.first.id;

      return '';
    } catch (_) {
      return '';
    }
  }

  // Fallback: get subjects from class collection
  Future<List<String>> _getSubjectsFromClass(String classId) async {
    try {
      final doc = await _firestore.collection('classes').doc(classId).get();
      if (doc.exists) {
        final data = doc.data() ?? <String, dynamic>{};
        final fromClassDoc = _extractSubjectsFromData(data);
        if (fromClassDoc.isNotEmpty) return fromClassDoc;
      }
      return const <String>[];
    } catch (e) {
      return const <String>[];
    }
  }

  Future<List<String>> _getSubjectsFromClassSubcollection(
    String classId,
  ) async {
    try {
      final snap = await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .get();

      final subjects = <String>[];
      for (final d in snap.docs) {
        final data = d.data();
        final name = _readStringField(data, ['name', 'subject', 'title']);
        if (name.isNotEmpty) {
          subjects.add(name);
        } else if (d.id.trim().isNotEmpty) {
          subjects.add(d.id.trim().replaceAll('_', ' '));
        }
      }
      return _normalizeSubjects(subjects);
    } catch (_) {
      return const <String>[];
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
      rethrow;
    }
  }

  // Get student profile data
  Future<Map<String, dynamic>> getStudentProfile(String studentId) async {
    try {
      // 1) students/{uid}
      final byDocId = await _firestore
          .collection('students')
          .doc(studentId)
          .get();
      if (byDocId.exists) {
        return byDocId.data() ?? <String, dynamic>{};
      }

      // 2) students where uid == studentId
      final byUid = await _firestore
          .collection('students')
          .where('uid', isEqualTo: studentId)
          .limit(1)
          .get();
      if (byUid.docs.isNotEmpty) {
        return byUid.docs.first.data();
      }

      // 3) users/{uid} fallback (some setups keep profile here)
      final userDoc = await _firestore.collection('users').doc(studentId).get();
      if (userDoc.exists) {
        return userDoc.data() ?? <String, dynamic>{};
      }

      return <String, dynamic>{};
    } catch (e) {
      return <String, dynamic>{};
    }
  }

  List<String> _extractSubjectsFromData(Map<String, dynamic> data) {
    final candidates = <String>[];

    final multiKeys = ['subjects', 'subjectList', 'studentSubjects'];
    for (final key in multiKeys) {
      final value = data[key];
      if (value is List) {
        candidates.addAll(value.map((e) => e.toString()));
      }
    }

    final single = _readStringField(data, ['subject', 'mainSubject']);
    if (single.isNotEmpty) candidates.add(single);

    return _normalizeSubjects(candidates);
  }

  List<String> _normalizeSubjects(List<String> raw) {
    final cleaned = raw
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s.replaceAll(RegExp(r'\s+'), ' '))
        .toSet()
        .toList();
    cleaned.sort();
    return cleaned;
  }

  String _readStringField(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  // Update student profile
  Future<void> updateStudentProfile(
    String studentId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _firestore.collection('students').doc(studentId).update(updates);
    } catch (e) {
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
      rethrow;
    }
  }
}
