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
      final docId = cacheKey;
      final doc = await _firestore
          .collection('insights_teacher_tests')
          .doc(docId)
          .get();

      if (!doc.exists) {
        print('⚠️ No teacher tests data for $docId');
        return null;
      }

      final detail = TeacherTestsDetail.fromFirestore(doc);
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
