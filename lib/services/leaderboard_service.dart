import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardEntry {
  final String studentId;
  final String name;
  final String? photoUrl;
  final int rank;
  final num score; // for overall: points/avg; for per-test: test score

  LeaderboardEntry({
    required this.studentId,
    required this.name,
    this.photoUrl,
    required this.rank,
    required this.score,
  });
}

class StudentStats {
  final int testsTaken; // distinct testIds
  final double averageScore; // avg of latest attempt per test
  final int? classRank; // 1-based, among classmates by points

  StudentStats({
    required this.testsTaken,
    required this.averageScore,
    this.classRank,
  });
}

class LeaderboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Helper: get student doc (students collection) for uid or email
  Future<Map<String, dynamic>?> _getStudentDocByUidOrEmail({
    required String uid,
    String? email,
  }) async {
    // Try by uid
    final doc = await _db.collection('students').doc(uid).get();
    if (doc.exists) return doc.data();
    if (email != null && email.isNotEmpty) {
      final q = await _db
          .collection('students')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.data();
    }
    return null;
  }

  // Overall leaderboard based on users.rewardPoints within same school/class/section
  Future<List<LeaderboardEntry>> getOverallLeaderboardForClass({
    required String schoolCode,
    required String className,
    String? section,
    int limit = 50,
  }) async {
    // 1) Get class roster from students collection
    var q = _db
        .collection('students')
        .where('schoolCode', isEqualTo: schoolCode)
        .where('className', isEqualTo: className);
    if (section != null && section.isNotEmpty) {
      q = q.where('section', isEqualTo: section);
    }
    final studentsSnap = await q.get();
    if (studentsSnap.docs.isEmpty) return <LeaderboardEntry>[];

    // 2) For each student, try to locate users/{uid} by matching email
    final entries = <Map<String, dynamic>>[];
    for (final sDoc in studentsSnap.docs) {
      final s = sDoc.data();
      final email = (s['email'] as String?) ?? s['studentEmail'] as String?;
      final name = (s['name'] as String?) ?? s['studentName'] as String? ?? '';
      final photoUrl = s['photoUrl'] as String?;
      String? uidFromUsers;
      int rewardPoints = 0;
      if (email != null && email.isNotEmpty) {
        final uq = await _db
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (uq.docs.isNotEmpty) {
          final u = uq.docs.first.data();
          uidFromUsers = (u['uid'] as String?) ?? uq.docs.first.id;
          rewardPoints = (u['rewardPoints'] as num?)?.toInt() ?? 0;
        }
      }
      entries.add({
        'uid': uidFromUsers ?? sDoc.id,
        'name': name,
        'photoUrl': photoUrl,
        'points': rewardPoints,
      });
    }

    // 3) Sort by points desc and assign ranks
    entries.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
    final result = <LeaderboardEntry>[];
    for (var i = 0; i < entries.length && i < limit; i++) {
      final e = entries[i];
      result.add(
        LeaderboardEntry(
          studentId: e['uid'] as String,
          name: e['name'] as String,
          photoUrl: e['photoUrl'] as String?,
          rank: i + 1,
          score: e['points'] as int,
        ),
      );
    }
    return result;
  }

  // Per-test leaderboard: rank students by their score for a specific test
  Future<List<LeaderboardEntry>> getPerTestLeaderboard({
    required String testId,
    String? schoolCode,
    int limit = 100,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('testResults')
        .where('testId', isEqualTo: testId);
    if (schoolCode != null && schoolCode.isNotEmpty) {
      q = q.where('schoolCode', isEqualTo: schoolCode);
    }
    final snap = await q.get();
    if (snap.docs.isEmpty) return <LeaderboardEntry>[];

    // Dedup by studentId, keep highest score
    final bestByStudent = <String, Map<String, dynamic>>{};
    for (final d in snap.docs) {
      final data = d.data();
      final sid = data['studentId'] as String?;
      if (sid == null || sid.isEmpty) continue;
      final score = (data['score'] as num?)?.toDouble() ?? 0.0;
      final name = data['studentName'] as String? ?? '';
      if (!bestByStudent.containsKey(sid) ||
          score > (bestByStudent[sid]!['score'] as double)) {
        bestByStudent[sid] = {'studentId': sid, 'name': name, 'score': score};
      }
    }

    final list = bestByStudent.values.toList();
    list.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final result = <LeaderboardEntry>[];
    for (var i = 0; i < list.length && i < limit; i++) {
      final e = list[i];
      result.add(
        LeaderboardEntry(
          studentId: e['studentId'] as String,
          name: e['name'] as String,
          photoUrl: null,
          rank: i + 1,
          score: e['score'] as double,
        ),
      );
    }
    return result;
  }

  // Student profile stats from testResults (distinct tests) and class rank by points
  Future<StudentStats> getStudentStats({
    required String studentId,
    String? email,
  }) async {
    // Load all results for student
    final snap = await _db
        .collection('testResults')
        .where('studentId', isEqualTo: studentId)
        .get();

    // Dedup by testId: keep latest completedAt
    final byTest = <String, Map<String, dynamic>>{};
    for (final d in snap.docs) {
      final data = d.data();
      final tId = data['testId'] as String?;
      if (tId == null || tId.isEmpty) continue;
      final completedAt =
          (data['completedAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      if (!byTest.containsKey(tId) ||
          completedAt.isAfter(byTest[tId]!['completedAt'] as DateTime)) {
        byTest[tId] = {
          'score': (data['score'] as num?)?.toDouble() ?? 0.0,
          'completedAt': completedAt,
        };
      }
    }

    final testsTaken = byTest.length;
    final averageScore = testsTaken == 0
        ? 0.0
        : byTest.values
                  .map((e) => e['score'] as double)
                  .fold<double>(0.0, (a, b) => a + b) /
              testsTaken;

    // Compute class rank by rewardPoints among classmates
    // First, read student's class info from students collection
    final studentDoc = await _getStudentDocByUidOrEmail(
      uid: studentId,
      email: email,
    );
    int? classRank;
    if (studentDoc != null) {
      final schoolCode = (studentDoc['schoolCode'] as String?) ?? '';
      final className = (studentDoc['className'] as String?) ?? '';
      final section = studentDoc['section'] as String?;
      if (schoolCode.isNotEmpty && className.isNotEmpty) {
        final lb = await getOverallLeaderboardForClass(
          schoolCode: schoolCode,
          className: className,
          section: section,
          limit: 200,
        );
        final idx = lb.indexWhere((e) => e.studentId == studentId);
        if (idx != -1) classRank = lb[idx].rank;
      }
    }

    return StudentStats(
      testsTaken: testsTaken,
      averageScore: averageScore,
      classRank: classRank,
    );
  }
}
