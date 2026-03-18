import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/insights/ai_report_model.dart';
import '../../models/insights/insights_metrics_model.dart';
import './insights_repository.dart';

/// Service for generating AI-powered insights reports
/// Uses Cloudflare Worker to securely access DeepSeek API
class AIInsightsReportService {
  /// Cloudflare Worker endpoint - API key is secured on the server
  static const String _workerUrl =
      'https://deepseek-ai-worker.giridharannj.workers.dev/chat';

  final InsightsRepository _repository = InsightsRepository();

  /// Generate or fetch cached AI report
  Future<AIInsightsReport?> generateReport({
    required String schoolCode,
    required String range,
    required String scopeKey,
    required String metric,
  }) async {
    // Force refresh to always get latest data

    // Fetch metrics data with force refresh
    final metrics = await _repository.getInsightsMetrics(
      schoolCode: schoolCode,
      range: range,
      scopeKey: scopeKey,
      forceRefresh: true,
    );

    if (metrics == null) {
      // Create a fallback report with no-data message
      final fallbackResponse = _generateNoDataReport(metric);

      final reportId = '${schoolCode}_${range}_${scopeKey}_$metric';
      final report = AIInsightsReport.fromAIResponse(
        reportId: reportId,
        schoolCode: schoolCode,
        range: range,
        scopeKey: scopeKey,
        metric: metric,
        aiResponseText: fallbackResponse,
      );

      // Save fallback report
      await _repository.saveAIReport(report);
      return report;
    }

    // Generate new report using AI
    final aiResponse = await _callDeepSeekAPI(metrics, metric);

    if (aiResponse == null) {
      return null;
    }

    // Parse response into structured report
    final reportId = '${schoolCode}_${range}_${scopeKey}_$metric';
    final report = AIInsightsReport.fromAIResponse(
      reportId: reportId,
      schoolCode: schoolCode,
      range: range,
      scopeKey: scopeKey,
      metric: metric,
      aiResponseText: aiResponse,
    );

    // Save to Firestore cache
    await _repository.saveAIReport(report);

    return report;
  }

