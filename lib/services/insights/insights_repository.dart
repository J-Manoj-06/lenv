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
    required String range,
    required String teacherId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_${range}_$teacherId';

    if (!forceRefresh && _teacherTestsCache.containsKey(cacheKey)) {
      return _teacherTestsCache[cacheKey];
    }

    try {
      // First try to get from pre-computed insights collection
      final docId = cacheKey;
      final doc = await _firestore
          .collection('insights_teacher_tests')
          .doc(docId)
          .get();

      if (doc.exists) {
        final detail = TeacherTestsDetail.fromFirestore(doc);
        _teacherTestsCache[cacheKey] = detail;
        return detail;
      }

      // If not found, compute from testResults collection (where actual test data is)
      print(
        '⚠️ No pre-computed data for $docId, fetching from testResults...',
      );

      // Calculate date range for the query
      final now = DateTime.now();
      DateTime cutoffDate;
      if (range == '7d') {
        cutoffDate = now.subtract(const Duration(days: 7));
      } else if (range == '30d') {
        cutoffDate = now.subtract(const Duration(days: 30));
      } else {
        // monthly - go back 30 days
        cutoffDate = now.subtract(const Duration(days: 30));
      }

      // Get completed test results for this teacher
      final testResultsSnapshot = await _firestore
          .collection('testResults')
          .where('teacherId', isEqualTo: teacherId)
          .where('schoolCode', isEqualTo: schoolCode)
          .where('status', isEqualTo: 'completed')
          .get();

      print(
        '📊 Found ${testResultsSnapshot.docs.length} test results with teacherId=$teacherId',
      );

      if (testResultsSnapshot.docs.isEmpty) {
        print('⚠️ No test results data for $teacherId in testResults');
        // Return empty detail instead of null
        return TeacherTestsDetail(
          teacherId: teacherId,
          schoolCode: schoolCode,
          range: range,
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
        
        // Filter by date range
        if (completedAt.isBefore(cutoffDate)) continue;

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
        final score = (data['score'] as num?)?.toDouble() ?? 0.0;
        final totalMarks = (data['totalMarks'] as num?)?.toDouble() ?? 1.0;
        if (totalMarks > 0) {
          final percentage = (score / totalMarks) * 100;
          testScores[testId]!.add(percentage);
        }
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
        range: range,
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

  /// Fetch aggregated metrics for AI analysis
  Future<InsightsMetrics?> getInsightsMetrics({
    required String schoolCode,
    required String range,
    required String scopeKey,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${schoolCode}_${range}_$scopeKey';

    if (!forceRefresh && _metricsCache.containsKey(cacheKey)) {
      return _metricsCache[cacheKey];
    }

    try {
      final docId = cacheKey;
      final doc = await _firestore
          .collection('insights_metrics')
          .doc(docId)
          .get();

      if (!doc.exists) {
        print('⚠️ No metrics data for $docId');
        return null;
      }

      final metrics = InsightsMetrics.fromFirestore(doc);
      _metricsCache[cacheKey] = metrics;
      return metrics;
    } catch (e) {
      print('❌ Error fetching metrics: $e');
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
