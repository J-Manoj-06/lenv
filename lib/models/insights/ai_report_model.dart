import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for AI-generated insights report
class AIInsightsReport {
  final String reportId;
  final String schoolCode;
  final String range;
  final String scopeKey;
  final String metric;
  final String summary;
  final List<String> strengths;
  final List<String> weakAreas;
  final List<String> suggestedActions;
  final DateTime generatedAt;

  AIInsightsReport({
    required this.reportId,
    required this.schoolCode,
    required this.range,
    required this.scopeKey,
    required this.metric,
    required this.summary,
    required this.strengths,
    required this.weakAreas,
    required this.suggestedActions,
    required this.generatedAt,
  });

  factory AIInsightsReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return AIInsightsReport(
      reportId: doc.id,
      schoolCode: data['schoolCode'] as String? ?? '',
      range: data['range'] as String? ?? '7d',
      scopeKey: data['scopeKey'] as String? ?? 'school',
      metric: data['metric'] as String? ?? 'Performance',
      summary: data['summary'] as String? ?? '',
      strengths: List<String>.from(data['strengths'] as List? ?? []),
      weakAreas: List<String>.from(data['weakAreas'] as List? ?? []),
      suggestedActions: List<String>.from(
        data['suggestedActions'] as List? ?? [],
      ),
      generatedAt:
          (data['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schoolCode': schoolCode,
      'range': range,
      'scopeKey': scopeKey,
      'metric': metric,
      'summary': summary,
      'strengths': strengths,
      'weakAreas': weakAreas,
      'suggestedActions': suggestedActions,
      'generatedAt': Timestamp.fromDate(generatedAt),
    };
  }

  /// Check if report is still fresh (less than 6 hours old)
  bool get isFresh {
    final now = DateTime.now();
    final diff = now.difference(generatedAt);
    return diff.inHours < 6;
  }

  /// Parse AI response text into structured report
  factory AIInsightsReport.fromAIResponse({
    required String reportId,
    required String schoolCode,
    required String range,
    required String scopeKey,
    required String metric,
    required String aiResponseText,
  }) {
    // Parse AI response (assumes structured format)
    final lines = aiResponseText.split('\n');
    String summary = '';
    final strengths = <String>[];
    final weakAreas = <String>[];
    final suggestedActions = <String>[];

    String currentSection = '';
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.toLowerCase().contains('summary:')) {
        currentSection = 'summary';
        continue;
      } else if (trimmed.toLowerCase().contains('strength')) {
        currentSection = 'strengths';
        continue;
      } else if (trimmed.toLowerCase().contains('weak')) {
        currentSection = 'weakAreas';
        continue;
      } else if (trimmed.toLowerCase().contains('action') ||
          trimmed.toLowerCase().contains('recommendation')) {
        currentSection = 'suggestedActions';
        continue;
      }

      if (currentSection == 'summary') {
        summary += '$trimmed ';
      } else if (currentSection == 'strengths' &&
          (trimmed.startsWith('-') ||
              trimmed.startsWith('•') ||
              trimmed.startsWith('*'))) {
        strengths.add(trimmed.substring(1).trim());
      } else if (currentSection == 'weakAreas' &&
          (trimmed.startsWith('-') ||
              trimmed.startsWith('•') ||
              trimmed.startsWith('*'))) {
        weakAreas.add(trimmed.substring(1).trim());
      } else if (currentSection == 'suggestedActions' &&
          (trimmed.startsWith('-') ||
              trimmed.startsWith('•') ||
              trimmed.startsWith('*'))) {
        suggestedActions.add(trimmed.substring(1).trim());
      }
    }

    // Fallback if parsing fails
    if (summary.isEmpty) {
      summary = aiResponseText.substring(
        0,
        aiResponseText.length > 200 ? 200 : aiResponseText.length,
      );
    }

    return AIInsightsReport(
      reportId: reportId,
      schoolCode: schoolCode,
      range: range,
      scopeKey: scopeKey,
      metric: metric,
      summary: summary.trim(),
      strengths: strengths.isNotEmpty ? strengths : ['Analysis in progress'],
      weakAreas: weakAreas.isNotEmpty ? weakAreas : ['Analysis in progress'],
      suggestedActions: suggestedActions.isNotEmpty
          ? suggestedActions
          : ['Recommendations being generated'],
      generatedAt: DateTime.now(),
    );
  }
}
