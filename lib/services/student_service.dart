import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/student_model.dart';
import '../models/test_result_model.dart';

class StudentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current student data
  Future<StudentModel?> getCurrentStudent() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final userDocRef = _firestore.collection('users').doc(user.uid);
      // Force server read to avoid stale cache
      final userDoc = await userDocRef.get(
        const GetOptions(source: Source.server),
      );

      // If users/<uid> doesn't exist, bootstrap it from students by email
      if (!userDoc.exists) {
        final String emailFallback = user.email ?? '';
        if (emailFallback.isEmpty) return null;

        Map<String, dynamic>? studentRefData;
        try {
          // Force server read to avoid stale cache
          final sSnap = await _firestore
              .collection('students')
              .where('email', isEqualTo: emailFallback)
              .limit(1)
              .get(const GetOptions(source: Source.server));
          if (sSnap.docs.isNotEmpty) {
            studentRefData = sSnap.docs.first.data();
          }
        } catch (_) {}

        if (studentRefData == null) return null;

        // Resolve school name via schoolCode
        String? resolvedSchoolName;
        final String? schoolCode = studentRefData['schoolCode'] as String?;
        if (schoolCode != null && schoolCode.isNotEmpty) {
          try {
            final schoolSnap = await _firestore
                .collection('schools')
                .where('schoolCode', isEqualTo: schoolCode)
                .limit(1)
                .get();
            if (schoolSnap.docs.isNotEmpty) {
              resolvedSchoolName =
                  schoolSnap.docs.first.data()['name'] as String? ?? schoolCode;
            } else {
              resolvedSchoolName = schoolCode;
            }
          } catch (_) {
            resolvedSchoolName = schoolCode;
          }
        }

        // Build a StudentModel from students data
        final bootstrap = StudentModel(
          uid: user.uid,
          email: emailFallback,
          name:
              (studentRefData['studentName'] ?? studentRefData['name'] ?? '')
                  as String,
          photoUrl: null,
          schoolId: null,
          schoolCode: studentRefData['schoolCode'] as String?,
          schoolName: resolvedSchoolName,
          className: studentRefData['className'] as String?,
          section: studentRefData['section'] as String?,
          phone: studentRefData['contactNumber'] as String?,
          parentPhone: studentRefData['parentPhone'] as String?,
          parentEmail: await _resolveParentEmail(
            studentUid: user.uid,
            studentEmail: emailFallback,
            studentData: studentRefData,
          ),
          rewardPoints: 0,
          classRank: 0,
          monthlyProgress: 0.0,
          monthlyTarget: 90.0,
          pendingTests: 0,
          completedTests: 0,
          newNotifications: 0,
          createdAt: DateTime.now(),
          isActive: true,
        );

        try {
          await userDocRef.set(
            bootstrap.toFirestore(),
            SetOptions(merge: true),
          );
        } catch (_) {}

        return bootstrap;
      }

      // Base model from users collection
      StudentModel base = StudentModel.fromFirestore(userDoc);

      // If any key fields are missing, enrich from students collection (by email)
      String email = base.email.isNotEmpty
          ? base.email
          : (userDoc.data()?['email'] ?? user.email ?? '');

      Map<String, dynamic>? studentRefData;
      try {
        if (email.isNotEmpty) {
          final sSnap = await _firestore
              .collection('students')
              .where('email', isEqualTo: email)
              .limit(1)
              .get(const GetOptions(source: Source.server));
          if (sSnap.docs.isNotEmpty) {
            studentRefData = sSnap.docs.first.data();
          }
        }
      } catch (_) {}

      String resolvedName = base.name.isNotEmpty
          ? base.name
          : (studentRefData?['studentName'] ??
                studentRefData?['name'] ??
                base.name);
      String? resolvedPhone = (base.phone != null && base.phone!.isNotEmpty)
          ? base.phone
          : (studentRefData?['contactNumber'] as String?);
      String? resolvedParentPhone =
          (base.parentPhone != null && base.parentPhone!.isNotEmpty)
          ? base.parentPhone
          : (studentRefData?['parentPhone'] as String?);
      String? resolvedClassName =
          (base.className != null && base.className!.isNotEmpty)
          ? base.className
          : (studentRefData?['className'] as String?);

      String? resolvedSection =
          (base.section != null && base.section!.isNotEmpty)
          ? base.section
          : (studentRefData?['section'] as String?);

      String? resolvedSchoolCode = base.schoolCode;
      if ((resolvedSchoolCode == null || resolvedSchoolCode.isEmpty) &&
          studentRefData != null) {
        resolvedSchoolCode = studentRefData['schoolCode'] as String?;
      }

      String? resolvedSchoolName = base.schoolName;
      if ((resolvedSchoolName == null || resolvedSchoolName.isEmpty) &&
          studentRefData != null) {
        final String? schoolCode = studentRefData['schoolCode'] as String?;
        if (schoolCode != null && schoolCode.isNotEmpty) {
          try {
            final schoolSnap = await _firestore
                .collection('schools')
                .where('schoolCode', isEqualTo: schoolCode)
                .limit(1)
                .get();
            if (schoolSnap.docs.isNotEmpty) {
              resolvedSchoolName =
                  schoolSnap.docs.first.data()['name'] as String? ?? schoolCode;
            } else {
              resolvedSchoolName = schoolCode;
            }
          } catch (_) {
            resolvedSchoolName = schoolCode;
          }
        }
      }

      final String? resolvedParentEmail = await _resolveParentEmail(
        studentUid: user.uid,
        studentEmail: email,
        studentData: studentRefData,
      );

      final Map<String, dynamic> updates = {};
      if (resolvedName.isNotEmpty && resolvedName != base.name) {
        updates['name'] = resolvedName;
      }
      if (resolvedPhone != null &&
          resolvedPhone.isNotEmpty &&
          resolvedPhone != base.phone) {
        updates['phone'] = resolvedPhone;
      }
      if (resolvedParentPhone != null &&
          resolvedParentPhone.isNotEmpty &&
          resolvedParentPhone != base.parentPhone) {
        updates['parentPhone'] = resolvedParentPhone;
      }
      if (resolvedClassName != null &&
          resolvedClassName.isNotEmpty &&
          resolvedClassName != base.className) {
        updates['className'] = resolvedClassName;
      }
      if (resolvedSection != null &&
          resolvedSection.isNotEmpty &&
          resolvedSection != base.section) {
        updates['section'] = resolvedSection;
      }
      if (resolvedSchoolCode != null &&
          resolvedSchoolCode.isNotEmpty &&
          resolvedSchoolCode != base.schoolCode) {
        updates['schoolCode'] = resolvedSchoolCode;
      }
      if (resolvedSchoolName != null &&
          resolvedSchoolName.isNotEmpty &&
          resolvedSchoolName != base.schoolName) {
        updates['schoolName'] = resolvedSchoolName;
      }
      if (resolvedParentEmail != null &&
          resolvedParentEmail.isNotEmpty &&
          resolvedParentEmail != base.parentEmail) {
        updates['parentEmail'] = resolvedParentEmail;
      }

      if (updates.isNotEmpty) {
        try {
          await _firestore.collection('users').doc(user.uid).update(updates);
        } catch (e) {}
      }

      if (studentRefData != null && updates.isNotEmpty) {
        try {
          await _firestore.collection('students').doc(user.uid).update(updates);
        } catch (e) {}
      }

      try {
        final studentsDoc = await _firestore
            .collection('students')
            .doc(user.uid)
            .get();
        if (!studentsDoc.exists) {
          await _firestore.collection('students').doc(user.uid).set({
            'uid': user.uid,
            'email': base.email.isNotEmpty ? base.email : user.email ?? '',
            'name': resolvedName,
            'studentName': resolvedName,
            'className': resolvedClassName ?? '',
            'section': resolvedSection ?? '',
            'schoolCode': resolvedSchoolCode ?? '',
            'schoolName': resolvedSchoolName ?? '',
            'phone': resolvedPhone ?? '',
            'contactNumber': resolvedPhone ?? '',
            'parentPhone': resolvedParentPhone ?? '',
            if (resolvedParentEmail != null && resolvedParentEmail.isNotEmpty)
              'parentEmail': resolvedParentEmail,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          final doc = studentsDoc.data() ?? {};
          if ((doc['className'] as String?)?.isEmpty ?? true) {
            await _firestore.collection('students').doc(user.uid).update({
              'className': resolvedClassName ?? '',
              'section': resolvedSection ?? '',
              'schoolCode': resolvedSchoolCode ?? '',
              'schoolName': resolvedSchoolName ?? '',
              if (resolvedParentEmail != null && resolvedParentEmail.isNotEmpty)
                'parentEmail': resolvedParentEmail,
            });
          }
        }
      } catch (e) {}

      return base.copyWith(
        name: resolvedName,
        phone: resolvedPhone,
        parentPhone: resolvedParentPhone,
        parentEmail: resolvedParentEmail,
        className: resolvedClassName,
        section: resolvedSection,
        schoolCode: resolvedSchoolCode,
        schoolName: resolvedSchoolName,
      );
    } catch (e) {
      final user = _auth.currentUser;
      if (user != null) {
        try {
          return await _buildFallbackStudent(user);
        } catch (_) {}
      }
      return null;
    }
  }

  Future<String?> _resolveParentEmail({
    required String studentUid,
    required String studentEmail,
    Map<String, dynamic>? studentData,
  }) async {
    String? normalize(dynamic value) {
      final s = value?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final directParentEmail =
        normalize(studentData?['parentEmail']) ??
        normalize(studentData?['parent_email']);
    if (directParentEmail != null) return directParentEmail;

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(studentUid)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data() ?? <String, dynamic>{};
        final fromUser =
            normalize(userData['parentEmail']) ??
            normalize(userData['parent_email']);
        if (fromUser != null) return fromUser;
      }
    } catch (_) {}

    final studentParentPhone =
        normalize(studentData?['parentPhone']) ??
        normalize(studentData?['parent_phone']);

    if (studentParentPhone != null) {
      try {
        final phoneQueries = await Future.wait([
          _firestore
              .collection('parents')
              .where('phoneNumber', isEqualTo: studentParentPhone)
              .limit(1)
              .get(),
          _firestore
              .collection('parents')
              .where('phone', isEqualTo: studentParentPhone)
              .limit(1)
              .get(),
          _firestore
              .collection('parents')
              .where('parentPhone', isEqualTo: studentParentPhone)
              .limit(1)
              .get(),
        ]);

        for (final snap in phoneQueries) {
          if (snap.docs.isNotEmpty) {
            final email = normalize(snap.docs.first.data()['email']);
            if (email != null) {
              try {
                await _firestore.collection('users').doc(studentUid).set({
                  'parentEmail': email,
                }, SetOptions(merge: true));
              } catch (_) {}
              try {
                await _firestore.collection('students').doc(studentUid).set({
                  'parentEmail': email,
                }, SetOptions(merge: true));
              } catch (_) {}
              return email;
            }
          }
        }
      } catch (_) {}
    }

    try {
      final parentsSnap = await _firestore
          .collection('parents')
          .limit(100)
          .get();
      for (final doc in parentsSnap.docs) {
        final data = doc.data();
        final linkedStudents = (data['linkedStudents'] as List?) ?? const [];
        final isLinked = linkedStudents.any((entry) {
          if (entry is Map) {
            final entryUid = normalize(entry['id']) ?? normalize(entry['uid']);
            final entryEmail = normalize(entry['email']);
            return entryUid == studentUid || entryEmail == studentEmail;
          }
          final entryValue = normalize(entry);
          return entryValue == studentUid || entryValue == studentEmail;
        });

        if (isLinked) {
          final email = normalize(data['email']);
          if (email != null) {
            try {
              await _firestore.collection('users').doc(studentUid).set({
                'parentEmail': email,
              }, SetOptions(merge: true));
            } catch (_) {}
            try {
              await _firestore.collection('students').doc(studentUid).set({
                'parentEmail': email,
              }, SetOptions(merge: true));
            } catch (_) {}
            return email;
          }
        }
      }
    } catch (_) {}

    try {
      final parentSnap = await _firestore
          .collection('parents')
          .where('linkedStudentsEmails', arrayContains: studentEmail)
          .limit(1)
          .get();
      if (parentSnap.docs.isNotEmpty) {
        final email = normalize(parentSnap.docs.first.data()['email']);
        if (email != null) return email;
      }
    } catch (_) {}

    return null;
  }

  /// Fallback builder: minimal student using auth info + student_rewards sum
  Future<StudentModel> _buildFallbackStudent(User user) async {
    double totalPoints = 0;
    try {
      final rewardsSnap = await _firestore
          .collection('student_rewards')
          .where('studentId', isEqualTo: user.uid)
          .get();
      for (final doc in rewardsSnap.docs) {
        final data = doc.data();
        final pts = data['pointsEarned'];
        if (pts is num) totalPoints += pts.toDouble();
      }
    } catch (e) {}

    return StudentModel(
      uid: user.uid,
      email: user.email ?? '',
      name: user.displayName ?? 'Student',
      photoUrl: user.photoURL,
      schoolId: null,
      schoolCode: null,
      schoolName: null,
      className: null,
      section: null,
      phone: null,
      parentPhone: null,
      rewardPoints: totalPoints.toInt(),
      classRank: 0,
      monthlyProgress: 0,
      monthlyTarget: 90,
      pendingTests: 0,
      completedTests: 0,
      newNotifications: 0,
      streak: 0,
      lastStreakDate: null,
      createdAt: DateTime.now(),
      isActive: true,
    );
  }

  // Stream of student data (real-time updates)
  Stream<StudentModel?> getStudentStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return StudentModel.fromFirestore(doc);
    });
  }

  // Update student stats
  Future<void> updateStudentStats({
    required String uid,
    int? rewardPoints,
    int? classRank,
    double? monthlyProgress,
    int? pendingTests,
    int? completedTests,
    int? newNotifications,
  }) async {
    try {
      final Map<String, dynamic> updates = {};

      if (rewardPoints != null) updates['rewardPoints'] = rewardPoints;
      if (classRank != null) updates['classRank'] = classRank;
      if (monthlyProgress != null) updates['monthlyProgress'] = monthlyProgress;
      if (pendingTests != null) updates['pendingTests'] = pendingTests;
      if (completedTests != null) updates['completedTests'] = completedTests;
      if (newNotifications != null) {
        updates['newNotifications'] = newNotifications;
      }

      if (updates.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updates);
      }
    } catch (e) {
      rethrow;
    }
  }

  // Update student profile information
  Future<void> updateStudentProfile({
    required String uid,
    String? name,
    String? phone,
    String? schoolName,
    String? parentPhone,
    String? className,
    String? photoUrl,
  }) async {
    try {
      final Map<String, dynamic> updates = {};

      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;
      if (schoolName != null) updates['schoolName'] = schoolName;
      if (parentPhone != null) updates['parentPhone'] = parentPhone;
      if (className != null) updates['className'] = className;
      if (photoUrl != null) updates['photoUrl'] = photoUrl;

      if (updates.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updates);
      }
    } catch (e) {
      rethrow;
    }
  }

  // Get today's daily challenge
  Future<DailyChallengeModel?> getTodayChallenge() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot = await _firestore
          .collection('dailyChallenges')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;

      return DailyChallengeModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      return null;
    }
  }

  // Get student notifications
  Future<List<NotificationModel>> getStudentNotifications(
    String studentId, {
    int limit = 10,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('studentId', isEqualTo: studentId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // Get unread notification count
  Future<int> getUnreadNotificationCount(String studentId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('studentId', isEqualTo: studentId)
          .where('isRead', isEqualTo: false)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {}
  }

  // Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String studentId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('studentId', isEqualTo: studentId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {}
  }

  // Submit daily challenge answer
  Future<bool> submitChallengeAnswer({
    required String studentId,
    required String challengeId,
    required String answer,
  }) async {
    try {
      // Get the challenge
      final challengeDoc = await _firestore
          .collection('dailyChallenges')
          .doc(challengeId)
          .get();

      if (!challengeDoc.exists) return false;

      final challenge = DailyChallengeModel.fromFirestore(challengeDoc);
      final isCorrect =
          answer.toLowerCase() == challenge.correctAnswer.toLowerCase();

      // Record the attempt
      await _firestore.collection('challengeAttempts').add({
        'studentId': studentId,
        'challengeId': challengeId,
        'answer': answer,
        'isCorrect': isCorrect,
        'pointsEarned': isCorrect ? challenge.points : 0,
        'attemptedAt': FieldValue.serverTimestamp(),
      });

      // If correct, update student points AND create student_rewards entry
      if (isCorrect) {
        // Create student_rewards entry (same as test points)
        final rewardDoc = _firestore.collection('student_rewards').doc();
        await rewardDoc.set({
          'id': rewardDoc.id,
          'studentId': studentId,
          'testId': challengeId, // Use challengeId as testId for tracking
          'marks': 1.0, // Correct answer = 1 mark
          'totalMarks': 1.0,
          'pointsEarned': challenge.points,
          'timestamp': FieldValue.serverTimestamp(),
          'source': 'daily_challenge', // Mark this as daily challenge points
        });

        // Update users collection using merge to handle missing docs
        await _firestore.collection('users').doc(studentId).set({
          'rewardPoints': FieldValue.increment(challenge.points),
          'totalPoints': FieldValue.increment(challenge.points),
        }, SetOptions(merge: true));
      }

      return isCorrect;
    } catch (e) {
      return false;
    }
  }

  // Check if student has attempted today's challenge
  Future<bool> hasAttemptedTodayChallenge(String studentId) async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);

      final snapshot = await _firestore
          .collection('challengeAttempts')
          .where('studentId', isEqualTo: studentId)
          .where(
            'attemptedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Get student's pending tests count
  Future<int> getPendingTestsCount(String studentId) async {
    try {
      // Query testResults collection for assignments with status='assigned'
      final snapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where('status', isEqualTo: 'assigned')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  // Calculate monthly progress
  Future<double> calculateMonthlyProgress(String studentId) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      // Get tests taken this month
      final snapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where(
            'completedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .get();

      if (snapshot.docs.isEmpty) return 0.0;

      // Calculate average score
      double totalScore = 0;
      for (var doc in snapshot.docs) {
        totalScore += (doc.data()['score'] ?? 0.0).toDouble();
      }

      return totalScore / snapshot.docs.length;
    } catch (e) {
      return 0.0;
    }
  }

  // Get a specific test result by its document id
  Future<TestResultModel?> getTestResultById(String resultId) async {
    try {
      final doc = await _firestore
          .collection('testResults')
          .doc(resultId)
          .get();
      if (!doc.exists) return null;
      return TestResultModel.fromFirestore(doc);
    } catch (e) {
      return null;
    }
  }
}
