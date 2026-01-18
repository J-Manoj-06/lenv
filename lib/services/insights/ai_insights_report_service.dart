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
              'content':
                  '''Educational analyst. Generate concise school report in this format:

Summary:
[2 sentences max]

Strengths:
- [strength 1]
- [strength 2]
- [strength 3]

Weak Areas:
- [weakness 1]
- [weakness 2]  
- [weakness 3]

Actions:
- [action 1]
- [action 2]
- [action 3]

Be specific.''',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7,
          'max_tokens': 500,
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
    return '''
School: ${metrics.schoolCode} | Last 15 days | Scope: ${metrics.scopeKey}

Data:
- Avg Score: ${metrics.avgScore.toStringAsFixed(1)}%
- Tests: ${metrics.testCount}
- Participation: ${metrics.participationAvg.toStringAsFixed(1)}%

Focus: $metricType

Provide:
1. Summary (2 sentences)
2. 3 Strengths
3. 3 Weak Areas  
4. 3 Actions

Be concise.
''';
  }

  /// Fallback report if API fails (compact version)
  String _generateFallbackReport(InsightsMetrics metrics, String metricType) {
    return '''
Summary:
Last 15 days: ${metrics.testCount} tests completed, avg ${metrics.avgScore.toStringAsFixed(1)}% performance.

Strengths:
- Performance at ${metrics.avgScore >= 75 ? 'good' : 'acceptable'} level
- ${metrics.testCount} assessments completed
- Active participation

Weak Areas:
- Need more consistent testing
- Some students below target
- Tracking improvements needed

Actions:
- Focus on struggling students
- Increase test frequency
- Monitor participation rates
''';
  }
}
