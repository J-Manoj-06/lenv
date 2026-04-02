import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../utils/cache_manager.dart';
import 'dart:async';

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

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<int> _computeCanonicalPoints({
    required String uid,
    required Map<String, dynamic> studentData,
  }) async {
    // Canonical source: students.available_points (trust explicit value, including zero)
    if (studentData.containsKey('available_points')) {
      return _parseInt(studentData['available_points']).clamp(0, 1 << 30);
    }

    // Fallback for older docs: sum(student_rewards.pointsEarned) - locked_points
    try {
      final rewardsSnap = await _db
          .collection('student_rewards')
          .where('studentId', isEqualTo: uid)
          .get();
      int earned = 0;
      for (final doc in rewardsSnap.docs) {
        earned += _parseInt(doc.data()['pointsEarned']);
      }
      final locked = _parseInt(studentData['locked_points']);
      return (earned - locked).clamp(0, 1 << 30);
    } catch (_) {
      return _parseInt(studentData['rewardPoints']);
    }
  }

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

  // Overall leaderboard based on available points within same school/class/section.
  // Canonical order: students.available_points -> users.rewardPoints fallback.
  Future<List<LeaderboardEntry>> getOverallLeaderboardForClass({
    required String schoolCode,
    required String className,
    String? section,
    int limit = 50,
  }) async {
    try {
      // 1) Get class roster from students collection (has className and section)
      var q = _db
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: className);

      if (section != null && section.isNotEmpty) {
        q = q.where('section', isEqualTo: section);
      }

      final studentsSnap = await q.get();
      if (studentsSnap.docs.isEmpty) return <LeaderboardEntry>[];

      // 2) Build leaderboard entries with canonical points.
      final entries = <LeaderboardEntry>[];

      for (final studentDoc in studentsSnap.docs) {
        final studentData = studentDoc.data();
        final uid = studentData['uid'] as String?;
        if (uid == null) continue;

        num score = await _computeCanonicalPoints(
          uid: uid,
          studentData: studentData,
        );

        String name =
            (studentData['studentName'] as String?) ??
            (studentData['name'] as String?) ??
            'Student';
        String? photoUrl = studentData['photoUrl'] as String?;

        // Fallback to users doc if needed (legacy profiles).
        if (score <= 0 || name == 'Student' || photoUrl == null) {
          try {
            final userDoc = await _db.collection('users').doc(uid).get();
            if (userDoc.exists) {
              final userData = userDoc.data() ?? {};
              if (score <= 0) {
                score = _parseInt(userData['available_points']) > 0
                    ? _parseInt(userData['available_points'])
                    : (_parseInt(userData['rewardPoints']) > 0
                          ? _parseInt(userData['rewardPoints'])
                          : (_parseInt(userData['totalPoints']) > 0
                                ? _parseInt(userData['totalPoints'])
                                : score));
              }
              if (name == 'Student') {
                name = (userData['name'] as String?) ?? name;
              }
              photoUrl ??= userData['photoUrl'] as String?;
            }
          } catch (_) {}
        }

        entries.add(
          LeaderboardEntry(
            studentId: uid,
            name: name,
            photoUrl: photoUrl,
            rank: 0, // Will assign after sorting
            score: score,
          ),
        );
      }

      // 3) Sort by score (descending) and assign ranks
      return _dedupeAndRank(entries, limit: limit);
    } catch (e) {
      return [];
    }
  }

  /// Helper: Convert LeaderboardEntry to cacheable map
  List<Map<String, dynamic>> _entriesToCacheableList(
    List<LeaderboardEntry> entries,
  ) {
    return entries
        .map(
          (e) => {
            'studentId': e.studentId,
            'name': e.name,
            'photoUrl': e.photoUrl,
            'rank': e.rank,
            'score': e.score,
          },
        )
        .toList();
  }

  /// Helper: Convert cacheable map to LeaderboardEntry
  List<LeaderboardEntry> _cacheableListToEntries(
    List<Map<String, dynamic>> cached,
  ) {
    return cached
        .map(
          (e) => LeaderboardEntry(
            studentId: e['studentId'] as String,
            name: e['name'] as String,
            photoUrl: e['photoUrl'] as String?,
            rank: e['rank'] as int,
            score: e['score'] as num,
          ),
        )
        .toList();
  }

  // Ensure only one entry per studentId, keep highest score, and re-rank
  List<LeaderboardEntry> _dedupeAndRank(
    List<LeaderboardEntry> entries, {
    int limit = 50,
  }) {
    final bestByStudent = <String, LeaderboardEntry>{};

    for (final entry in entries) {
      final existing = bestByStudent[entry.studentId];
      if (existing == null || entry.score > existing.score) {
        bestByStudent[entry.studentId] = entry;
      }
    }

    final unique = bestByStudent.values.toList();
    unique.sort((a, b) => b.score.compareTo(a.score));

    for (var i = 0; i < unique.length; i++) {
      unique[i] = LeaderboardEntry(
        studentId: unique[i].studentId,
        name: unique[i].name,
        photoUrl: unique[i].photoUrl,
        rank: i + 1,
        score: unique[i].score,
      );
    }

    return unique.take(limit).toList();
  }

  /// Get overall leaderboard with caching - fetches from cache first, then updates
  Future<List<LeaderboardEntry>> getOverallLeaderboardForClassWithCache({
    required String schoolCode,
    required String className,
    String? section,
    int limit = 50,
  }) async {
    // Fetch fresh data and cache it
    final entries = await getOverallLeaderboardForClass(
      schoolCode: schoolCode,
      className: className,
      section: section,
      limit: limit,
    );

    // Cache the results for instant display next time
    if (entries.isNotEmpty) {
      await CacheManager.cacheLeaderboardData(
        schoolCode: schoolCode,
        className: className,
        entries: _entriesToCacheableList(entries),
      );
    }

    return entries;
  }

  // ✅ OPTIMIZED: Stream-based overall leaderboard with instant cache display + real-time updates
  // Emits cached data IMMEDIATELY (0s), then listens for real-time updates
  Stream<List<LeaderboardEntry>> getOverallLeaderboardStreamForClass({
    required String schoolCode,
    required String className,
    String? section,
    int limit = 50,
  }) async* {
    if (schoolCode.isEmpty || className.isEmpty) {
      yield [];
      return;
    }

    // ✅ STEP 1: Emit cached data IMMEDIATELY for instant display (0 seconds!)
    final cachedData = await CacheManager.getLeaderboardCache(
      schoolCode: schoolCode,
      className: className,
    );

    if (cachedData != null && cachedData.isNotEmpty) {
      yield _cacheableListToEntries(cachedData);
    }

    // ✅ STEP 2: Listen to students class roster for real-time point updates
    // (available_points / locked_points changes are reflected here).
    // Uses a debounce approach to avoid excessive refreshes.
    DateTime? lastUpdate;
    const debounceDuration = Duration(seconds: 2);

    Query<Map<String, dynamic>> studentsQuery = _db
        .collection('students')
        .where('schoolCode', isEqualTo: schoolCode)
        .where('className', isEqualTo: className);
    if (section != null && section.isNotEmpty) {
      studentsQuery = studentsQuery.where('section', isEqualTo: section);
    }

    try {
      await for (final _ in studentsQuery.snapshots()) {
        final now = DateTime.now();

        // Debounce: Only refresh if 2 seconds passed since last update
        if (lastUpdate != null &&
            now.difference(lastUpdate) < debounceDuration) {
          continue;
        }

        lastUpdate = now;

        // Fetch fresh data and cache it
        final entries = await getOverallLeaderboardForClassWithCache(
          schoolCode: schoolCode,
          className: className,
          section: section,
          limit: limit,
        );

        yield entries;
      }
    } on FirebaseException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      final isSignedOut = FirebaseAuth.instance.currentUser == null;
      final isPermissionIssue =
          e.code == 'permission-denied' ||
          msg.contains('permission denied') ||
          msg.contains('insufficient permissions');

      if (isSignedOut && isPermissionIssue) {
        if (kDebugMode) {
          debugPrint(
            '[LeaderboardService] Ignoring stream error after sign-out: $e',
          );
        }
        yield const <LeaderboardEntry>[];
        return;
      }
      rethrow;
    }
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
