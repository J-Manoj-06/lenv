import 'package:cloud_firestore/cloud_firestore.dart';
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
