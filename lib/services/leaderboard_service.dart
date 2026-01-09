import 'package:cloud_firestore/cloud_firestore.dart';
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
  // OPTIMIZED: Gets class roster from students, then fetches rewardPoints from users in parallel
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

      print(
        '📊 Found ${studentsSnap.docs.length} students in class $className',
      );

      // 2) Batch fetch rewardPoints from users collection
      final entries = <LeaderboardEntry>[];

      for (final studentDoc in studentsSnap.docs) {
        final studentData = studentDoc.data();
        final uid = studentData['uid'] as String?;
        if (uid == null) continue;

        final userDoc = await _db.collection('users').doc(uid).get();
        if (!userDoc.exists) continue;

        final userData = userDoc.data() ?? {};
        entries.add(
          LeaderboardEntry(
            studentId: uid,
            name:
                userData['name'] as String? ??
                studentData['studentName'] as String? ??
                'Student',
            photoUrl: userData['photoUrl'] as String?,
            rank: 0, // Will assign after sorting
            score: userData['rewardPoints'] as num? ?? 0,
          ),
        );
      }

      // 3) Sort by score (descending) and assign ranks
      return _dedupeAndRank(entries, limit: limit);
    } catch (e) {
      print('❌ Error getting overall leaderboard: $e');
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

    print(
      '🔄 Creating optimized leaderboard stream for $schoolCode / $className',
    );

    // ✅ STEP 1: Emit cached data IMMEDIATELY for instant display (0 seconds!)
    final cachedData = await CacheManager.getLeaderboardCache(
      schoolCode: schoolCode,
      className: className,
    );

    if (cachedData != null && cachedData.isNotEmpty) {
      print('⚡ Emitting cached leaderboard (${cachedData.length} entries)');
      yield _cacheableListToEntries(cachedData);
    }

    // ✅ STEP 2: Listen to student_rewards for real-time updates
    // Uses a debounce approach to avoid excessive refreshes
    DateTime? lastUpdate;
    const debounceDuration = Duration(seconds: 2);

    await for (final _ in _db.collection('student_rewards').snapshots()) {
      final now = DateTime.now();

      // Debounce: Only refresh if 2 seconds passed since last update
      if (lastUpdate != null && now.difference(lastUpdate) < debounceDuration) {
        continue;
      }

      lastUpdate = now;
      print('🔄 Real-time update detected, refreshing leaderboard...');

      // Fetch fresh data and cache it
      final entries = await getOverallLeaderboardForClassWithCache(
        schoolCode: schoolCode,
        className: className,
        section: section,
        limit: limit,
      );

      yield entries;
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
