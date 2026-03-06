import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/test_model.dart';
import '../models/reward_model.dart';
import '../models/performance_model.dart';
import '../models/test_result_model.dart';
import '../models/product_model.dart';
import '../models/reward_points_model.dart';
import '../models/reward_request_model.dart';
import 'badge_rules.dart';
import 'badge_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // User Operations
  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toJson());
  }

  Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data()!;
      // CRITICAL: Ensure uid is set in the data map before converting to UserModel
      data['uid'] = uid;
      return UserModel.fromJson(data);
    }
    return null;
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  Stream<List<UserModel>> getUsersByRole(UserRole role, String instituteId) {
    return _db
        .collection('users')
        .where('role', isEqualTo: role.toString().split('.').last)
        .where('instituteId', isEqualTo: instituteId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            // CRITICAL: Ensure uid is set in the data map before converting to UserModel
            data['uid'] = doc.id;
            return UserModel.fromJson(data);
          }).toList(),
        );
  }

  // Test Operations
  Future<String> createTest(TestModel test) async {
    // Store test definitions in scheduledTests collection instead of tests
    final docRef = _db.collection('scheduledTests').doc();
    final data = test.toJson();
    data['id'] = docRef.id;

    // Best-effort: attach schoolCode from teacher profile to avoid cross-school confusion
    try {
      String? schoolCode;
      // Try direct teacher document by UID
      final teacherByUid = await _db
          .collection('teachers')
          .doc(test.teacherId)
          .get();
      if (teacherByUid.exists) {
        schoolCode = (teacherByUid.data()?['schoolCode'] as String?)?.trim();
      }
      // Fallback: try by current auth email
      if ((schoolCode == null || schoolCode.isEmpty)) {
        final currentUser = FirebaseAuth.instance.currentUser;
        final email = currentUser?.email;
        if (email != null && email.isNotEmpty) {
          final tq = await _db
              .collection('teachers')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();
          if (tq.docs.isNotEmpty) {
            schoolCode = (tq.docs.first.data()['schoolCode'] as String?)
                ?.trim();
          }
        }
      }
      if (schoolCode != null && schoolCode.isNotEmpty) {
        data['schoolCode'] = schoolCode;
      }
    } catch (_) {
      // non-fatal
    }

    await docRef.set(data);
    return docRef.id;
  }

  // Assign test to all students in the specified class/section using teacher's schoolCode and test's target class
  Future<void> assignTestToClass(String testId, String teacherAuthUid) async {
    try {
      // Fetch test document to get the target className and section
      final testDoc = await _db.collection('scheduledTests').doc(testId).get();
      if (!testDoc.exists) {
        return;
      }
      final testData = testDoc.data()!;
      final targetClassName =
          testData['class'] ?? testData['className'] as String? ?? '';
      final targetSection = testData['section'] as String? ?? '';
      final testTitle =
          testData['title'] ?? testData['testTitle'] ?? 'Untitled Test';
      final subject = testData['subject'] ?? '';
      final teacherName = testData['teacherName'] ?? '';

      // Fetch teacher document
      var teacherDoc = await _db
          .collection('teachers')
          .doc(teacherAuthUid)
          .get();
      Map<String, dynamic>? teacherData;

      if (!teacherDoc.exists) {
        // Get teacher email from Firebase Auth current user
        final currentUser = FirebaseAuth.instance.currentUser;
        final userEmail = currentUser?.email;

        if (userEmail != null) {
          final teacherQuery = await _db
              .collection('teachers')
              .where('email', isEqualTo: userEmail)
              .limit(1)
              .get();
          if (teacherQuery.docs.isNotEmpty) {
            teacherData = teacherQuery.docs.first.data();
          }
        }
      } else {
        teacherData = teacherDoc.data();
      }

      if (teacherData == null) {
        return;
      }

      final schoolCode = teacherData['schoolCode'] as String? ?? '';

      if (schoolCode.isEmpty || targetClassName.isEmpty) {
        return;
      }

      // Query students by schoolCode, className, section
      var query = _db
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: targetClassName);
      if (targetSection.isNotEmpty) {
        query = query.where('section', isEqualTo: targetSection);
      }
      final snapshot = await query.get();

      // Batch fetch all user documents at once for better performance
      final studentEmails = <String>[];
      final studentDataMap = <String, Map<String, dynamic>>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final email =
            data['email'] as String? ?? data['studentEmail'] as String?;
        if (email != null && email.isNotEmpty) {
          studentEmails.add(email);
          studentDataMap[email] = {
            'docId': doc.id,
            'name':
                data['studentName'] as String? ??
                (data['name'] as String? ?? ''),
            'data': data,
          };
        }
      }

      // Batch query users collection
      final userDocs = await Future.wait(
        studentEmails.map(
          (email) => _db
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get(),
        ),
      );

      final studentAssignments = <Map<String, String>>[];
      final usersToCreate = <String, Map<String, dynamic>>{};

      for (var i = 0; i < studentEmails.length; i++) {
        final email = studentEmails[i];
        final userQuery = userDocs[i];
        final studentInfo = studentDataMap[email]!;

        String? uid;
        if (userQuery.docs.isNotEmpty) {
          final userData = userQuery.docs.first.data();
          uid = (userData['uid'] as String?)?.trim();
        } else {
          // User doesn't exist, prepare to create
          uid = studentInfo['docId'] as String;
          usersToCreate[uid] = {
            'uid': uid,
            'email': email,
            'name': studentInfo['name'],
            'role': 'student',
            'schoolCode': schoolCode,
            'className': studentInfo['data']['className'] ?? targetClassName,
            'section': studentInfo['data']['section'] ?? targetSection,
            'pendingTests': 0,
            'completedTests': 0,
            'newNotifications': 0,
            'totalPoints': studentInfo['data']['totalPoints'] ?? 0,
            'rewardPoints': studentInfo['data']['rewardPoints'] ?? 0,
            'createdAt': FieldValue.serverTimestamp(),
            'autoCreated': true,
          };
        }

        if (uid != null && uid.isNotEmpty) {
          studentAssignments.add({
            'studentId': uid,
            'studentEmail': email,
            'studentName': studentInfo['name'],
          });
        }
      }

      // Check existing assignments in batch - handle Firestore's whereIn limit of 10
      final existingStudentIds = <String>{};
      final allStudentIds = studentAssignments
          .map((s) => s['studentId']!)
          .toList();

      // Query in chunks of 10 (Firestore whereIn limit)
      for (var i = 0; i < allStudentIds.length; i += 10) {
        final chunk = allStudentIds.skip(i).take(10).toList();
        final existingAssignments = await _db
            .collection('testResults')
            .where('testId', isEqualTo: testId)
            .where('studentId', whereIn: chunk)
            .get();

        existingStudentIds.addAll(
          existingAssignments.docs
              .map((doc) => doc.data()['studentId'] as String?)
              .where((id) => id != null)
              .cast<String>(),
        );
      }

      // Use batched writes for better performance
      var batch = _db.batch();
      var batchCount = 0;
      final batches = <WriteBatch>[];

      // Extract test data once
      final duration = testData['duration'] ?? 60;
      final totalQuestions =
          (testData['questions'] as List?)?.length ??
          testData['questionCount'] ??
          testData['totalQuestions'] ??
          0;
      final startDate = testData['startDate'] ?? testData['date'];
      final startTime = testData['startTime'] ?? '';

      String dateStr = '';
      if (startDate is Timestamp) {
        final dt = startDate.toDate();
        dateStr =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } else if (startDate is String) {
        dateStr = startDate;
      }

      for (final student in studentAssignments) {
        // Skip if already assigned
        if (existingStudentIds.contains(student['studentId'])) {
          continue;
        }

        // Create user document if needed
        if (usersToCreate.containsKey(student['studentId'])) {
          final userRef = _db.collection('users').doc(student['studentId']);
          batch.set(
            userRef,
            usersToCreate[student['studentId']]!,
            SetOptions(merge: true),
          );
          batchCount++;
        }

        // Create assignment document
        final assignmentDoc = {
          'testId': testId,
          'studentId': student['studentId']!,
          'studentEmail': student['studentEmail']!,
          'studentName': student['studentName']!,
          'testTitle': testTitle,
          'subject': subject,
          'className': targetClassName,
          'section': targetSection,
          'teacherId': teacherAuthUid,
          'teacherName': teacherName,
          'teacherEmail': teacherData['email'] ?? '',
          'status': 'assigned',
          'assignedAt': FieldValue.serverTimestamp(),
          'startedAt': null,
          'submittedAt': null,
          'score': 0,
          'totalMarks': testData['totalMarks'] ?? 0,
          'totalQuestions': totalQuestions,
          'totalPoints': 0,
          'correctAnswers': 0,
          'earnedPoints': 0,
          'duration': duration,
          'date': dateStr,
          'startTime': startTime,
          'timeTaken': 0,
          'schoolCode': schoolCode,
          'answers': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'questionOrder': totalQuestions > 0
              ? (List<int>.generate(totalQuestions, (i) => i)..shuffle())
              : [],
        };

        final assignmentRef = _db.collection('testResults').doc();
        batch.set(assignmentRef, assignmentDoc);
        batchCount++;

        // Update user counters - use set with merge to avoid errors if doc doesn't exist
        final userDocRef = _db.collection('users').doc(student['studentId']);
        batch.set(userDocRef, {
          'pendingTests': FieldValue.increment(1),
          'newNotifications': FieldValue.increment(1),
        }, SetOptions(merge: true));
        batchCount++;

        // Firestore batch limit is 500 operations
        if (batchCount >= 450) {
          batches.add(batch);
          batch = _db.batch(); // Create new batch
          batchCount = 0;
        }
      }

      // Add final batch if it has operations
      if (batchCount > 0) {
        batches.add(batch);
      }

      // Commit all batches
      await Future.wait(batches.map((b) => b.commit()));
    } catch (e) {
      rethrow;
    }
  }

  // Create test and automatically assign to class
  Future<String> createTestAndAssignToClass(TestModel test) async {
    final testId = await createTest(test);

    // If className is specified and test is published, assign to class
    if (test.className != null &&
        test.className!.isNotEmpty &&
        test.status == TestStatus.published) {
      await assignTestToClass(testId, test.teacherId);
    } else {}

    return testId;
  }

  // Create scheduled test and store in scheduledTests collection
  Future<String> createScheduledTest(
    TestModel test, {
    required DateTime scheduledDate,
    required TimeOfDay scheduledTime,
  }) async {
    // Create test document first
    final testId = await createTest(test);

    // Format date as "YYYY-MM-DD" and time as "HH:MM" for storage
    final dateString =
        '${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}';
    final timeString =
        '${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}';

    // Compute start/end DateTimes for reliable comparisons
    final startDateTime = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      scheduledTime.hour,
      scheduledTime.minute,
    );
    final endDateTime = startDateTime.add(Duration(minutes: test.duration));

    // Resolve teacher email and schoolCode for richer scheduled doc parity with web
    String teacherEmail = '';
    String schoolCode = '';
    try {
      // Try direct teacher doc by UID
      final teacherDoc = await _db
          .collection('teachers')
          .doc(test.teacherId)
          .get();
      if (teacherDoc.exists) {
        final data = teacherDoc.data() ?? {};
        teacherEmail = (data['email'] as String?)?.trim() ?? '';
        schoolCode = (data['schoolCode'] as String?)?.trim() ?? '';
      } else {
        // Fallback to query by current auth email
        final current = FirebaseAuth.instance.currentUser;
        final email = current?.email;
        if (email != null && email.isNotEmpty) {
          final q = await _db
              .collection('teachers')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            final data = q.docs.first.data();
            teacherEmail = (data['email'] as String?)?.trim() ?? '';
            schoolCode = (data['schoolCode'] as String?)?.trim() ?? '';
          }
        }
      }
    } catch (_) {
      // non-fatal
    }

    // Transform questions into the shape used by the web panel
    final List<Map<String, dynamic>> questions = [];
    for (var i = 0; i < test.questions.length; i++) {
      final q = test.questions[i];
      String type;
      switch (q.type) {
        case QuestionType.multipleChoice:
          type = 'mcq';
          break;
        case QuestionType.trueFalse:
          type = 'tf';
          break;
        case QuestionType.shortAnswer:
          type = 'short';
          break;
        case QuestionType.essay:
          type = 'essay';
          break;
      }
      questions.add({
        'id': (q.id.isNotEmpty ? q.id : 'q_${i + 1}'),
        'type': type,
        'questionText': q.question,
        if (q.options != null) 'options': q.options,
        'correctAnswer': q.correctAnswer,
        'marks': q.points,
      });
    }

    // Store in scheduledTests collection (aligning fields with web-created documents)
    final scheduleDocRef = _db.collection('scheduledTests').doc(testId);
    await scheduleDocRef.set({
      'id': testId,
      'title': test.title,
      'description': test.description,
      'teacherId': test.teacherId,
      'teacherName': test.teacherName,
      'teacherEmail': teacherEmail,
      'schoolCode': schoolCode,
      'className': test.className ?? '',
      'section': test.section ?? '',
      'subject': test.subject,
      // Aggregate fields
      'questionCount': test.questions.length,
      'duration': test.duration,
      'totalMarks': test.totalPoints,
      // Schedule window
      'date': dateString,
      'startTime': timeString,
      'startDate': Timestamp.fromDate(startDateTime),
      'endDate': Timestamp.fromDate(endDateTime),
      // Status & automation flags
      'status': 'scheduled',
      'autoPublished': true, // allow auto-publish job to pick it up
      'resultsPublished': false, // not yet
      // Content
      'questions': questions,
      // Notifications & audit
      'notifyStudents': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': test.teacherId,
    });

    // Assign to students in the target class (just like published tests)
    // This ensures students can see the test in their dashboard
    if (test.className != null && test.className!.isNotEmpty) {
      await assignTestToClass(testId, test.teacherId);
    }

    return testId;
  }

  Future<TestModel?> getTest(String testId) async {
    // Try scheduledTests first (new location)
    final doc = await _db.collection('scheduledTests').doc(testId).get();
    if (doc.exists) {
      return TestModel.fromScheduledTest(doc.id, doc.data()!);
    }
    return null;
  }

  Future<void> updateTest(String testId, Map<String, dynamic> data) async {
    await _db.collection('scheduledTests').doc(testId).update(data);
  }

  Future<void> deleteTest(String testId) async {
    await _db.collection('scheduledTests').doc(testId).delete();
  }

  /// Safer delete: remove the test and clean up related data
  /// - Deletes all testResults for this test (both assignments and completions)
  /// - Decrements pendingTests for assigned students (best-effort)
  /// - Deletes the test document from scheduledTests
  Future<void> deleteTestCascade(String testId) async {
    try {
      final testRef = _db.collection('scheduledTests').doc(testId);

      // Find all assignments for this test from testResults collection
      final assignmentsQ = await _db
          .collection('testResults')
          .where('testId', isEqualTo: testId)
          .get();

      // Extract student IDs who have assignments (status='assigned')
      final assignedStudentIds = assignmentsQ.docs
          .where((doc) {
            final status = (doc.data()['status'] as String?) ?? '';
            return status == 'assigned';
          })
          .map((doc) => doc.data()['studentId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      // Delete all testResults documents (assignments and completions) in batches
      for (final chunk in _chunk(assignmentsQ.docs, 400)) {
        final batch = _db.batch();
        for (final d in chunk) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }

      // Best-effort: decrement pendingTests for students who had pending assignments
      if (assignedStudentIds.isNotEmpty) {
        for (final chunk in _chunk<String>(assignedStudentIds, 400)) {
          final batch = _db.batch();
          for (final sid in chunk) {
            batch.update(_db.collection('users').doc(sid), {
              'pendingTests': FieldValue.increment(-1),
            });
          }
          try {
            await batch.commit();
          } catch (_) {}
        }
      }

      // Finally delete the test from scheduledTests
      await testRef.delete();
    } catch (e) {
      // Fallback to simple delete if anything goes wrong
      try {
        await _db.collection('scheduledTests').doc(testId).delete();
      } catch (_) {}
      rethrow;
    }
  }

  // Small helper to chunk lists for batched writes
  Iterable<List<T>> _chunk<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, i + size > list.length ? list.length : i + size);
    }
  }

  /// Utility: Count students for a teacher email whose user docs have a populated uid
  /// Returns a summary map with totals and prints detailed logs.
  Future<Map<String, dynamic>> countStudentsUidByTeacherEmail(
    String teacherEmail,
  ) async {
    try {
      // 1) Load teacher by email
      final teacherQuery = await _db
          .collection('teachers')
          .where('email', isEqualTo: teacherEmail)
          .limit(1)
          .get();

      if (teacherQuery.docs.isEmpty) {
        return {'success': false, 'error': 'Teacher not found'};
      }

      final teacherData = teacherQuery.docs.first.data();
      final schoolCode = (teacherData['schoolCode'] as String?)?.trim() ?? '';
      final classesHandled = teacherData['classesHandled'] as List<dynamic>?;
      final sectionsRaw = teacherData['sections'] ?? teacherData['section'];
      final classAssignments =
          teacherData['classAssignments'] as List<dynamic>?;

      if (schoolCode.isEmpty) {}

      // 2) Build list of (className, section) pairs to query students
      List<Map<String, String>> targets = [];

      List<String> normalizeSections(dynamic sections) {
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

      if (classesHandled != null && classesHandled.isNotEmpty) {
        final sections = normalizeSections(sectionsRaw);
        for (final c in classesHandled) {
          final className = c.toString(); // e.g., "Grade 10"
          for (final s in sections) {
            targets.add({'className': className, 'section': s});
          }
        }
      } else if (classAssignments != null && classAssignments.isNotEmpty) {
        // Parse strings like "Grade 10: A, Science"
        for (final assignment in classAssignments) {
          final str = assignment.toString();
          final parts = str.split(':');
          if (parts.length < 2) continue;
          final gradePart = parts[0].trim(); // "Grade 10"
          final right = parts[1];
          final commaParts = right.split(',');
          if (commaParts.isEmpty) continue;
          final section = commaParts[0].trim(); // "A"
          final className = gradePart; // keep full "Grade X" for query
          targets.add({'className': className, 'section': section});
        }
      }

      if (targets.isEmpty) {
        return {
          'success': true,
          'schoolCode': schoolCode,
          'totalStudents': 0,
          'withUid': 0,
          'withoutUid': 0,
          'missingUsers': 0,
        };
      }

      // 3) Query students for all targets and collect emails
      final emails = <String>{};
      int totalStudentDocs = 0;
      for (final t in targets) {
        final className = t['className']!;
        final section = t['section']!;
        var q = _db
            .collection('students')
            .where('schoolCode', isEqualTo: schoolCode)
            .where('className', isEqualTo: className)
            .where('section', isEqualTo: section);
        final snap = await q.get();
        totalStudentDocs += snap.docs.length;
        for (final doc in snap.docs) {
          final data = doc.data();
          final email =
              (data['email'] as String?) ?? data['studentEmail'] as String?;
          if (email != null && email.isNotEmpty) emails.add(email.trim());
        }
      }

      // 4) Check users collection for uid presence
      int withUid = 0;
      int withoutUid = 0;
      int missingUsers = 0;

      for (final email in emails) {
        final uq = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (uq.docs.isEmpty) {
          missingUsers++;
          // ignore: avoid_print
          continue;
        }
        final u = uq.docs.first.data();
        final uid = (u['uid'] as String?)?.trim() ?? '';
        if (uid.isNotEmpty) {
          withUid++;
        } else {
          withoutUid++;
        }
      }

      return {
        'success': true,
        'teacherEmail': teacherEmail,
        'schoolCode': schoolCode,
        'targets': targets.length,
        'totalStudents': totalStudentDocs,
        'uniqueEmails': emails.length,
        'withUid': withUid,
        'withoutUid': withoutUid,
        'missingUsers': missingUsers,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Stream<List<TestModel>> getTestsByTeacher(String teacherId) {
    // Query scheduledTests collection - sort in memory to avoid index requirement
    return _db
        .collection('scheduledTests')
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
          // Parse all tests
          final tests = snapshot.docs
              .map((doc) => TestModel.fromScheduledTest(doc.id, doc.data()))
              .toList();

          // Sort by createdAt in memory (newest first)
          tests.sort((a, b) {
            return b.createdAt.compareTo(a.createdAt); // Descending order
          });

          return tests;
        });
  }

  Stream<List<TestModel>> getAvailableTestsForStudent(
    String studentId, {
    String? studentEmail,
  }) async* {
    // Query testResults collection for assignments to this student
    // Only fetch tests that are NOT completed/submitted (pending tests only)
    var assignmentsQuery = _db
        .collection('testResults')
        .where('studentId', isEqualTo: studentId)
        .where('status', whereIn: ['assigned', 'started'])
        .snapshots();

    await for (var assignmentsSnapshot in assignmentsQuery) {
      // Extract unique test IDs from assignments
      final testIds = assignmentsSnapshot.docs
          .map((doc) => doc.data()['testId'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      if (testIds.isEmpty) {
        yield [];
        continue;
      }

      // Fetch test details from scheduledTests collection
      // Firestore whereIn has a limit of 10, so we need to batch if more than 10
      final List<TestModel> tests = [];

      for (var i = 0; i < testIds.length; i += 10) {
        final batch = testIds.skip(i).take(10).toList();
        final testsSnapshot = await _db
            .collection('scheduledTests')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (var doc in testsSnapshot.docs) {
          try {
            final test = TestModel.fromScheduledTest(doc.id, doc.data());
            // Only include published tests
            if (test.status == TestStatus.published) {
              tests.add(test);
            }
          } catch (e) {}
        }
      }

      yield tests;
    }
  }

  // Test Results Operations (for students)
  Stream<List<TestResultModel>> getTestResultsByStudent(String studentId) {
    return _db
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

  // Reward Operations
  Future<String> createReward(RewardModel reward) async {
    final docRef = await _db.collection('rewards').add(reward.toJson());
    return docRef.id;
  }

  Future<void> updateReward(String rewardId, Map<String, dynamic> data) async {
    await _db.collection('rewards').doc(rewardId).update(data);
  }

  Stream<List<RewardModel>> getRewardsByStudent(String studentId) {
    // Same approach: avoid composite index requirement by sorting client-side.
    return _db
        .collection('rewards')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final rewards = snapshot.docs
              .map((doc) => RewardModel.fromJson(doc.data()))
              .toList();
          rewards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return rewards;
        });
  }

  // Get reward catalog for student - only shows parent rewards with pending status
  Stream<List<RewardModel>> getRewardCatalogForStudent(String studentId) {
    return _db
        .collection('rewards')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final rewards = snapshot.docs
              .map((doc) => RewardModel.fromJson(doc.data()))
              .where(
                (reward) =>
                    reward.senderRole == 'parent' &&
                    reward.status == RewardStatus.pending,
              )
              .toList();
          rewards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return rewards;
        });
  }

  // Performance Operations
  Future<void> updatePerformance(PerformanceModel performance) async {
    await _db
        .collection('performances')
        .doc(performance.studentId)
        .set(performance.toJson());
  }

  Future<PerformanceModel?> getPerformance(String studentId) async {
    final doc = await _db.collection('performances').doc(studentId).get();
    if (doc.exists) {
      return PerformanceModel.fromJson(doc.data()!);
    }
    return null;
  }

  // ------------------------------------------------------------
  // (Removed legacy migration helper – website now writes correct auth UIDs directly.)

  Stream<PerformanceModel?> getPerformanceStream(String studentId) {
    // Fetch real-time data from testResults collection
    return _db
        .collection('testResults')
        .where('studentId', isEqualTo: studentId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return null;
          }

          // Build performance model from test results
          final List<TestSubmission> submissions = [];
          int totalScore = 0;
          int totalTests = 0;
          // int totalPoints = 0; // not used here

          for (final doc in snapshot.docs) {
            final data = doc.data();

            // Only process documents with required fields
            if (data['testId'] == null || data['completedAt'] == null) {
              continue;
            }

            final score = (data['score'] ?? 0).toDouble();
            final correctAnswers = (data['correctAnswers'] ?? 0) as int;
            final totalQuestions = (data['totalQuestions'] ?? 1) as int;
            final percentage = totalQuestions > 0
                ? (correctAnswers / totalQuestions) * 100
                : 0.0;

            // Calculate points (if not stored, estimate from score)
            final points =
                (data['totalPoints'] ?? (percentage * 1.5).toInt()) as int;

            submissions.add(
              TestSubmission(
                testId: data['testId'] ?? '',
                testTitle: data['testTitle'] ?? 'Test',
                score: score.toInt(),
                totalPoints: points,
                percentage: percentage,
                submittedAt:
                    (data['completedAt'] as Timestamp?)?.toDate() ??
                    (data['submittedAt'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              ),
            );

            totalScore += percentage.toInt();
            totalTests++;
            // totalPoints += points; // not used
          }

          final averageScore = totalTests > 0 ? totalScore / totalTests : 0.0;

          return PerformanceModel(
            id: studentId,
            studentId: studentId,
            studentName: snapshot.docs.first.data()['studentName'] ?? '',
            instituteId: snapshot.docs.first.data()['schoolCode'] ?? '',
            submissions: submissions,
            averageScore: averageScore,
            totalTestsTaken: totalTests,
            totalRewardsReceived: 0, // Can be fetched separately if needed
            lastUpdated: DateTime.now(),
          );
        });
  }

  // Institute Analytics
  Stream<List<PerformanceModel>> getInstitutePerformances(String instituteId) {
    return _db
        .collection('performances')
        .where('instituteId', isEqualTo: instituteId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PerformanceModel.fromJson(doc.data()))
              .toList(),
        );
  }

  // UTILITY: Batch sync UIDs for all students in a specific class
  // This is a one-time fix for students whose uid field is empty
  Future<Map<String, dynamic>> batchSyncStudentUIDs({
    required String schoolCode,
    String? className,
    String? section,
  }) async {
    // if (className != null) {}
    // if (section != null) {}

    try {
      // Query students
      var query = _db
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode);

      if (className != null && className.isNotEmpty) {
        query = query.where('className', isEqualTo: className);
      }
      if (section != null && section.isNotEmpty) {
        query = query.where('section', isEqualTo: section);
      }

      final studentsSnapshot = await query.get();

      int updatedCount = 0;
      int alreadyValidCount = 0;
      int errorCount = 0;
      final List<String> errors = [];

      for (final studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final email = studentData['email'] as String?;

        if (email == null || email.isEmpty) {
          errorCount++;
          continue;
        }

        // Find user document by email
        final userQuery = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (userQuery.docs.isEmpty) {
          errorCount++;
          errors.add('No user doc for $email');
          continue;
        }

        final userDoc = userQuery.docs.first;
        final userData = userDoc.data();
        final currentUid = (userData['uid'] as String?)?.trim();

        // Check if uid is already valid (non-empty)
        if (currentUid != null && currentUid.isNotEmpty) {
          alreadyValidCount++;
          continue;
        }

        // Try to get Auth UID by attempting to sign in
        // Since we can't do that here, we'll use the user document ID as UID
        // This will be corrected when the student logs in

        await _db.collection('users').doc(userDoc.id).update({
          'uid': userDoc.id,
        });

        updatedCount++;
      }

      return {
        'success': true,
        'totalStudents': studentsSnapshot.docs.length,
        'updated': updatedCount,
        'alreadyValid': alreadyValidCount,
        'errors': errorCount,
        'errorDetails': errors,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Submit Test Result
  Future<void> submitTestResult(
    TestResultModel result, {
    required DateTime testEndDate,
  }) async {
    String? schoolCode; // Declare at method level for use in violations

    try {
      // Check if test has ended to determine if we should update points/leaderboard
      final now = DateTime.now();
      bool testHasEnded = now.isAfter(testEndDate);

      // Fallback: derive end time from scheduledTests if not yet ended
      if (!testHasEnded) {
        try {
          final sched = await _db
              .collection('scheduledTests')
              .doc(result.testId)
              .get();
          if (sched.exists) {
            final sdata = sched.data() ?? {};
            DateTime? fallbackEnd;
            // Prefer explicit endDate if present
            final endTs = sdata['endDate'];
            if (endTs is Timestamp) {
              fallbackEnd = endTs.toDate();
            } else {
              // Compute from date + startTime + duration
              final dateStr = sdata['date'] as String?;
              final timeStr = sdata['startTime'] as String?;
              final durationMin = (sdata['duration'] as num?)?.toInt() ?? 0;
              if (dateStr != null && timeStr != null) {
                try {
                  final partsD = dateStr.split('-'); // yyyy-mm-dd
                  final partsT = timeStr.split(':'); // HH:MM
                  if (partsD.length == 3 && partsT.length >= 2) {
                    final y = int.tryParse(partsD[0]) ?? now.year;
                    final m = int.tryParse(partsD[1]) ?? now.month;
                    final d = int.tryParse(partsD[2]) ?? now.day;
                    final hh = int.tryParse(partsT[0]) ?? 0;
                    final mm = int.tryParse(partsT[1]) ?? 0;
                    final start = DateTime(y, m, d, hh, mm);
                    fallbackEnd = start.add(Duration(minutes: durationMin));
                  }
                } catch (_) {}
              }
            }

            if (fallbackEnd != null && now.isAfter(fallbackEnd)) {
              testHasEnded = true;
            }
          }
        } catch (_) {}
      }

      // Add schoolCode if we can infer it from the student's profile
      try {
        final stSnap = await _db
            .collection('students')
            .doc(result.studentId)
            .get();
        if (stSnap.exists) {
          final sc = (stSnap.data()?['schoolCode'] as String?)?.trim();
          if (sc != null && sc.isNotEmpty) {
            schoolCode = sc; // Save for use in violations
          }
        }
      } catch (_) {}

      if (testHasEnded) {
      } else {}

      // NEW LOGIC: Raw marks gained from test result's totalPoints field
      // This represents the actual sum of points for correct answers
      // Reward points should equal marks gained (no multipliers / percentage weighting)
      final earnedPointsCandidate =
          result.totalPoints ??
          result
              .correctAnswers; // use totalPoints if available, fallback to correctAnswers

      // Update the assignment document directly (no separate result document)
      String? assignmentId;
      try {
        final assignmentQuery = await _db
            .collection('testResults')
            .where('studentId', isEqualTo: result.studentId)
            .where('testId', isEqualTo: result.testId)
            .where('status', isEqualTo: 'assigned')
            .limit(1)
            .get();

        if (assignmentQuery.docs.isNotEmpty) {
          final assignmentDoc = assignmentQuery.docs.first;
          assignmentId = assignmentDoc.id; // Save for violations logging

          // Build update data with all result fields
          final updateData = {
            'status': 'completed',
            'submittedAt': FieldValue.serverTimestamp(),
            'score': result.score,
            'correctAnswers': result.correctAnswers,
            'totalQuestions': result.totalQuestions,
            'answers': result.answers,
            'completedAt': Timestamp.fromDate(result.completedAt),
            'timeTaken': result.timeTaken,
            'wasProctored': result.wasProctored,
            'tabSwitchCount': result.tabSwitchCount,
            'violationDetected': result.violationDetected,
            'pointsAwarded': testHasEnded,
            // Persist per-test points for UI
            'earnedPoints': testHasEnded
                ? earnedPointsCandidate
                : 0, // raw marks gained
            'totalPoints': testHasEnded
                ? earnedPointsCandidate
                : 0, // mirror for backward compatibility
            if (result.violationReason != null)
              'violationReason': result.violationReason,
            'schoolCode': ?schoolCode,
          };

          await assignmentDoc.reference.update(updateData);
        } else {}
      } catch (e) {}

      // Update student counters and points ONLY if test has ended
      if (testHasEnded) {
        // Use previously computed points
        final earnedPoints = earnedPointsCandidate; // raw marks

        // Update student counters (users collection preferred, fallback to students)
        bool countersUpdated = false;
        try {
          final userByIdRef = _db.collection('users').doc(result.studentId);
          final userByIdSnap = await userByIdRef.get();
          if (userByIdSnap.exists) {
            await userByIdRef.update({
              'completedTests': FieldValue.increment(1),
              'pendingTests': FieldValue.increment(-1),
              'totalScore': FieldValue.increment(result.score.toInt()),
              // Use calculated points, not raw score
              'totalPoints': FieldValue.increment(earnedPoints), // raw marks
              'rewardPoints': FieldValue.increment(earnedPoints), // raw marks
            });
            countersUpdated = true;
          } else {
            final uq = await _db
                .collection('users')
                .where('uid', isEqualTo: result.studentId)
                .limit(1)
                .get();
            if (uq.docs.isNotEmpty) {
              await uq.docs.first.reference.update({
                'completedTests': FieldValue.increment(1),
                'pendingTests': FieldValue.increment(-1),
                'totalScore': FieldValue.increment(result.score.toInt()),
                // Use calculated points, not raw score
                'totalPoints': FieldValue.increment(earnedPoints),
                'rewardPoints': FieldValue.increment(earnedPoints),
              });
              countersUpdated = true;
            }
          }
        } catch (e) {}

        if (!countersUpdated) {
          // Fallback: update students collection counters if present
          try {
            final sref = _db.collection('students').doc(result.studentId);
            final ssnap = await sref.get();
            if (ssnap.exists) {
              await sref.update({
                'completedTests': FieldValue.increment(1),
                'pendingTests': FieldValue.increment(-1),
                'totalScore': FieldValue.increment(result.score.toInt()),
                'totalPoints': FieldValue.increment(earnedPoints),
                'rewardPoints': FieldValue.increment(earnedPoints),
              });
              countersUpdated = true;
            }
          } catch (e) {}
        }

        if (countersUpdated) {
        } else {}

        // Save points record to student_rewards collection for history
        try {
          // Just save to student_rewards for record keeping (points already added above)
          final doc = _db.collection('student_rewards').doc();
          await doc.set(
            RewardPointsModel(
              id: doc.id,
              studentId: result.studentId,
              testId: result.testId,
              marks: (result.totalPoints ?? result.correctAnswers)
                  .toDouble(), // actual marks earned
              totalMarks: result.totalQuestions.toDouble(),
              pointsEarned: earnedPoints, // equals raw marks
              timestamp: DateTime.now(),
            ).toJson(),
          );
        } catch (e) {}
      } else {
        // Test hasn't ended yet - mark for later processing
      }

      // NOTE: We no longer update the "tests" collection as it's being phased out
      // All test information is now stored in scheduledTests and testResults

      // If violation detected, log it separately
      if (result.violationDetected && assignmentId != null) {
        await _db.collection('violations').add({
          'studentId': result.studentId,
          'studentName': result.studentName,
          'studentEmail': result.studentEmail,
          'testId': result.testId,
          'testTitle': result.testTitle,
          'resultId': assignmentId, // Use assignment document ID
          'violationType': 'tab_switch',
          'tabSwitchCount': result.tabSwitchCount,
          'reason': result.violationReason,
          'timestamp': FieldValue.serverTimestamp(),
          'score': result.score,
          if (schoolCode != null && schoolCode.isNotEmpty)
            'schoolCode': schoolCode,
        });
      }
    } catch (e) {
      rethrow;
    }
  }

  // =========================
  // Rewards & Products (Student)
  // =========================

  /// Calculate points based on percentage achieved:
  /// - >= 90%: percentage × 1.5
  /// - 35% to 89%: percentage × 1.0
  /// - < 35%: 0 points (below pass threshold)
  int calculatePoints({
    required double total,
    required double obtained,
    int basePoints = 100, // Not used in new logic, kept for compatibility
  }) {
    if (total <= 0) return 0;

    // Calculate percentage (0-100)
    final percentage = (obtained / total) * 100.0;

    // Apply rules based on percentage
    double points = 0.0;
    if (percentage >= 90) {
      // High achievers: percentage × 1.5
      points = percentage * 1.5;
    } else if (percentage >= 35) {
      // Pass mark and above: percentage × 1.0
      points = percentage * 1.0;
    } else {
      // Below 35%: no points (fail)
      points = 0.0;
    }

    return points.round();
  }

  /// Save an entry in student_rewards and increment student's totalPoints
  Future<void> savePointsToFirestore({
    required String studentId,
    required String testId,
    required double marks,
    required double totalMarks,
    required int points,
  }) async {
    final doc = _db.collection('student_rewards').doc();
    final payload = RewardPointsModel(
      id: doc.id,
      studentId: studentId,
      testId: testId,
      marks: marks,
      totalMarks: totalMarks,
      pointsEarned: points,
      timestamp: DateTime.now(),
    ).toJson();

    final batch = _db.batch();
    batch.set(doc, payload);

    // Prefer users collection for points, but also try students if exists
    final userRef = _db.collection('users').doc(studentId);
    // Use set with merge to avoid failures when the user doc doesn't exist yet
    batch.set(userRef, {
      'totalPoints': FieldValue.increment(points),
      'rewardPoints': FieldValue.increment(points),
    }, SetOptions(merge: true));

    // Optional: update students collection if present
    final studentRef = _db.collection('students').doc(studentId);
    try {
      final studentSnap = await studentRef.get();
      if (studentSnap.exists) {
        batch.update(studentRef, {
          'totalPoints': FieldValue.increment(points),
          'rewardPoints': FieldValue.increment(points),
        });
      } else {}
    } catch (_) {
      // ignore if collection not present
    }

    await batch.commit();
  }

  /// Products catalog
  Stream<List<ProductModel>> getProducts({String? category}) {
    Query<Map<String, dynamic>> q = _db.collection('products');
    if (category != null && category.isNotEmpty && category != 'All') {
      q = q.where('category', isEqualTo: category.toLowerCase());
    }
    return q.snapshots().map(
      (snap) => snap.docs
          .map((d) => ProductModel.fromJson(d.data(), id: d.id))
          .toList(),
    );
  }

  /// Create or update a product (admin/seed)
  Future<void> upsertProduct(ProductModel product) async {
    final ref = _db
        .collection('products')
        .doc(product.id.isEmpty ? null : product.id);
    if (ref.id == product.id && product.id.isNotEmpty) {
      await ref.set(product.toJson(), SetOptions(merge: true));
    } else {
      final docRef = _db.collection('products').doc();
      final data = product.toJson();
      data['id'] = docRef.id;
      await docRef.set(data);
    }
  }

  /// Student requests a reward
  Future<String> requestReward({
    required ProductModel product,
    required String studentId,
    required String studentName,
  }) async {
    final reqRef = _db.collection('reward_requests').doc();
    final request = RewardRequestModel(
      id: reqRef.id,
      studentId: studentId,
      studentName: studentName,
      productId: product.id,
      productName: product.name,
      amazonLink: product.amazonLink,
      price: product.price,
      pointsRequired: product.pointsRequired,
      status: RewardRequestStatus.pending,
      requestedOn: DateTime.now(),
    );
    await reqRef.set(request.toJson());
    return reqRef.id;
  }

  Stream<List<RewardRequestModel>> getRewardRequestsForStudent(
    String studentId,
  ) {
    return _db
        .collection('reward_requests')
        .where('studentId', isEqualTo: studentId)
        .orderBy('requestedOn', descending: true)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => RewardRequestModel.fromJson(d.data(), id: d.id))
              .toList(),
        );
  }

  /// Parent approves a reward request: deduct points and write approved_rewards
  Future<void> approveReward({
    required String requestId,
    required String parentId,
  }) async {
    final reqRef = _db.collection('reward_requests').doc(requestId);
    final snap = await reqRef.get();
    if (!snap.exists) throw Exception('Request not found');
    final data = snap.data()!;
    final studentId = data['studentId'] as String;
    final points = (data['pointsRequired'] as num? ?? 0).toInt();

    final batch = _db.batch();
    batch.update(reqRef, {
      'status': 'approved',
      'parentId': parentId,
      'approvedOn': FieldValue.serverTimestamp(),
    });

    // Deduct from users/ and students/ if present
    // Use set(merge: true) so we don't fail if the doc doesn't exist yet
    batch.set(_db.collection('users').doc(studentId), {
      'totalPoints': FieldValue.increment(-points),
      'rewardPoints': FieldValue.increment(-points),
    }, SetOptions(merge: true));
    final studentRef = _db.collection('students').doc(studentId);
    try {
      final st = await studentRef.get();
      if (st.exists) {
        batch.update(studentRef, {
          'totalPoints': FieldValue.increment(-points),
          'rewardPoints': FieldValue.increment(-points),
        });
      }
    } catch (_) {}

    final approvedRef = _db.collection('approved_rewards').doc();
    batch.set(approvedRef, {
      'id': approvedRef.id,
      'requestId': requestId,
      'studentId': studentId,
      'productName': data['productName'],
      'amazonLink': data['amazonLink'],
      'status': 'approved',
      'dateApproved': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Mark order placed for an approved reward (and reflect on request doc)
  Future<void> markOrderPlaced(String requestId) async {
    final reqRef = _db.collection('reward_requests').doc(requestId);
    final approvedQuery = await _db
        .collection('approved_rewards')
        .where('requestId', isEqualTo: requestId)
        .limit(1)
        .get();
    final batch = _db.batch();
    batch.update(reqRef, {'status': 'order_placed'});
    if (approvedQuery.docs.isNotEmpty) {
      batch.update(approvedQuery.docs.first.reference, {
        'status': 'order_placed',
      });
    }
    await batch.commit();
  }

  // =========================
  // Automatic Result Publishing
  // =========================

  /// Auto-publish tests whose endDate has passed.
  /// Criteria:
  /// - endDate <= now
  /// - resultsPublished != true (missing or false)
  /// - status != completed (will be set to completed)
  /// Optionally filter by schoolCode if provided, to reduce query scope.
  /// Returns number of tests updated.
  Future<int> autoPublishExpiredTests({String? schoolCode}) async {
    try {
      final nowTs = Timestamp.fromDate(DateTime.now());

      // Use a single-inequality query (endDate <= now) then filter client-side
      // to avoid composite index requirements and noisy logs.
      final fb = await _db
          .collection('tests')
          .where('endDate', isLessThanOrEqualTo: nowTs)
          .get();

      final docs = fb.docs
          .where((d) => (d.data()['resultsPublished'] != true))
          .where(
            (d) => schoolCode == null || schoolCode.trim().isEmpty
                ? true
                : (d.data()['schoolCode'] == schoolCode.trim()),
          )
          .toList();

      if (docs.isEmpty) return 0;

      int updatedCount = 0;
      for (final chunk in _chunk(docs, 400)) {
        final batch = _db.batch();
        for (final d in chunk) {
          final data = d.data();
          // Mark as completed + results published
          batch.update(d.reference, {
            'status': 'completed',
            'resultsPublished': true,
            'publishedAt': FieldValue.serverTimestamp(),
          });

          // Notify assigned students (best-effort)
          final assigned =
              (data['assignedStudentIds'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const <String>[];
          for (final sid in assigned) {
            final notifRef = _db.collection('notifications').doc();
            batch.set(notifRef, {
              'id': notifRef.id,
              'studentId': sid,
              'title': 'Results Published 🎯',
              'message':
                  'Your results for \'${data['title'] ?? 'Test'}\' are now available!',
              'type': 'test',
              'createdAt': FieldValue.serverTimestamp(),
              'isRead': false,
              'data': {'testId': data['id'], 'subject': data['subject']},
            });

            // Increment in-app badge counters (best-effort) without failing if doc missing
            batch.set(_db.collection('users').doc(sid), {
              'newNotifications': FieldValue.increment(1),
            }, SetOptions(merge: true));
          }
        }
        await batch.commit();
        updatedCount += chunk.length;
      }

      return updatedCount;
    } catch (e) {
      return 0;
    }
  }

  // =========================
  // AI Test Generation Support
  // =========================

  /// Save AI-generated test to scheduledTests collection
  /// Returns the document ID of the created test
  Future<String> saveScheduledTest(Map<String, dynamic> testDoc) async {
    // Generate a new document ID
    final docRef = _db.collection('scheduledTests').doc();

    // Add the ID to the document
    testDoc['id'] = docRef.id;

    // Ensure required fields have defaults
    testDoc['createdAt'] = FieldValue.serverTimestamp();
    testDoc['autoPublished'] ??= false;
    testDoc['resultsPublished'] ??= false;
    testDoc['status'] ??= 'scheduled';

    // Save to Firestore
    await docRef.set(testDoc);

    return docRef.id;
  }

  /// Fetch previous questions for context in AI generation
  /// Returns up to 5 recent questions from the same class/section/subject
  Future<List<Map<String, dynamic>>> fetchPreviousQuestions({
    required String className,
    required String section,
    required String subject,
  }) async {
    try {
      final snapshot = await _db
          .collection('scheduledTests')
          .where('className', isEqualTo: className)
          .where('section', isEqualTo: section)
          .where('subject', isEqualTo: subject)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();

      final previousQuestions = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final questions = data['questions'] as List<dynamic>? ?? [];

        // Extract question text and marks from each test
        for (final q in questions) {
          if (q is Map<String, dynamic>) {
            previousQuestions.add({
              'questionText': q['questionText'] ?? q['question'] ?? '',
              'marks': q['marks'] ?? q['points'] ?? 1,
            });
          }
        }
      }

      return previousQuestions.take(5).toList(); // Limit to 5 questions
    } catch (e) {
      return []; // Return empty list on error, don't fail the generation
    }
  }

  /// Process pending test results and award points for tests that have ended
  /// Also awards achievement badges post end-time to cover early submissions
  /// This should be called when the app starts or when viewing dashboard
  Future<void> processEndedTests() async {
    try {
      final now = DateTime.now();

      // Find completed results that have not yet awarded points
      final pendingResultsSnap = await _db
          .collection('testResults')
          .where('status', isEqualTo: 'completed')
          .where('pointsAwarded', isEqualTo: false)
          .limit(200)
          .get();

      if (pendingResultsSnap.docs.isEmpty) {
        return;
      }

      // Collect unique testIds from pending results
      final testIds = pendingResultsSnap.docs
          .map((d) => (d.data()['testId'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      // Helper: check if a test has ended by reading scheduledTests
      Future<Map<String, bool>> loadEndedStatus(List<String> ids) async {
        final result = <String, bool>{};
        for (var i = 0; i < ids.length; i += 10) {
          final batch = ids.skip(i).take(10).toList();
          final schedSnap = await _db
              .collection('scheduledTests')
              .where(FieldPath.documentId, whereIn: batch)
              .get();
          for (final doc in schedSnap.docs) {
            final data = doc.data();
            bool ended = false;
            final endTs = data['endDate'];
            if (endTs is Timestamp) {
              ended = now.isAfter(endTs.toDate());
            } else {
              // Compute from date + startTime + duration
              final dateStr = data['date'] as String?;
              final timeStr = data['startTime'] as String?;
              final durationMin = (data['duration'] as num?)?.toInt() ?? 0;
              if (dateStr != null && timeStr != null) {
                try {
                  final partsD = dateStr.split('-');
                  final partsT = timeStr.split(':');
                  if (partsD.length == 3 && partsT.length >= 2) {
                    final y = int.tryParse(partsD[0]) ?? now.year;
                    final m = int.tryParse(partsD[1]) ?? now.month;
                    final d = int.tryParse(partsD[2]) ?? now.day;
                    final hh = int.tryParse(partsT[0]) ?? 0;
                    final mm = int.tryParse(partsT[1]) ?? 0;
                    final start = DateTime(y, m, d, hh, mm);
                    final end = start.add(Duration(minutes: durationMin));
                    ended = now.isAfter(end);
                  }
                } catch (_) {}
              }
            }
            result[doc.id] = ended;

            // Best-effort: backfill endDate for future efficiency
            if (ended && data['endDate'] == null) {
              try {
                DateTime? computedEnd;
                final dateStr = data['date'] as String?;
                final timeStr = data['startTime'] as String?;
                final durationMin = (data['duration'] as num?)?.toInt() ?? 0;
                if (dateStr != null && timeStr != null) {
                  final partsD = dateStr.split('-');
                  final partsT = timeStr.split(':');
                  if (partsD.length == 3 && partsT.length >= 2) {
                    final y = int.tryParse(partsD[0]) ?? now.year;
                    final m = int.tryParse(partsD[1]) ?? now.month;
                    final d = int.tryParse(partsD[2]) ?? now.day;
                    final hh = int.tryParse(partsT[0]) ?? 0;
                    final mm = int.tryParse(partsT[1]) ?? 0;
                    final start = DateTime(y, m, d, hh, mm);
                    computedEnd = start.add(Duration(minutes: durationMin));
                  }
                }
                if (computedEnd != null) {
                  await doc.reference.update({
                    'endDate': Timestamp.fromDate(computedEnd),
                  });
                }
              } catch (_) {}
            }
          }
        }
        return result;
      }

      final endedMap = await loadEndedStatus(testIds);
      final resultsToProcess = pendingResultsSnap.docs.where((d) {
        final tid = (d.data()['testId'] as String?) ?? '';
        return endedMap[tid] == true;
      }).toList();

      // Track processing
      final processedTestIds = <String>{};

      // Group pending results by student to ensure correct milestone ordering
      final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      byStudent = {};
      for (final doc in resultsToProcess) {
        final sid = (doc.data()['studentId'] as String?) ?? '';
        if (sid.isEmpty) continue;
        byStudent.putIfAbsent(sid, () => []).add(doc);
      }

      for (final entry in byStudent.entries) {
        final studentId = entry.key;
        final docs = entry.value;

        // Sort this student's pending results by completion time ascending
        docs.sort((a, b) {
          DateTime aTime =
              (a.data()['completedAt'] as Timestamp?)?.toDate() ??
              (a.data()['submittedAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          DateTime bTime =
              (b.data()['completedAt'] as Timestamp?)?.toDate() ??
              (b.data()['submittedAt'] as Timestamp?)?.toDate() ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return aTime.compareTo(bTime);
        });

        // Baseline: number of already-completed results for this student
        // minus number of pending being processed now, so milestones are exact
        int baselineCompleted = 0;
        try {
          final completedQ = await _db
              .collection('testResults')
              .where('studentId', isEqualTo: studentId)
              .where('status', isEqualTo: 'completed')
              .get();
          baselineCompleted = completedQ.docs.length - docs.length;
          if (baselineCompleted < 0) baselineCompleted = 0;
        } catch (_) {}

        // Seed previous score from the latest already-processed test
        int? prevPercent;
        try {
          final prevSnap = await _db
              .collection('testResults')
              .where('studentId', isEqualTo: studentId)
              .where('status', isEqualTo: 'completed')
              .where('pointsAwarded', isEqualTo: true)
              .orderBy('completedAt', descending: true)
              .limit(1)
              .get();
          if (prevSnap.docs.isNotEmpty) {
            final d = prevSnap.docs.first.data();
            final ca = (d['correctAnswers'] ?? 0) as int;
            final tq = (d['totalQuestions'] ?? 0) as int;
            if (tq > 0) {
              prevPercent = ((ca / tq) * 100).round();
            }
          }
        } catch (_) {}

        final rules = BadgeRules(BadgeService());

        for (var i = 0; i < docs.length; i++) {
          final resultDoc = docs[i];
          final data = resultDoc.data();
          final testId = data['testId'] as String?;
          final correctAnswers = (data['correctAnswers'] ?? 0) as int;
          final totalQuestions = (data['totalQuestions'] ?? 0) as int;
          final pointsAwarded = data['pointsAwarded'] as bool? ?? false;

          if (testId == null || pointsAwarded) {
            continue;
          }

          try {
            // Calculate and award points
            final earnedPoints = calculatePoints(
              total: totalQuestions.toDouble(),
              obtained: correctAnswers.toDouble(),
              basePoints: 100,
            );

            // Save to student_rewards for record keeping
            final doc = _db.collection('student_rewards').doc();
            await doc.set(
              RewardPointsModel(
                id: doc.id,
                studentId: studentId,
                testId: testId,
                marks: correctAnswers.toDouble(),
                totalMarks: totalQuestions.toDouble(),
                pointsEarned: earnedPoints,
                timestamp: DateTime.now(),
              ).toJson(),
            );

            // Add points to user
            final userRef = _db.collection('users').doc(studentId);
            final userSnap = await userRef.get();
            if (userSnap.exists) {
              await userRef.update({
                'totalPoints': FieldValue.increment(earnedPoints),
                'rewardPoints': FieldValue.increment(earnedPoints),
              });
            }

            // Mark this result as processed with points persisted
            await resultDoc.reference.update({
              'pointsAwarded': true,
              'earnedPoints': earnedPoints,
              'totalPoints': earnedPoints,
              'pointsAwardedAt': FieldValue.serverTimestamp(),
            });

            // Compute badge inputs
            final scorePercent = totalQuestions > 0
                ? ((correctAnswers / totalQuestions) * 100).round()
                : 0;
            final testsCompleted = baselineCompleted + i + 1; // include current

            // Award badges safely (service prevents duplicates)
            try {
              await rules.onTestCompleted(
                studentId: studentId,
                testId: testId,
                scorePercent: scorePercent,
                testsCompleted: testsCompleted,
                previousScorePercent: prevPercent,
              );
            } catch (e) {}

            // Update prev for next iteration
            prevPercent = scorePercent;

            processedTestIds.add(testId);
          } catch (e) {}
        }
      }

      // Best-effort: mark scheduled tests as resultsPublished if ended
      if (processedTestIds.isNotEmpty) {
        try {
          final idsToPublish = processedTestIds.toList();
          for (var i = 0; i < idsToPublish.length; i += 10) {
            final batchIds = idsToPublish.skip(i).take(10).toList();
            final schedSnap = await _db
                .collection('scheduledTests')
                .where(FieldPath.documentId, whereIn: batchIds)
                .get();
            final batch = _db.batch();
            for (final d in schedSnap.docs) {
              final currentStatus =
                  d.data()['resultsPublished'] as bool? ?? false;
              if (!currentStatus) {
                batch.update(d.reference, {
                  'status': 'completed',
                  'resultsPublished': true,
                  'publishedAt': FieldValue.serverTimestamp(),
                });
              }
            }
            await batch.commit();
          }
        } catch (e) {}
      }
    } catch (e) {}
  }

  // (Sync utilities removed – website now writes correct data directly.)
}
