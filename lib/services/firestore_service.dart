import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/test_model.dart';
import '../models/reward_model.dart';
import '../models/performance_model.dart';
import '../models/test_result_model.dart';
import '../models/product_model.dart';
import '../models/reward_points_model.dart';
import '../models/reward_request_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // User Operations
  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toJson());
  }

  Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromJson(doc.data()!);
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
          (snapshot) => snapshot.docs
              .map((doc) => UserModel.fromJson(doc.data()))
              .toList(),
        );
  }

  // Test Operations
  Future<String> createTest(TestModel test) async {
    final docRef = _db.collection('tests').doc();
    final data = test.toJson();
    data['id'] = docRef.id;
    await docRef.set(data);
    return docRef.id;
  }

  // Assign test to all students in the specified class/section using teacher's schoolCode and test's target class
  Future<void> assignTestToClass(String testId, String teacherAuthUid) async {
    print('📝 Assigning test $testId using teacher Auth UID: $teacherAuthUid');
    try {
      // Fetch test document to get the target className and section
      final testDoc = await _db.collection('tests').doc(testId).get();
      if (!testDoc.exists) {
        print('⚠️ Test document not found for $testId');
        return;
      }
      final testData = testDoc.data()!;
      final targetClassName = testData['className'] as String? ?? '';
      final targetSection = testData['section'] as String? ?? '';

      // Fetch teacher document by querying with Auth UID (email lookup)
      // First try direct doc lookup, then query by email
      var teacherDoc = await _db
          .collection('teachers')
          .doc(teacherAuthUid)
          .get();
      Map<String, dynamic>? teacherData;

      if (!teacherDoc.exists) {
        print('   Teacher doc not found by UID, trying email lookup...');
        // Get teacher email from Firebase Auth current user
        final currentUser = FirebaseAuth.instance.currentUser;
        final userEmail = currentUser?.email;
        print('   Firebase Auth email: $userEmail');

        if (userEmail != null) {
          print(
            '   Found teacher email from Auth: $userEmail, querying teachers collection...',
          );
          // Pre-assignment audit: count how many students have UID for this teacher
          try {
            await countStudentsUidByTeacherEmail(userEmail);
          } catch (e) {
            // ignore: avoid_print
            print('   (audit) Failed to count UIDs for $userEmail: $e');
          }
          final teacherQuery = await _db
              .collection('teachers')
              .where('email', isEqualTo: userEmail)
              .limit(1)
              .get();
          print('   Teacher query found ${teacherQuery.docs.length} results');
          if (teacherQuery.docs.isNotEmpty) {
            teacherData = teacherQuery.docs.first.data();
            print('   ✓ Found teacher document via email query');
            print('   Teacher data: $teacherData');
          } else {
            print('   ⚠️ No teacher document found with email: $userEmail');
          }
        } else {
          print('   ⚠️ No email available from Firebase Auth');
        }
      } else {
        teacherData = teacherDoc.data();
        print('   ✓ Found teacher document directly by UID');
      }

      if (teacherData == null) {
        print(
          '❌ FATAL: Teacher document not found for Auth UID: $teacherAuthUid',
        );
        print('   Neither direct lookup nor email-based query succeeded.');
        return;
      }

      final schoolCode = teacherData['schoolCode'] as String? ?? '';

      if (schoolCode.isEmpty || targetClassName.isEmpty) {
        print(
          '⚠️ Missing required fields: schoolCode=$schoolCode, className=$targetClassName',
        );
        return;
      }

      print('   Teacher schoolCode: $schoolCode');
      print('   Target className: $targetClassName, section: $targetSection');

      // Query students by schoolCode, className, section
      var query = _db
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: targetClassName);
      if (targetSection.isNotEmpty) {
        query = query.where('section', isEqualTo: targetSection);
      }
      final snapshot = await query.get();
      print('📋 Found ${snapshot.docs.length} student documents');

      // Map emails to Auth UIDs
      final emails = <String>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final email =
            data['email'] as String? ?? data['studentEmail'] as String?;
        if (email != null && email.isNotEmpty) {
          emails.add(email);
        }
      }
      print('📧 Extracted ${emails.length} email addresses from students');

      // Look up Auth UIDs by checking users collection
      final studentUids = <String>[];
      final emailToUidMap = <String, String>{};

      print('🔍 Starting UID lookup for ${emails.length} student emails...');

      // Get UIDs from users collection
      for (final email in emails) {
        final userQuery = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (userQuery.docs.isNotEmpty) {
          final userDoc = userQuery.docs.first;
          final data = userDoc.data();

          // Use the uid field if it exists and is not empty
          final uid = (data['uid'] as String?)?.trim();
          if (uid != null && uid.isNotEmpty) {
            emailToUidMap[email] = uid;
            studentUids.add(uid);
            print('   ✅ $email → UID: $uid');
          } else {
            print(
              '   ⚠️ $email → uid field is EMPTY (student needs to log in first)',
            );
          }
        } else {
          print('   ❌ No user document found for: $email');
        }
      }
      print(
        '✅ Mapping complete: ${studentUids.length} UIDs found out of ${emails.length} emails',
      );
      if (studentUids.length < emails.length) {
        print(
          '⚠️ ${emails.length - studentUids.length} students need to log in to update their UIDs',
        );
      }

      // Update test document with BOTH UIDs and emails
      // Emails serve as fallback for students who haven't logged in yet
      await _db.collection('tests').doc(testId).update({
        'assignedStudentIds': studentUids,
        'assignedStudentEmails': emails,
      });
      print(
        '✅ Test document updated with ${studentUids.length} UIDs and ${emails.length} emails',
      );

      // Batch update users counters
      final batchSize = 500;
      int successCount = 0;
      int errorCount = 0;
      for (int i = 0; i < studentUids.length; i += batchSize) {
        final batchStudentIds = studentUids.skip(i).take(batchSize).toList();
        final batch = _db.batch();
        for (final studentId in batchStudentIds) {
          final userDoc = await _db.collection('users').doc(studentId).get();
          if (userDoc.exists) {
            batch.update(userDoc.reference, {
              'pendingTests': FieldValue.increment(1),
              'newNotifications': FieldValue.increment(1),
            });
            successCount++;
          } else {
            final altQuery = await _db
                .collection('users')
                .where('uid', isEqualTo: studentId)
                .limit(1)
                .get();
            if (altQuery.docs.isNotEmpty) {
              batch.update(altQuery.docs.first.reference, {
                'pendingTests': FieldValue.increment(1),
                'newNotifications': FieldValue.increment(1),
              });
              successCount++;
            } else {
              errorCount++;
              print(
                '   ⚠️ User document not found for UID (and no uid match): $studentId',
              );
            }
          }
        }
        try {
          await batch.commit();
          print('   ✓ Batch committed successfully');
        } catch (e) {
          print('   ❌ Batch commit failed: $e');
          errorCount += batchStudentIds.length;
        }
      }
      print('✅ Assignment complete: $successCount updated, $errorCount errors');
    } catch (e, stackTrace) {
      print('❌ Error in assignTestToClass: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Create test and automatically assign to class
  Future<String> createTestAndAssignToClass(TestModel test) async {
    print('📚 Creating test: ${test.title}');
    print('   className: ${test.className}');
    print('   section: ${test.section}');
    print('   status: ${test.status}');

    final testId = await createTest(test);
    print('✅ Test created with ID: $testId');

    // If className is specified and test is published, assign to class
    if (test.className != null &&
        test.className!.isNotEmpty &&
        test.status == TestStatus.published) {
      print(
        '🎯 Auto-assigning test to class ${test.className}${test.section != null ? " section ${test.section}" : ""}...',
      );
      await assignTestToClass(testId, test.teacherId);
    } else {
      print('⏭️ Skipping auto-assignment:');
      print(
        '   className is null or empty: ${test.className == null || test.className!.isEmpty}',
      );
      print(
        '   status is not published: ${test.status != TestStatus.published}',
      );
    }

    return testId;
  }

  Future<TestModel?> getTest(String testId) async {
    final doc = await _db.collection('tests').doc(testId).get();
    if (doc.exists) {
      return TestModel.fromJson(doc.data()!);
    }
    return null;
  }

  Future<void> updateTest(String testId, Map<String, dynamic> data) async {
    await _db.collection('tests').doc(testId).update(data);
  }

  Future<void> deleteTest(String testId) async {
    await _db.collection('tests').doc(testId).delete();
  }

  /// Utility: Count students for a teacher email whose user docs have a populated uid
  /// Returns a summary map with totals and prints detailed logs.
  Future<Map<String, dynamic>> countStudentsUidByTeacherEmail(
    String teacherEmail,
  ) async {
    print('🔎 Counting students with UID for teacher: $teacherEmail');
    try {
      // 1) Load teacher by email
      final teacherQuery = await _db
          .collection('teachers')
          .where('email', isEqualTo: teacherEmail)
          .limit(1)
          .get();

      if (teacherQuery.docs.isEmpty) {
        print('⚠️ No teacher found for email: $teacherEmail');
        return {'success': false, 'error': 'Teacher not found'};
      }

      final teacherData = teacherQuery.docs.first.data();
      final schoolCode = (teacherData['schoolCode'] as String?)?.trim() ?? '';
      final classesHandled = teacherData['classesHandled'] as List<dynamic>?;
      final sectionsRaw = teacherData['sections'] ?? teacherData['section'];
      final classAssignments =
          teacherData['classAssignments'] as List<dynamic>?;

      if (schoolCode.isEmpty) {
        print('⚠️ Teacher has no schoolCode');
      }

      // 2) Build list of (className, section) pairs to query students
      List<Map<String, String>> targets = [];

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

      if (classesHandled != null && classesHandled.isNotEmpty) {
        final sections = _normalizeSections(sectionsRaw);
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
        print('⚠️ No class/section targets derived for teacher');
        return {
          'success': true,
          'schoolCode': schoolCode,
          'totalStudents': 0,
          'withUid': 0,
          'withoutUid': 0,
          'missingUsers': 0,
        };
      }

      print('🎯 Query targets: ${targets.length} (className + section pairs)');

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
        print('   • $className - $section → ${snap.docs.length} students');
        for (final doc in snap.docs) {
          final data = doc.data();
          final email =
              (data['email'] as String?) ?? data['studentEmail'] as String?;
          if (email != null && email.isNotEmpty) emails.add(email.trim());
        }
      }

      print('📧 Unique student emails collected: ${emails.length}');

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
          print('   ❌ No user doc for $email');
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

      print('✅ UID summary for $teacherEmail');
      print('   • Total student docs (by classes): $totalStudentDocs');
      print('   • Unique emails: ${emails.length}');
      print('   • With UID: $withUid');
      print('   • Without UID: $withoutUid');
      print('   • Missing users: $missingUsers');

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
    } catch (e, st) {
      print('❌ Error counting UIDs: $e');
      print(st);
      return {'success': false, 'error': e.toString()};
    }
  }

  Stream<List<TestModel>> getTestsByTeacher(String teacherId) {
    // Index is enabled (teacherId asc, createdAt desc) — use server-side ordering
    return _db
        .collection('tests')
        .where('teacherId', isEqualTo: teacherId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TestModel.fromJson(doc.data()))
              .toList(),
        );
  }

  Stream<List<TestModel>> getAvailableTestsForStudent(
    String studentId, {
    String? studentEmail,
  }) async* {
    print('🎓 Student Tests Query for $studentId:');
    if (studentEmail != null) {
      print('   Email: $studentEmail');
    }

    // First, try querying by UID
    print('   Query: tests where assignedStudentIds arrayContains $studentId');
    var byUidQuery = _db
        .collection('tests')
        .where('assignedStudentIds', arrayContains: studentId)
        .where('status', isEqualTo: 'published')
        .snapshots();

    await for (var snapshot in byUidQuery) {
      var tests = snapshot.docs
          .map((doc) => TestModel.fromJson(doc.data()))
          .toList();

      print(
        '   Found ${tests.length} tests with student in assignedStudentIds',
      );

      // If no tests found by UID and email is provided, try querying by email
      if (tests.isEmpty && studentEmail != null && studentEmail.isNotEmpty) {
        print(
          '   Trying fallback query by email: assignedStudentEmails arrayContains $studentEmail',
        );
        final byEmailSnapshot = await _db
            .collection('tests')
            .where('assignedStudentEmails', arrayContains: studentEmail)
            .where('status', isEqualTo: 'published')
            .get();

        tests = byEmailSnapshot.docs
            .map((doc) => TestModel.fromJson(doc.data()))
            .toList();

        print(
          '   Found ${tests.length} tests with student email in assignedStudentEmails',
        );
      }

      // Filter to only published tests
      final publishedTests = tests
          .where((test) => test.status == TestStatus.published)
          .toList();
      print(
        '📝 After filtering by published status: ${publishedTests.length} tests',
      );

      // Debug: Check all published tests
      final allPublishedSnapshot = await _db
          .collection('tests')
          .where('status', isEqualTo: 'published')
          .get();
      print(
        '   🔍 Checking all ${allPublishedSnapshot.docs.length} published tests:',
      );
      for (var doc in allPublishedSnapshot.docs) {
        final data = doc.data();
        final assignedIds = data['assignedStudentIds'] as List<dynamic>? ?? [];
        final assignedEmails =
            data['assignedStudentEmails'] as List<dynamic>? ?? [];
        final testTitle = data['title'] ?? 'Untitled';
        print('      - "$testTitle": ${assignedIds.length} students assigned');

        if (assignedIds.contains(studentId)) {
          print('        ✓ Student IS in assignedStudentIds list');
        } else if (studentEmail != null &&
            assignedEmails.contains(studentEmail)) {
          print('        ✓ Student email IS in assignedStudentEmails list');
        } else {
          print(
            '        X Student not in list. First 3 IDs: (${assignedIds.take(3).join(', ')})',
          );
          if (assignedEmails.isNotEmpty && studentEmail != null) {
            print(
              '          First 3 emails: (${assignedEmails.take(3).join(', ')})',
            );
          }
        }
      }

      yield publishedTests;
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

  Stream<PerformanceModel?> getPerformanceStream(String studentId) {
    return _db.collection('performances').doc(studentId).snapshots().map((doc) {
      if (doc.exists) {
        return PerformanceModel.fromJson(doc.data()!);
      }
      return null;
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
    print('🔧 Starting batch UID sync...');
    print('   SchoolCode: $schoolCode');
    if (className != null) print('   ClassName: $className');
    if (section != null) print('   Section: $section');

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
      print('📋 Found ${studentsSnapshot.docs.length} students');

      int updatedCount = 0;
      int alreadyValidCount = 0;
      int errorCount = 0;
      final List<String> errors = [];

      for (final studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final email = studentData['email'] as String?;

        if (email == null || email.isEmpty) {
          print('   ⚠️ Student ${studentDoc.id} has no email, skipping');
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
          print('   ⚠️ No user doc found for $email, skipping');
          errorCount++;
          errors.add('No user doc for $email');
          continue;
        }

        final userDoc = userQuery.docs.first;
        final userData = userDoc.data();
        final currentUid = (userData['uid'] as String?)?.trim();

        // Check if uid is already valid (non-empty)
        if (currentUid != null && currentUid.isNotEmpty) {
          print('   ✅ $email already has UID: $currentUid');
          alreadyValidCount++;
          continue;
        }

        // Try to get Auth UID by attempting to sign in
        // Since we can't do that here, we'll use the user document ID as UID
        // This will be corrected when the student logs in
        print('   🔄 $email → Setting UID to doc ID: ${userDoc.id}');

        await _db.collection('users').doc(userDoc.id).update({
          'uid': userDoc.id,
        });

        updatedCount++;
      }

      print('✅ Batch sync complete!');
      print('   Updated: $updatedCount');
      print('   Already valid: $alreadyValidCount');
      print('   Errors: $errorCount');

      return {
        'success': true,
        'totalStudents': studentsSnapshot.docs.length,
        'updated': updatedCount,
        'alreadyValid': alreadyValidCount,
        'errors': errorCount,
        'errorDetails': errors,
      };
    } catch (e, stackTrace) {
      print('❌ Batch sync failed: $e');
      print('Stack trace: $stackTrace');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Submit Test Result
  Future<void> submitTestResult(TestResultModel result) async {
    print('📝 Submitting test result for student: ${result.studentName}');
    print('   Test: ${result.testTitle}');
    print('   Score: ${result.score}%');
    print('   Tab switches: ${result.tabSwitchCount}');
    print('   Violation: ${result.violationDetected}');

    try {
      // Create the test result document
      final resultDoc = _db.collection('testResults').doc();
      final resultData = result.toFirestore();
      resultData['id'] = resultDoc.id;

      await resultDoc.set(resultData);
      print('✅ Test result saved with ID: ${resultDoc.id}');

      // Update student counters
      final studentDoc = _db.collection('users').doc(result.studentId);
      await studentDoc.update({
        'completedTests': FieldValue.increment(1),
        'pendingTests': FieldValue.increment(-1),
        'totalScore': FieldValue.increment(result.score.toInt()),
        'totalPoints': FieldValue.increment(result.score.toInt()),
      });
      print('✅ Student counters updated');

      // Rewards: also log earned points record for this test
      try {
        final earnedPoints = calculatePoints(
          total: result.totalQuestions.toDouble(),
          obtained: result.correctAnswers.toDouble(),
          basePoints: 100, // default baseline
        );
        await savePointsToFirestore(
          studentId: result.studentId,
          testId: result.testId,
          marks: result.correctAnswers.toDouble(),
          totalMarks: result.totalQuestions.toDouble(),
          points: earnedPoints,
        );
        print('🏅 Reward points logged for test ${result.testId}');
      } catch (e) {
        print('⚠️ Failed to log reward points: $e');
      }

      // Update test document with completion info
      final testDoc = _db.collection('tests').doc(result.testId);
      await testDoc.update({
        'completedBy': FieldValue.arrayUnion([result.studentId]),
        'completedCount': FieldValue.increment(1),
      });
      print('✅ Test completion tracking updated');

      // If violation detected, log it separately
      if (result.violationDetected) {
        await _db.collection('violations').add({
          'studentId': result.studentId,
          'studentName': result.studentName,
          'studentEmail': result.studentEmail,
          'testId': result.testId,
          'testTitle': result.testTitle,
          'resultId': resultDoc.id,
          'violationType': 'tab_switch',
          'tabSwitchCount': result.tabSwitchCount,
          'reason': result.violationReason,
          'timestamp': FieldValue.serverTimestamp(),
          'score': result.score,
        });
        print('⚠️ Violation logged');
      }
    } catch (e, stackTrace) {
      print('❌ Error submitting test result: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // =========================
  // Rewards & Products (Student)
  // =========================

  /// Calculate points: (obtained/total) * basePoints then apply multipliers
  /// 100% ×2, 90–99 ×1.5, 75–89 ×1.2, <50 ×0.8
  int calculatePoints({
    required double total,
    required double obtained,
    int basePoints = 100,
  }) {
    if (total <= 0) return 0;
    final pct = (obtained / total) * 100.0;
    double multiplier = 1.0;
    if (pct >= 100) {
      multiplier = 2.0;
    } else if (pct >= 90) {
      multiplier = 1.5;
    } else if (pct >= 75) {
      multiplier = 1.2;
    } else if (pct < 50) {
      multiplier = 0.8;
    }
    final raw = ((obtained / total) * basePoints) * multiplier;
    return raw.round();
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
    batch.update(userRef, {
      'totalPoints': FieldValue.increment(points),
      'rewardPoints': FieldValue.increment(points),
    });

    // Optional: update students collection if present
    final studentRef = _db.collection('students').doc(studentId);
    try {
      final studentSnap = await studentRef.get();
      if (studentSnap.exists) {
        batch.update(studentRef, {
          'totalPoints': FieldValue.increment(points),
          'rewardPoints': FieldValue.increment(points),
        });
      }
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
  }) async {
    final reqRef = _db.collection('reward_requests').doc();
    final request = RewardRequestModel(
      id: reqRef.id,
      studentId: studentId,
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
    batch.update(_db.collection('users').doc(studentId), {
      'totalPoints': FieldValue.increment(-points),
      'rewardPoints': FieldValue.increment(-points),
    });
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
}
