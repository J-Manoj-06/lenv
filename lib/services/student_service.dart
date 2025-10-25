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

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;

      return StudentModel.fromFirestore(doc);
    } catch (e) {
      print('Error getting student: $e');
      return null;
    }
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
      if (newNotifications != null)
        updates['newNotifications'] = newNotifications;

      if (updates.isNotEmpty) {
        await _firestore.collection('users').doc(uid).update(updates);
      }
    } catch (e) {
      print('Error updating student stats: $e');
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
      print('Error getting daily challenge: $e');
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
      print('Error getting notifications: $e');
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
      print('Error getting unread count: $e');
      return 0;
    }
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
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
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
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

      // If correct, update student points
      if (isCorrect) {
        final studentDoc = await _firestore
            .collection('users')
            .doc(studentId)
            .get();
        final currentPoints = studentDoc.data()?['rewardPoints'] ?? 0;
        await _firestore.collection('users').doc(studentId).update({
          'rewardPoints': currentPoints + challenge.points,
        });
      }

      return isCorrect;
    } catch (e) {
      print('Error submitting challenge answer: $e');
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
      print('Error checking challenge attempt: $e');
      return false;
    }
  }

  // Get student's pending tests count
  Future<int> getPendingTestsCount(String studentId) async {
    try {
      final snapshot = await _firestore
          .collection('tests')
          .where('studentIds', arrayContains: studentId)
          .where('status', isEqualTo: 'active')
          .where('endTime', isGreaterThan: Timestamp.now())
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('Error getting pending tests: $e');
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
      print('Error calculating monthly progress: $e');
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
      print('Error getting test result: $e');
      return null;
    }
  }
}
