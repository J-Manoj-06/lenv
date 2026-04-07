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

      final doc = await _firestore
          .collection('insights_top_performers')
          .doc(docId)
          .get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data?['standards'] != null) {}

      final summary = TopPerformersSummary.fromFirestore(doc);
      _topPerformersCache[cacheKey] = summary;
      return summary;
    } catch (e) {
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
        return null;
      }

      final ranking = StandardFullRanking.fromFirestore(doc);
      _fullRankingCache[cacheKey] = ranking;
      return ranking;
    } catch (e) {
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
        return null;
      }

      final stats = TeacherStatsSummary.fromFirestore(doc);
      _teacherStatsCache[cacheKey] = stats;
      return stats;
    } catch (e) {
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

      // Get ALL completed test results for this teacher
      final testResultsSnapshot = await _firestore
          .collection('testResults')
          .where('teacherId', isEqualTo: teacherId)
          .where('schoolCode', isEqualTo: schoolCode)
          .where('status', isEqualTo: 'completed')
          .get();

      if (testResultsSnapshot.docs.isEmpty) {
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

      final now = DateTime.now();
      var cutoffDate = now.subtract(const Duration(days: 15));
      var cutoffTimestamp = Timestamp.fromDate(cutoffDate);

      // Get test results from last 15 days
      var testResultsSnapshot = await _firestore
          .collection('testResults')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: cutoffTimestamp)
          .get();

      // If no data in 15 days, try 30 days
      if (testResultsSnapshot.docs.isEmpty) {
        cutoffDate = now.subtract(const Duration(days: 30));
        cutoffTimestamp = Timestamp.fromDate(cutoffDate);

        testResultsSnapshot = await _firestore
            .collection('testResults')
            .where('schoolCode', isEqualTo: schoolCode)
            .where('status', isEqualTo: 'completed')
            .where('completedAt', isGreaterThanOrEqualTo: cutoffTimestamp)
            .get();
      }

      // If still no data, try 90 days
      if (testResultsSnapshot.docs.isEmpty) {
        cutoffDate = now.subtract(const Duration(days: 90));
        cutoffTimestamp = Timestamp.fromDate(cutoffDate);

        testResultsSnapshot = await _firestore
            .collection('testResults')
            .where('schoolCode', isEqualTo: schoolCode)
            .where('status', isEqualTo: 'completed')
            .where('completedAt', isGreaterThanOrEqualTo: cutoffTimestamp)
            .get();
      }

      if (testResultsSnapshot.docs.isEmpty) {
        return null;
      }

      // Apply scope filtering so AI analysis reflects the selected scope.
      final String? scopeStandard = scopeKey.startsWith('STD')
          ? scopeKey.substring(3).split('_').first
          : null;
      final String? scopeSection =
          (scopeKey.startsWith('STD') && scopeKey.contains('_'))
          ? scopeKey.substring(3).split('_').last.toUpperCase()
          : null;

      final filteredDocs = testResultsSnapshot.docs.where((doc) {
        if (!scopeKey.startsWith('STD')) return true;

        final data = doc.data();
        final className = data['className']?.toString() ?? '';
        final standard = _extractStandardFromClassName(className);
        final section = (data['section']?.toString() ?? '')
            .trim()
            .toUpperCase();

        if (scopeStandard != null && standard != scopeStandard) {
          return false;
        }

        if (scopeSection != null && scopeSection.isNotEmpty) {
          return section == scopeSection;
        }

        return true;
      }).toList();

      if (filteredDocs.isEmpty) {
        return null;
      }

      // Compute minimal aggregated metrics
      double totalScore = 0;
      int validScores = 0;
      Set<String> uniqueTests = {};
      final Set<String> weakStudents = {};
      final Map<String, List<double>> subjectScores = {};

      for (var doc in filteredDocs) {
        final data = doc.data();
        final score = (data['score'] as num?)?.toDouble();
        final testId = data['testId'] as String?;
        final subject = (data['subject']?.toString().trim().isNotEmpty ?? false)
            ? data['subject'].toString().trim()
            : 'General';
        final studentId =
            data['studentId']?.toString() ?? data['studentUid']?.toString();

        if (score != null && score >= 0 && score <= 100) {
          totalScore += score;
          validScores++;
          (subjectScores[subject] ??= <double>[]).add(score);
          if (score < 60 && studentId != null && studentId.isNotEmpty) {
            weakStudents.add(studentId);
          }
        }

        if (testId != null) uniqueTests.add(testId);
      }

      final avgScore = validScores > 0 ? totalScore / validScores : 0.0;
      final participation = validScores > 0
          ? (validScores.toDouble() / filteredDocs.length) * 100
          : 0.0;

      final subjectAverages = <String, double>{};
      subjectScores.forEach((subject, scores) {
        if (scores.isEmpty) return;
        final sum = scores.reduce((a, b) => a + b);
        subjectAverages[subject] = sum / scores.length;
      });

      // Create minimal metrics object
      final metrics = InsightsMetrics(
        schoolCode: schoolCode,
        range: '15d',
        scopeKey: scopeKey,
        avgScore: avgScore,
        testCount: uniqueTests.length,
        updatedAt: now,
        // Performance-only essentials for AI analysis.
        attendanceAvg: 0.0,
        participationAvg: participation,
        topImproversCount: 0,
        weakStudentsCount: weakStudents.length,
        subjectAverages: subjectAverages,
      );

      _metricsCache[cacheKey] = metrics;
      return metrics;
    } catch (e) {
      return null;
    }
  }

  String _extractStandardFromClassName(String className) {
    if (className.trim().isEmpty) return '';
    final match = RegExp(r'\d+').firstMatch(className);
    return match?.group(0) ?? '';
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
        return null;
      }

      final report = AIInsightsReport.fromFirestore(doc);

      // Check if fresh
      if (!report.isFresh) {
        return null;
      }

      _aiReportCache[cacheKey] = report;
      return report;
    } catch (e) {
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
    } catch (e) {}
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
