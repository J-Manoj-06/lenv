import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student_model.dart';
import '../models/test_result_model.dart';
import '../models/reward_request_model.dart';

class ParentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get all children (students) linked to a parent by email
  /// First fetches parent document to get linkedStudents, then fetches each student
  Future<List<StudentModel>> getChildrenByParentEmail(
    String parentEmail,
  ) async {
    try {
      print('🔍 ParentService: Fetching children for parent: $parentEmail');

      // First, get the parent document to find linked students
      final parentQuery = await _firestore
          .collection('parents')
          .where('email', isEqualTo: parentEmail)
          .limit(1)
          .get();

      if (parentQuery.docs.isEmpty) {
        print('⚠️ ParentService: Parent document not found for $parentEmail');
        return [];
      }

      final parentDoc = parentQuery.docs.first;
      final parentData = parentDoc.data();
      final linkedStudents = parentData['linkedStudents'] as List<dynamic>?;

      if (linkedStudents == null || linkedStudents.isEmpty) {
        print('⚠️ ParentService: No linked students found in parent document');
        return [];
      }

      print(
        '📋 ParentService: Found ${linkedStudents.length} linked student(s)',
      );

      // Fetch each student by their ID
      final children = <StudentModel>[];
      for (var studentInfo in linkedStudents) {
        var studentId = studentInfo['id'] as String?;
        if (studentId != null) {
          // Trim whitespace and ensure clean ID
          studentId = studentId.trim();
          print(
            '  🔍 Attempting to fetch student ID: "$studentId" (length: ${studentId.length})',
          );

          try {
            final studentDoc = await _firestore
                .collection('students')
                .doc(studentId)
                .get();

            if (studentDoc.exists) {
              var studentModel = StudentModel.fromFirestore(studentDoc);
              // Fallback: if Firestore doc lacks name/class/section, use linkedStudents data
              final linkedName = (studentInfo['name'] as String?)?.trim();
              final linkedClass = (studentInfo['class'] as String?)?.trim();
              final linkedSection = (studentInfo['section'] as String?)?.trim();
              if ((studentModel.name.isEmpty) &&
                  (linkedName != null && linkedName.isNotEmpty)) {
                studentModel = studentModel.copyWith(name: linkedName);
              }
              if ((studentModel.className == null ||
                      (studentModel.className?.isEmpty ?? true)) &&
                  (linkedClass != null && linkedClass.isNotEmpty)) {
                studentModel = studentModel.copyWith(className: linkedClass);
              }
              if ((studentModel.section == null ||
                      (studentModel.section?.isEmpty ?? true)) &&
                  (linkedSection != null && linkedSection.isNotEmpty)) {
                studentModel = studentModel.copyWith(section: linkedSection);
              }
              children.add(studentModel);
              print('  ✅ Loaded student: ${linkedName ?? studentModel.name}');
            } else {
              print('  ⚠️ Student document not found: $studentId');
              print('  ℹ️ Trying to query by uid field instead...');

              // Try querying by uid field as fallback
              final querySnapshot = await _firestore
                  .collection('students')
                  .where('uid', isEqualTo: studentId)
                  .limit(1)
                  .get();

              if (querySnapshot.docs.isNotEmpty) {
                children.add(
                  StudentModel.fromFirestore(querySnapshot.docs.first),
                );
                print(
                  '  ✅ Found student via uid query: ${studentInfo['name']}',
                );
              } else {
                print('  ❌ Student not found by document ID or uid field');
                print(
                  '  ℹ️ Creating placeholder student from linkedStudents data',
                );

                // Create a minimal student model from the linkedStudents data
                final placeholderStudent = StudentModel(
                  uid: studentId,
                  name: (studentInfo['name'] as String?) ?? 'Unknown Student',
                  email: '', // No email in linkedStudents
                  schoolCode: parentData['schoolCode'] as String? ?? '',
                  className: (studentInfo['class'] as String?) ?? '',
                  section: (studentInfo['section'] as String?) ?? '',
                  rewardPoints: 0,
                  monthlyProgress: 0.0,
                  createdAt: DateTime.now(),
                );
                children.add(placeholderStudent);
                print(
                  '  ⚠️ Using placeholder data for: ${studentInfo['name']}',
                );
              }
            }
          } catch (e) {
            print('  ❌ Error fetching student $studentId: $e');
          }
        } else {
          print('  ⚠️ Student info has no id field: $studentInfo');
        }
      }

      print('✅ ParentService: Successfully loaded ${children.length} children');
      return children;
    } catch (e) {
      print('❌ ParentService Error fetching children: $e');
      return [];
    }
  }

  /// Get real-time stream of children for a parent
  /// Note: This returns a stream but checks parent's linkedStudents on each update
  Stream<List<StudentModel>> getChildrenStream(String parentEmail) async* {
    try {
      // Get parent document to find linked student IDs
      final parentQuery = await _firestore
          .collection('parents')
          .where('email', isEqualTo: parentEmail)
          .limit(1)
          .get();

      if (parentQuery.docs.isEmpty) {
        yield [];
        return;
      }

      final parentDoc = parentQuery.docs.first;
      final parentData = parentDoc.data();
      final linkedStudents = parentData['linkedStudents'] as List<dynamic>?;

      if (linkedStudents == null || linkedStudents.isEmpty) {
        yield [];
        return;
      }

      // Fetch students by IDs
      final children = <StudentModel>[];
      for (var studentInfo in linkedStudents) {
        final studentId = studentInfo['id'] as String?;
        if (studentId != null) {
          try {
            final studentDoc = await _firestore
                .collection('students')
                .doc(studentId)
                .get();

            if (studentDoc.exists) {
              children.add(StudentModel.fromFirestore(studentDoc));
            }
          } catch (e) {
            print('Error fetching student $studentId: $e');
          }
        }
      }

      yield children;
    } catch (e) {
      print('Error in children stream: $e');
      yield [];
    }
  }

  /// Get student's test results with detailed information
  Future<List<TestResultModel>> getStudentTestResults(String studentId) async {
    try {
      final querySnapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .orderBy('completedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => TestResultModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Error fetching test results: $e');
      return [];
    }
  }

  /// Get student's test results stream
  Stream<List<TestResultModel>> getStudentTestResultsStream(String studentId) {
    return _firestore
        .collection('testResults')
        .where('studentId', isEqualTo: studentId)
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TestResultModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// Get student's reward requests
  Future<List<RewardRequestModel>> getStudentRewardRequests(
    String studentId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('reward_requests')
          .where('studentId', isEqualTo: studentId)
          .orderBy('requestedAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => RewardRequestModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('❌ Error fetching reward requests: $e');
      return [];
    }
  }

  /// Get student's reward requests stream
  Stream<List<RewardRequestModel>> getStudentRewardRequestsStream(
    String studentId,
  ) {
    return _firestore
        .collection('reward_requests')
        .where('studentId', isEqualTo: studentId)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RewardRequestModel.fromJson(doc.data()))
              .toList(),
        );
  }

  /// Get announcements for student's class
  Future<List<Map<String, dynamic>>> getAnnouncementsForStudent(
    String studentId,
  ) async {
    try {
      // First get student data to know their class
      final studentDoc = await _firestore
          .collection('students')
          .doc(studentId)
          .get();

      if (!studentDoc.exists) return [];

      final studentData = studentDoc.data()!;
      final schoolCode = studentData['schoolCode'] as String?;
      final className = studentData['className'] as String?;
      final section = studentData['section'] as String?;

      if (schoolCode == null || className == null) return [];

      // Fetch class-level announcements (no section filter)
      final classQuerySnapshot = await _firestore
          .collection('announcements')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: className)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      // Optionally fetch section-level announcements for the student's section
      List<QueryDocumentSnapshot<Map<String, dynamic>>> sectionDocs = [];
      if (section != null && section.isNotEmpty) {
        final sectionQuerySnapshot = await _firestore
            .collection('announcements')
            .where('schoolCode', isEqualTo: schoolCode)
            .where('className', isEqualTo: className)
            .where('section', isEqualTo: section)
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();
        sectionDocs = sectionQuerySnapshot.docs;
      }

      // Merge and de-duplicate by id
      final allDocs = <String, Map<String, dynamic>>{};
      for (final doc in classQuerySnapshot.docs) {
        final data = doc.data();
        allDocs[doc.id] = {'id': doc.id, ...data};
      }
      for (final doc in sectionDocs) {
        final data = doc.data();
        allDocs[doc.id] = {'id': doc.id, ...data};
      }

      // Sort by createdAt desc (if present)
      final results = allDocs.values.toList();
      results.sort((a, b) {
        final aTs = a['createdAt'];
        final bTs = b['createdAt'];
        DateTime? ad;
        DateTime? bd;
        if (aTs is Timestamp) ad = aTs.toDate();
        if (bTs is Timestamp) bd = bTs.toDate();
        if (ad != null && bd != null) {
          return bd.compareTo(ad);
        }
        return 0;
      });

      // Limit to a reasonable number
      return results.take(20).toList();
    } catch (e) {
      print('❌ Error fetching announcements: $e');
      return [];
    }
  }

  /// Get announcements stream for student's class
  Stream<List<Map<String, dynamic>>> getAnnouncementsStream(
    String schoolCode,
    String className,
    String? section,
  ) {
    var query = _firestore
        .collection('announcements')
        .where('schoolCode', isEqualTo: schoolCode)
        .where('className', isEqualTo: className);

    if (section != null && section.isNotEmpty) {
      query = query.where('section', isEqualTo: section);
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  /// Approve or reject a reward request
  Future<bool> updateRewardRequestStatus({
    required String requestId,
    required String status, // 'approved' or 'rejected'
    String? parentNote,
  }) async {
    try {
      final updateData = {
        'status': status,
        'parentApprovedAt': FieldValue.serverTimestamp(),
      };

      if (parentNote != null) {
        updateData['parentNote'] = parentNote;
      }

      await _firestore
          .collection('reward_requests')
          .doc(requestId)
          .update(updateData);

      print('✅ Reward request $status: $requestId');
      return true;
    } catch (e) {
      print('❌ Error updating reward request: $e');
      return false;
    }
  }

  /// Get student's reward points history
  Future<List<Map<String, dynamic>>> getStudentRewardHistory(
    String studentId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('student_rewards')
          .where('studentId', isEqualTo: studentId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();
    } catch (e) {
      print('❌ Error fetching reward history: $e');
      return [];
    }
  }

  /// Get student's performance statistics
  Future<Map<String, dynamic>> getStudentPerformanceStats(
    String studentId,
  ) async {
    try {
      // Get all test results
      final testResults = await getStudentTestResults(studentId);

      if (testResults.isEmpty) {
        return {
          'totalTests': 0,
          'averageScore': 0.0,
          'highestScore': 0.0,
          'lowestScore': 0.0,
          'completedTests': 0,
          'pendingTests': 0,
        };
      }

      // Calculate statistics
      final completedTests = testResults; // All testResults are completed

      double totalScore = 0;
      double highestScore = 0;
      double lowestScore = 100;

      for (var result in completedTests) {
        final percentage = result.percentage ?? 0;
        totalScore += percentage;
        if (percentage > highestScore) highestScore = percentage;
        if (percentage < lowestScore) lowestScore = percentage;
      }

      final averageScore = completedTests.isNotEmpty
          ? totalScore / completedTests.length
          : 0.0;

      // Get pending tests count
      final pendingQuery = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'assigned')
          .get();

      return {
        'totalTests': testResults.length,
        'averageScore': averageScore,
        'highestScore': highestScore,
        'lowestScore': lowestScore == 100 ? 0.0 : lowestScore,
        'completedTests': completedTests.length,
        'pendingTests': pendingQuery.docs.length,
      };
    } catch (e) {
      print('❌ Error calculating performance stats: $e');
      return {
        'totalTests': 0,
        'averageScore': 0.0,
        'highestScore': 0.0,
        'lowestScore': 0.0,
        'completedTests': 0,
        'pendingTests': 0,
      };
    }
  }

  /// Get conversations between parent and teachers
  Future<List<Map<String, dynamic>>> getParentConversations(
    String parentId,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('conversations')
          .where('parentId', isEqualTo: parentId)
          .orderBy('lastMessageAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();
    } catch (e) {
      print('❌ Error fetching conversations: $e');
      return [];
    }
  }

  /// Get messages from a specific conversation
  Stream<List<Map<String, dynamic>>> getConversationMessages(
    String conversationId,
  ) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  /// Get student's attendance percentage
  Future<double> getStudentAttendance(String studentId) async {
    try {
      // This would query attendance records if implemented
      // For now, return a default value
      final studentDoc = await _firestore
          .collection('students')
          .doc(studentId)
          .get();

      if (studentDoc.exists) {
        final data = studentDoc.data();
        return (data?['attendancePercentage'] as num?)?.toDouble() ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      print('❌ Error fetching attendance: $e');
      return 0.0;
    }
  }

  /// Get upcoming tests for student
  Future<List<Map<String, dynamic>>> getUpcomingTests(String studentId) async {
    try {
      final now = DateTime.now();

      final querySnapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'assigned')
          .get();

      // Filter for future tests
      final upcomingTests = <Map<String, dynamic>>[];

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final testId = data['testId'] as String?;

        if (testId != null) {
          // Get test details
          final testDoc = await _firestore
              .collection('scheduledTests')
              .doc(testId)
              .get();

          if (testDoc.exists) {
            final testData = testDoc.data()!;
            final startDate = testData['startDate'];

            DateTime? testDate;
            if (startDate is Timestamp) {
              testDate = startDate.toDate();
            } else if (startDate is String) {
              try {
                testDate = DateTime.parse(startDate);
              } catch (_) {}
            }

            if (testDate != null && testDate.isAfter(now)) {
              upcomingTests.add({
                'id': testId,
                'resultId': doc.id,
                ...testData,
                'assignmentData': data,
              });
            }
          }
        }
      }

      // Sort by date
      upcomingTests.sort((a, b) {
        final aDate = a['startDate'];
        final bDate = b['startDate'];

        DateTime? dateA;
        DateTime? dateB;

        if (aDate is Timestamp) dateA = aDate.toDate();
        if (bDate is Timestamp) dateB = bDate.toDate();

        if (dateA != null && dateB != null) {
          return dateA.compareTo(dateB);
        }
        return 0;
      });

      return upcomingTests;
    } catch (e) {
      print('❌ Error fetching upcoming tests: $e');
      return [];
    }
  }
}
