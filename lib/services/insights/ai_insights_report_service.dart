import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/insights/ai_report_model.dart';
import '../../models/insights/insights_metrics_model.dart';
import './insights_repository.dart';

/// Service for generating AI-powered insights reports
/// Uses existing DeepSeek API to generate structured analysis
class AIInsightsReportService {
  static const String _apiUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const String _apiKey = 'sk-ecd0161142054f39bb8b2d40545232c1';

  final InsightsRepository _repository = InsightsRepository();

  /// Generate or fetch cached AI report
  Future<AIInsightsReport?> generateReport({
    required String schoolCode,
    required String range,
    required String scopeKey,
    required String metric,
  }) async {
    // First, check if cached report exists and is fresh
    final cached = await _repository.getCachedAIReport(
      schoolCode: schoolCode,
      range: range,
      scopeKey: scopeKey,
      metric: metric,
    );

    if (cached != null && cached.isFresh) {
      print('✅ Using cached AI report');
      return cached;
    }

    print('🤖 Generating new AI report...');

    // Fetch metrics data
    final metrics = await _repository.getInsightsMetrics(
      schoolCode: schoolCode,
      range: range,
      scopeKey: scopeKey,
    );

    if (metrics == null) {
      print('❌ No metrics data available for AI analysis');
      return null;
    }

    // Generate new report using AI
    final aiResponse = await _callDeepSeekAPI(metrics, metric);

    if (aiResponse == null) {
      print('❌ Failed to generate AI report');
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

  /// Call DeepSeek API with structured prompt
  Future<String?> _callDeepSeekAPI(
    InsightsMetrics metrics,
    String metricType,
  ) async {
    if (_apiKey.isEmpty || _apiKey == 'YOUR_DEEPSEEK_API_KEY') {
      print('⚠️ DeepSeek API key not configured');
      return _generateFallbackReport(metrics, metricType);
    }

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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'] ?? '';
        return content;
      } else {
        print('❌ DeepSeek API error: ${response.statusCode}');
        return _generateFallbackReport(metrics, metricType);
      }
    } catch (e) {
      print('❌ Error calling DeepSeek API: $e');
      return _generateFallbackReport(metrics, metricType);
    }
  }

  /// Build AI prompt from metrics (compact format to reduce tokens)
  String _buildPrompt(InsightsMetrics metrics, String metricType) {
    // Customize prompt based on metric type - STRICTLY separate
    if (metricType == 'Attendance') {
      return '''15-day attendance analysis for ${metrics.scopeKey}:

Attendance Rate: ${metrics.attendanceAvg.toStringAsFixed(0)}%
Students needing attention: ${metrics.weakStudentsCount}
Tracking sessions: ${metrics.testCount}

Analyze attendance patterns only. Focus on presence/absence trends, regularity, and student engagement in attending school. Do not discuss test scores or academic performance.''';
    } else {
      // Performance metric - DO NOT include attendance
      return '''15-day academic performance for ${metrics.scopeKey}:

Average Score: ${metrics.avgScore.toStringAsFixed(0)}%
Tests Conducted: ${metrics.testCount}
Student Participation: ${metrics.participationAvg.toStringAsFixed(0)}%
Weak Performers: ${metrics.weakStudentsCount}

Analyze test performance and academic results only. Focus on scores, understanding, and learning outcomes. Do not discuss attendance.''';
    }
  }

  /// Fallback report if API fails (compact version)
  String _generateFallbackReport(InsightsMetrics metrics, String metricType) {
    if (metricType == 'Attendance') {
      return '''
Summary:
Attendance rate is ${metrics.attendanceAvg.toStringAsFixed(0)}% over 15 days.

Strengths:
- Regular attendance tracking maintained
- ${metrics.testCount} sessions monitored
- System captures daily presence

Weak Areas:
- ${metrics.attendanceAvg.toStringAsFixed(0)}% rate needs improvement
- ${metrics.weakStudentsCount} students frequently absent
- Consistency gaps observed

Actions:
- Contact parents of frequent absentees
- Implement attendance rewards program
- Monitor and address absence patterns
''';
    } else {
      return '''
Summary:
Average performance is ${metrics.avgScore.toStringAsFixed(0)}% across ${metrics.testCount} assessments.

Strengths:
- ${metrics.testCount} tests completed successfully
- ${metrics.participationAvg.toStringAsFixed(0)}% student participation
- Regular assessments maintained

Weak Areas:
- Overall score at ${metrics.avgScore.toStringAsFixed(0)}% needs improvement
- ${metrics.weakStudentsCount} students below target
- Concept mastery gaps identified

Actions:
- Provide targeted tutoring for weak students
- Increase practice and revision sessions
- Focus on difficult topics and concepts
''';
    }
  }
}
