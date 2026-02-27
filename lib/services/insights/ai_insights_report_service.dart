import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/insights/ai_report_model.dart';
import '../../models/insights/insights_metrics_model.dart';
import './insights_repository.dart';

/// Service for generating AI-powered insights reports
/// Uses Cloudflare Worker to securely access DeepSeek API
class AIInsightsReportService {
  /// Cloudflare Worker endpoint - API key is secured on the server
  static const String _workerUrl = 'https://deepseek-ai-worker.giridharannj.workers.dev/chat';

  final InsightsRepository _repository = InsightsRepository();

  /// Generate or fetch cached AI report
  Future<AIInsightsReport?> generateReport({
    required String schoolCode,
    required String range,
    required String scopeKey,
    required String metric,
  }) async {
    // Force refresh to always get latest data
    print('🤖 Generating new AI report (force refresh)...');

    // Fetch metrics data with force refresh
    final metrics = await _repository.getInsightsMetrics(
      schoolCode: schoolCode,
      range: range,
      scopeKey: scopeKey,
      forceRefresh: true,
    );

    if (metrics == null) {
      print('⚠️ No metrics data available for AI analysis - using fallback report');
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

    print('📊 Metrics received: avgScore=${metrics.avgScore.toStringAsFixed(1)}%, testCount=${metrics.testCount}');

    // Generate new report using AI
    final aiResponse = await _callDeepSeekAPI(metrics, metric);

    if (aiResponse == null) {
      print('❌ Failed to generate AI report');
      return null;
    }

    print('✅ AI Response received: ${aiResponse.length} characters');

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

  /// Call DeepSeek API with structured prompt
  Future<String?> _callDeepSeekAPI(
    InsightsMetrics metrics,
    String metricType,
  ) async {
    if (_apiKey.isEmpty || _apiKey == 'YOUR_DEEPSEEK_API_KEY') {
      print('⚠️ DeepSeek API key not configured - using fallback');
      return _generateFallbackReport(metrics, metricType);
    }

    final prompt = _buildPrompt(metrics, metricType);
    print('📝 Sending prompt to AI with data: $prompt');

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
      print('🔄 Calling DeepSeek API...');
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
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

      print('📡 API Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] ?? '';
        print('✅ AI generated report (${content.length} chars)');
        return content;
      } else {
        print('❌ DeepSeek API error: ${response.statusCode}');
        print('📋 Response: ${response.body}');
        // Use fallback if API fails
        return _generateFallbackReport(metrics, metricType);
      }
    } catch (e) {
      print('❌ Error calling DeepSeek API: $e');
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

ATTENDANCE DATA:
- Overall Attendance Rate: ${metrics.attendanceAvg.toStringAsFixed(1)}%
- Sessions Monitored: ${metrics.testCount}
- Students with Weak Attendance: ${metrics.weakStudentsCount}
- Average Participation: ${metrics.participationAvg.toStringAsFixed(1)}%

Analyze attendance patterns only. Focus on:
1. Why attendance rate is at ${metrics.attendanceAvg.toStringAsFixed(0)}%
2. Patterns and trends in attendance
3. Impact of low attendance on student engagement
4. Specific actions to improve attendance

Do NOT mention test scores or academic performance.''';
    } else {
      // Performance metric - DO NOT include attendance
      return '''School: ${metrics.schoolCode}
Scope: ${metrics.scopeKey}
Analysis Period: Last ${metrics.range == '15d' ? '15 days' : metrics.range}

PERFORMANCE DATA:
- Average Test Score: ${metrics.avgScore.toStringAsFixed(1)}%
- Tests Conducted: ${metrics.testCount}
- Student Participation Rate: ${metrics.participationAvg.toStringAsFixed(1)}%
- Students Performing Below Target: ${metrics.weakStudentsCount}

Analyze test performance and academic results. Focus on:
1. Why average score is ${metrics.avgScore.toStringAsFixed(0)}%
2. Subject-wise or topic-wise performance patterns
3. Reasons for weak performance in low-scoring areas
4. Specific interventions to improve performance

Do NOT mention attendance or other metrics.''';
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
- ${metrics.testCount} tests have been conducted
- ${metrics.participationAvg.toStringAsFixed(0)}% student participation in assessments
- Academic activities are being tracked

Weak Areas:
- Attendance tracking needs to be enabled
- No attendance records available for analysis
- System requires attendance data integration

Actions:
- Enable daily attendance recording in the system
- Train teachers on attendance marking procedures
- Start collecting attendance data for meaningful insights
''';
      }
      
      final rate = metrics.attendanceAvg;
      String rateAssessment = rate >= 90 ? 'excellent' : rate >= 80 ? 'good' : rate >= 70 ? 'satisfactory' : 'needs improvement';
      
      return '''
Summary:
Attendance rate is ${rate.toStringAsFixed(0)}% which is $rateAssessment for ${metrics.scopeKey}.

Strengths:
- ${rate >= 80 ? 'Strong attendance culture established' : 'Attendance tracking is active'}
- ${metrics.testCount} sessions monitored consistently
- System captures daily presence accurately

Weak Areas:
- ${rate < 90 ? '${(90 - rate).toStringAsFixed(0)}% improvement needed to reach 90% target' : 'Minor fluctuations in regularity'}
- ${metrics.weakStudentsCount > 0 ? '${metrics.weakStudentsCount} students frequently absent' : 'Some students need attention'}
- ${rate < 75 ? 'Critical attendance issues requiring immediate action' : 'Consistency can be improved'}

Actions:
- ${rate < 80 ? 'Immediate parent-teacher meetings for chronic absentees' : 'Continue monitoring attendance patterns'}
- ${rate < 85 ? 'Implement attendance incentive program' : 'Recognize students with perfect attendance'}
- ${rate < 90 ? 'Address systemic barriers to attendance' : 'Maintain current best practices'}
''';
    } else {
      // Generate performance-specific insights
      final score = metrics.avgScore;
      String performanceLevel = score >= 85 ? 'excellent' : score >= 75 ? 'good' : score >= 60 ? 'satisfactory' : 'needs significant improvement';
      
      return '''
Summary:
Average performance is ${score.toStringAsFixed(0)}% which is $performanceLevel across ${metrics.testCount} assessments for ${metrics.scopeKey}.

Strengths:
- ${metrics.testCount} tests successfully conducted
- ${metrics.participationAvg.toStringAsFixed(0)}% student participation shows engagement
- ${score >= 75 ? 'Strong academic foundation demonstrated' : 'Assessment system is active'}

Weak Areas:
- ${score < 85 ? 'Overall score at ${score.toStringAsFixed(0)}% falls short of 85% excellence target' : 'Minor improvements needed'}
- ${metrics.weakStudentsCount > 0 ? '${metrics.weakStudentsCount} students below passing threshold' : 'Some students need targeted support'}
- ${score < 70 ? 'Critical performance gaps requiring immediate intervention' : 'Concept mastery can be strengthened'}

Actions:
- ${score < 70 ? 'Launch urgent remedial classes for struggling students' : score < 80 ? 'Provide targeted tutoring for weak areas' : 'Focus on advanced topics and enrichment'}
- ${metrics.testCount < 5 ? 'Increase assessment frequency to track progress' : 'Analyze test patterns to identify specific weak topics'}
- ${score < 75 ? 'Implement peer learning and study groups' : 'Continue current teaching strategies with minor adjustments'}
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
