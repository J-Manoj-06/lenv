import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/insights/top_performer_model.dart';
import '../../models/insights/teacher_stats_model.dart';
import '../../models/insights/insights_metrics_model.dart';
import '../../models/insights/ai_report_model.dart';

/// Repository for fetching insights data from cached Firestore documents
/// Optimized to minimize Firebase reads by using aggregated documents
class InsightsRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache in memory to avoid repeated reads during session
  final Map<String, TopPerformersSummary> _topPerformersCache = {};
  final Map<String, TeacherStatsSummary> _teacherStatsCache = {};
  final Map<String, StandardFullRanking> _fullRankingCache = {};
  final Map<String, TeacherTestsDetail> _teacherTestsCache = {};
  final Map<String, InsightsMetrics> _metricsCache = {};
  final Map<String, AIInsightsReport> _aiReportCache = {};

  /// Fetch top performers summary (top 3 per standard)
  Future<TopPerformersSummary?> getTopPerformersSummary({
    required String schoolCode,
    required String range,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_$range';

    // Return cached if available and not forcing refresh
    if (!forceRefresh && _topPerformersCache.containsKey(cacheKey)) {
      return _topPerformersCache[cacheKey];
    }

    try {
      final docId = cacheKey;
      print('🔍 DEBUG: Querying insights_top_performers for docId: "$docId"');

      final doc = await _firestore
          .collection('insights_top_performers')
          .doc(docId)
          .get();

      if (!doc.exists) {
        print('⚠️ No top performers data for $docId');
        print('📋 Document does not exist in Firestore');
        return null;
      }

      print('✅ Found top performers data: ${doc.data()?.keys.join(', ')}');
      final data = doc.data();
      print(
        '📋 Standards array length: ${(data?['standards'] as List?)?.length ?? 0}',
      );
      if (data?['standards'] != null) {
        print('📋 Standards data: ${data!['standards']}');
      }

      final summary = TopPerformersSummary.fromFirestore(doc);
      print('📋 Parsed summary standards count: ${summary.standards.length}');
      _topPerformersCache[cacheKey] = summary;
      return summary;
    } catch (e) {
      print('❌ Error fetching top performers: $e');
      return null;
    }
  }

  /// Fetch full standard ranking (for "View More" page)
  Future<StandardFullRanking?> getStandardFullRanking({
    required String schoolCode,
    required String range,
    required String standard,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_${range}_STD$standard';

    if (!forceRefresh && _fullRankingCache.containsKey(cacheKey)) {
      return _fullRankingCache[cacheKey];
    }

    try {
      final docId = cacheKey;
      final doc = await _firestore
          .collection('insights_top_performers_full')
          .doc(docId)
          .get();

      if (!doc.exists) {
        print('⚠️ No full ranking data for $docId');
        return null;
      }

      final ranking = StandardFullRanking.fromFirestore(doc);
      _fullRankingCache[cacheKey] = ranking;
      return ranking;
    } catch (e) {
      print('❌ Error fetching full ranking: $e');
      return null;
    }
  }

  /// Fetch teacher stats summary
  Future<TeacherStatsSummary?> getTeacherStatsSummary({
    required String schoolCode,
    required String range,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_$range';

    if (!forceRefresh && _teacherStatsCache.containsKey(cacheKey)) {
      return _teacherStatsCache[cacheKey];
    }

    try {
      final docId = cacheKey;
      final doc = await _firestore
          .collection('insights_teacher_stats')
          .doc(docId)
          .get();

      if (!doc.exists) {
        print('⚠️ No teacher stats data for $docId');
        return null;
      }

      final stats = TeacherStatsSummary.fromFirestore(doc);
      _teacherStatsCache[cacheKey] = stats;
      return stats;
    } catch (e) {
      print('❌ Error fetching teacher stats: $e');
      return null;
    }
  }

  /// Fetch teacher detailed tests
  Future<TeacherTestsDetail?> getTeacherTestsDetail({
    required String schoolCode,
    required String teacherId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_alltime_$teacherId';

    if (!forceRefresh && _teacherTestsCache.containsKey(cacheKey)) {
      return _teacherTestsCache[cacheKey];
    }

    try {
      // Fetch ALL test results for this teacher (no time filtering)
      print('📊 Fetching all-time test data for teacherId: $teacherId');

      // Get ALL completed test results for this teacher
      final testResultsSnapshot = await _firestore
          .collection('testResults')
          .where('teacherId', isEqualTo: teacherId)
          .where('schoolCode', isEqualTo: schoolCode)
          .where('status', isEqualTo: 'completed')
          .get();

      print(
        '📊 Found ${testResultsSnapshot.docs.length} test results for teacherId=$teacherId',
      );

      if (testResultsSnapshot.docs.isEmpty) {
        print('⚠️ No test results data for $teacherId in testResults');
        // Return empty detail instead of null
        return TeacherTestsDetail(
          teacherId: teacherId,
          schoolCode: schoolCode,
          range: 'alltime',
          updatedAt: DateTime.now(),
          recentTests: [],
        );
      }

      // Group results by testId to get unique tests
      final Map<String, Map<String, dynamic>> uniqueTests = {};
      final Map<String, List<double>> testScores = {};

      for (var doc in testResultsSnapshot.docs) {
        final data = doc.data();
        final testId = data['testId'] as String?;
        final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

        if (testId == null || completedAt == null) continue;

        // Store test info if not already stored
        if (!uniqueTests.containsKey(testId)) {
          uniqueTests[testId] = {
            'testId': testId,
            'title': data['testTitle'] ?? data['title'] ?? 'Untitled Test',
            'className': data['className'] ?? '',
            'section': data['section'] ?? '',
            'date': completedAt,
          };
          testScores[testId] = [];
        }

        // Collect scores for average calculation
        // The 'score' field in testResults is already a percentage (0-100)
        final score = (data['score'] as num?)?.toDouble() ?? 0.0;
        testScores[testId]!.add(score);
      }

      print(
        '📊 Found ${uniqueTests.length} unique tests for teacher $teacherId',
      );

      // Build TestSummary list with average scores
      final tests = uniqueTests.values.map((testData) {
        final testId = testData['testId'] as String;
        final scores = testScores[testId] ?? [];
        final avgScore = scores.isEmpty
            ? 0.0
            : scores.reduce((a, b) => a + b) / scores.length;

        return TestSummary(
          testId: testId,
          title: testData['title'] as String,
          standard: testData['className'] as String,
          section: testData['section'] as String,
          avgScore: avgScore,
          date: testData['date'] as DateTime,
        );
      }).toList();

      // Sort by date (newest first)
      tests.sort((a, b) => b.date.compareTo(a.date));

      // Create a basic TeacherTestsDetail from computed data
      final detail = TeacherTestsDetail(
        teacherId: teacherId,
        schoolCode: schoolCode,
        range: 'alltime',
        updatedAt: DateTime.now(),
        recentTests: tests,
      );

      _teacherTestsCache[cacheKey] = detail;
      return detail;
    } catch (e) {
      print('❌ Error fetching teacher tests: $e');
      return null;
    }
  }

  /// Fetch aggregated metrics for AI analysis (last 15 days only, minimal data)
  Future<InsightsMetrics?> getInsightsMetrics({
    required String schoolCode,
    required String range,
    required String scopeKey,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_15d_$scopeKey';

    if (!forceRefresh && _metricsCache.containsKey(cacheKey)) {
      return _metricsCache[cacheKey];
    }

    try {
      // Instead of pre-aggregated data, compute minimal metrics from last 15 days
      print(
        '📊 Computing minimal metrics from last 15 days for AI analysis...',
      );

      final now = DateTime.now();
      final cutoffDate = now.subtract(const Duration(days: 15));
      final cutoffTimestamp = Timestamp.fromDate(cutoffDate);

      // Get test results from last 15 days only
      final testResultsSnapshot = await _firestore
          .collection('testResults')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: cutoffTimestamp)
          .get();

      if (testResultsSnapshot.docs.isEmpty) {
        print('⚠️ No test data in last 15 days for $schoolCode');
        return null;
      }

      // Compute minimal aggregated metrics
      double totalScore = 0;
      int validScores = 0;
      Set<String> uniqueTests = {};

      for (var doc in testResultsSnapshot.docs) {
        final data = doc.data();
        final score = (data['score'] as num?)?.toDouble();
        final testId = data['testId'] as String?;

        if (score != null && score >= 0 && score <= 100) {
          totalScore += score;
          validScores++;
        }

        if (testId != null) uniqueTests.add(testId);
      }

      final avgScore = validScores > 0 ? totalScore / validScores : 0.0;
      final participation = validScores > 0
          ? (validScores.toDouble() / testResultsSnapshot.docs.length) * 100
          : 0.0;

      // Create minimal metrics object
      final metrics = InsightsMetrics(
        schoolCode: schoolCode,
        range: '15d',
        scopeKey: scopeKey,
        avgScore: avgScore,
        testCount: uniqueTests.length,
        updatedAt: now,
        // Minimal data - only essentials
        attendanceAvg: 0.0,
        participationAvg: participation,
        topImproversCount: 0,
        weakStudentsCount: 0,
        subjectAverages: {},
      );

      _metricsCache[cacheKey] = metrics;
      print(
        '✅ Computed metrics: ${uniqueTests.length} tests, avg ${avgScore.toStringAsFixed(1)}%',
      );
      return metrics;
    } catch (e) {
      print('❌ Error computing metrics: $e');
      return null;
    }
  }

  /// Fetch cached AI report
  Future<AIInsightsReport?> getCachedAIReport({
    required String schoolCode,
    required String range,
    required String scopeKey,
    required String metric,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_${range}_${scopeKey}_$metric';

    if (!forceRefresh && _aiReportCache.containsKey(cacheKey)) {
      final cached = _aiReportCache[cacheKey]!;
      // Check if still fresh (< 6 hours)
      if (cached.isFresh) {
        return cached;
      }
    }

    try {
      final docId = cacheKey;
      final doc = await _firestore.collection('ai_reports').doc(docId).get();

      if (!doc.exists) {
        print('⚠️ No cached AI report for $docId');
        return null;
      }

      final report = AIInsightsReport.fromFirestore(doc);

      // Check if fresh
      if (!report.isFresh) {
        print('⏰ Cached report is stale, needs regeneration');
        return null;
      }

      _aiReportCache[cacheKey] = report;
      return report;
    } catch (e) {
      print('❌ Error fetching AI report: $e');
      return null;
    }
  }

  /// Save AI report to Firestore cache
  Future<void> saveAIReport(AIInsightsReport report) async {
    try {
      final docId =
          '${report.schoolCode}_${report.range}_${report.scopeKey}_${report.metric}';
      await _firestore.collection('ai_reports').doc(docId).set(report.toJson());

      // Update memory cache
      _aiReportCache[docId] = report;

      print('✅ AI report saved: $docId');
    } catch (e) {
      print('❌ Error saving AI report: $e');
    }
  }

  /// Clear all caches (useful for force refresh)
  void clearCaches() {
    _topPerformersCache.clear();
    _teacherStatsCache.clear();
    _fullRankingCache.clear();
    _teacherTestsCache.clear();
    _metricsCache.clear();
    _aiReportCache.clear();
  }
}
