import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/test_model.dart';
import '../models/reward_model.dart';
import '../models/performance_model.dart';
import '../models/test_result_model.dart';

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
            print('   ⚠️ $email → uid field is EMPTY (student needs to log in first)');
          }
        } else {
          print('   ❌ No user document found for: $email');
        }
      }
      print('✅ Mapping complete: ${studentUids.length} UIDs found out of ${emails.length} emails');
      if (studentUids.length < emails.length) {
        print('⚠️ ${emails.length - studentUids.length} students need to log in to update their UIDs');
      }

      // Update test document
      await _db.collection('tests').doc(testId).update({
        'assignedStudentIds': studentUids,
      });
      print('✅ Test document updated successfully');

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

  Stream<List<TestModel>> getAvailableTestsForStudent(String studentId) {
    return _db
        .collection('tests')
        .where('assignedStudentIds', arrayContains: studentId)
        .where('status', isEqualTo: 'published')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => TestModel.fromJson(doc.data()))
              .toList(),
        );
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
}