  /// Call DeepSeek API via Cloudflare Worker (secure)
  Future<String?> _callDeepSeekAPI(
    InsightsMetrics metrics,
    String metricType,
  ) async {
    final prompt = _buildPrompt(metrics, metricType);

    // Metric-specific system prompts
    String systemPrompt;
    if (metricType == 'Attendance') {
      systemPrompt =
          'Attendance analyst. Analyze ONLY attendance data. Do NOT mention performance, scores, or test results. Reply format:\n\nSummary:\n[One line about attendance]\n\nStrengths:\n- [attendance strength 1]\n- [attendance strength 2]\n- [attendance strength 3]\n\nWeak Areas:\n- [attendance weakness 1]\n- [attendance weakness 2]\n- [attendance weakness 3]\n\nActions:\n- [attendance action 1]\n- [attendance action 2]\n- [attendance action 3]';
    } else {
      systemPrompt =
          'Performance analyst. Analyze ONLY test scores and performance. Do NOT mention attendance. Reply format:\n\nSummary:\n[One line about performance]\n\nStrengths:\n- [performance strength 1]\n- [performance strength 2]\n- [performance strength 3]\n\nWeak Areas:\n- [performance weakness 1]\n- [performance weakness 2]\n- [performance weakness 3]\n\nActions:\n- [performance action 1]\n- [performance action 2]\n- [performance action 3]';
    }

    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7,
          'max_tokens': 300,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] ?? '';
        return content;
      } else {
        // Use fallback if API fails
        return _generateFallbackReport(metrics, metricType);
      }
    } catch (e) {
      // Use fallback if request fails
      return _generateFallbackReport(metrics, metricType);
    }
  }

  /// Build AI prompt from metrics (compact format to reduce tokens)
  String _buildPrompt(InsightsMetrics metrics, String metricType) {
    // Customize prompt based on metric type - STRICTLY separate
    if (metricType == 'Attendance') {
      return '''School: ${metrics.schoolCode}
Scope: ${metrics.scopeKey}
Analysis Period: Last ${metrics.range == '15d' ? '15 days' : metrics.range}

ATTENDANCE DATA ONLY:
- Overall Attendance Rate: ${metrics.attendanceAvg.toStringAsFixed(1)}%
- Days Monitored: ${metrics.testCount}

Analyze ONLY attendance patterns. Focus on:
1. Is ${metrics.attendanceAvg.toStringAsFixed(0)}% attendance rate acceptable?
2. What attendance trends should we monitor?
3. What causes low attendance?
4. Specific actions to improve attendance

IMPORTANT: Do NOT mention test scores, academic performance, grades, subjects, or student performance. Only analyze attendance.''';
    } else {
      // Performance metric - DO NOT include attendance
      return '''School: ${metrics.schoolCode}
Scope: ${metrics.scopeKey}
Analysis Period: Last ${metrics.range == '15d' ? '15 days' : metrics.range}

ACADEMIC PERFORMANCE DATA ONLY:
- Average Test Score: ${metrics.avgScore.toStringAsFixed(1)}%
- Tests Conducted: ${metrics.testCount}
- Students Below 60% (Weak): ${metrics.weakStudentsCount}

Analyze ONLY test performance and academic results. Focus on:
1. Is ${metrics.avgScore.toStringAsFixed(0)}% average score acceptable?
2. Which subject areas need improvement?
3. Why are ${metrics.weakStudentsCount} students struggling?
4. Specific academic interventions needed

IMPORTANT: Do NOT mention attendance, presence, or absences. Only analyze academic performance.''';
    }
  }

  /// Fallback report if API fails (compact version)
  String _generateFallbackReport(InsightsMetrics metrics, String metricType) {
    if (metricType == 'Attendance') {
      // Generate attendance-specific insights
      if (metrics.attendanceAvg == 0.0) {
        return '''
Summary:
Attendance data is not yet available in the system.

Strengths:
- Attendance tracking system is configured
- Data collection infrastructure is ready
- Can begin monitoring immediately

Weak Areas:
- No attendance records available for analysis
- Attendance marking has not started yet
- Unable to identify attendance patterns

Actions:
- Enable daily attendance recording in the system
- Train teachers on attendance marking procedures
- Begin collecting attendance data for analysis
''';
      }

      final rate = metrics.attendanceAvg;
      String rateAssessment = rate >= 90
          ? 'excellent'
          : rate >= 80
          ? 'good'
          : rate >= 70
          ? 'satisfactory'
          : 'needs improvement';

      return '''
Summary:
Attendance rate is ${rate.toStringAsFixed(0)}% which is $rateAssessment for ${metrics.scopeKey}.

Strengths:
- ${rate >= 80 ? 'Strong attendance culture established' : 'Attendance tracking is active'}
- ${metrics.testCount} days monitored for attendance
- System captures daily presence accurately

Weak Areas:
- ${rate < 90 ? '${(90 - rate).toStringAsFixed(0)}% improvement needed to reach 90% target' : 'Minor fluctuations in regularity'}
- ${rate < 75 ? 'Many students frequently absent' : 'Some students have irregular attendance'}
- ${rate < 75 ? 'Critical attendance issues requiring immediate action' : 'Consistency can be improved'}

Actions:
- ${rate < 80 ? 'Immediate parent-teacher meetings for chronic absentees' : 'Continue monitoring attendance patterns'}
- ${rate < 85 ? 'Implement attendance incentive program' : 'Recognize students with perfect attendance'}
- ${rate < 90 ? 'Address systemic barriers to attendance (transport, health, etc.)' : 'Maintain current best practices'}
''';
    } else {
      // Generate performance-specific insights
      final score = metrics.avgScore;
      String performanceLevel = score >= 85
          ? 'excellent'
          : score >= 75
          ? 'good'
          : score >= 60
          ? 'satisfactory'
          : 'needs significant improvement';

      return '''
Summary:
Average academic performance is ${score.toStringAsFixed(0)}% which is $performanceLevel across ${metrics.testCount} assessments for ${metrics.scopeKey}.

Strengths:
- ${metrics.testCount} tests successfully conducted and evaluated
- ${score >= 75 ? 'Strong academic foundation demonstrated' : 'Regular assessment system is active'}
- ${score >= 70 ? 'Majority of students meeting basic learning outcomes' : 'Assessment data available for intervention'}

Weak Areas:
- ${score < 85 ? 'Overall score at ${score.toStringAsFixed(0)}% falls short of 85% excellence target' : 'Minor improvements needed in advanced concepts'}
- ${metrics.weakStudentsCount > 0 ? '${metrics.weakStudentsCount} students scoring below 60% need urgent support' : 'Some students need targeted academic support'}
- ${score < 70 ? 'Critical performance gaps requiring immediate academic intervention' : 'Concept mastery can be strengthened'}

Actions:
- ${score < 70
          ? 'Launch urgent remedial classes for struggling students'
          : score < 80
          ? 'Provide targeted tutoring for weak subject areas'
          : 'Focus on advanced topics and academic enrichment'}
- ${metrics.testCount < 5 ? 'Conduct more assessments to better track academic progress' : 'Analyze test patterns to identify specific weak topics and concepts'}
- ${score < 75 ? 'Implement peer learning and study groups for academic improvement' : 'Continue current teaching strategies with minor adjustments'}
''';
    }
  }

  /// Generate a no-data report when there's insufficient data
  String _generateNoDataReport(String metricType) {
    if (metricType == 'Attendance') {
      return '''
Summary:
No attendance data available for the last 15 days.

Strengths:
- System is ready to track attendance
- Data collection can begin immediately
- Attendance monitoring is enabled

Weak Areas:
- No attendance records in past 15 days
- Unable to identify patterns yet
- Insufficient data for analysis

Actions:
- Ensure teachers are recording daily attendance
- Check that attendance data is being synced to the system
- Wait for 3-5 days of data before running analysis again
''';
    } else {
      return '''
Summary:
No test data available for the last 15 days.

Strengths:
- System is ready for test assessments
- Infrastructure is in place for performance tracking
- Analytics dashboard is configured

Weak Areas:
- No tests have been conducted recently
- Unable to generate performance insights
- Insufficient data for pattern analysis

Actions:
- Create and assign tests to students
- Conduct classroom assessments and upload results
- Allow 3-5 days of testing activity before rerunning analysis
''';
    }
  }
}
