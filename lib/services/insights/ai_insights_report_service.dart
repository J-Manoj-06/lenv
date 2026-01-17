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
            {
              'role': 'system',
              'content': '''You are an educational data analyst. 
Generate a structured school insights report with exactly this format:

Summary:
[2-3 sentences overview]

Strengths:
- [strength 1]
- [strength 2]
- [strength 3]

Weak Areas:
- [weakness 1]
- [weakness 2]
- [weakness 3]

Recommended Actions:
- [action 1]
- [action 2]
- [action 3]

Be specific and actionable. Use the metrics provided.''',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7,
          'max_tokens': 800,
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

  /// Build AI prompt from metrics
  String _buildPrompt(InsightsMetrics metrics, String metricType) {
    return '''
Analyze this school data for ${metrics.scopeKey} over ${metrics.range}:

Metrics:
${metrics.toAIPromptJson()}

Focus Area: $metricType

Generate a structured report with:
1. Summary (2-3 sentences)
2. Top 3 Strengths
3. Top 3 Weak Areas
4. Top 3 Recommended Actions

Be specific and actionable.
''';
  }

  /// Fallback report if API fails
  String _generateFallbackReport(InsightsMetrics metrics, String metricType) {
    final scope = metrics.scopeKey == 'school' ? 'School' : 'Selected scope';

    return '''
Summary:
$scope shows an average score of ${metrics.avgScore.toStringAsFixed(1)}% with ${metrics.testCount} tests conducted in the ${metrics.range} period. Attendance average is ${metrics.attendanceAvg.toStringAsFixed(1)}%.

Strengths:
- Overall performance is ${metrics.avgScore >= 75 ? 'above' : 'near'} acceptable levels
- ${metrics.topImproversCount} students showing improvement
- Test participation rate is ${metrics.participationAvg.toStringAsFixed(1)}%

Weak Areas:
- ${metrics.weakStudentsCount} students need additional support
- Some subjects showing below-average performance
- Attendance could be improved in certain areas

Recommended Actions:
- Implement targeted intervention for struggling students
- Conduct subject-specific remedial sessions
- Monitor and encourage consistent attendance
''';
  }
}
