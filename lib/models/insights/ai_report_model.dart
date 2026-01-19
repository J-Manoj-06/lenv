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
    // Clean response - remove markdown formatting
    String cleanText = aiResponseText
        .replaceAll('**', '')
        .replaceAll('###', '')
        .replaceAll('##', '')
        .replaceAll('#', '');

    final lines = cleanText.split('\n');
    String summary = '';
    final strengths = <String>[];
    final weakAreas = <String>[];
    final suggestedActions = <String>[];

    String currentSection = '';
    bool summaryStarted = false;

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Detect sections
      final lowerLine = trimmed.toLowerCase();
      if (lowerLine.startsWith('summary:')) {
        currentSection = 'summary';
        summaryStarted = false;
        // Check if summary is on same line
        final afterColon = trimmed.substring(trimmed.indexOf(':') + 1).trim();
        if (afterColon.isNotEmpty) {
          summary = afterColon;
          summaryStarted = true;
        }
        continue;
      } else if (lowerLine.contains('strength')) {
        currentSection = 'strengths';
        continue;
      } else if (lowerLine.contains('weak')) {
        currentSection = 'weakAreas';
        continue;
      } else if (lowerLine.contains('action') ||
          lowerLine.contains('recommendation')) {
        currentSection = 'suggestedActions';
        continue;
      }

      // Parse content based on section
      if (currentSection == 'summary' && !summaryStarted) {
        summary = trimmed;
        summaryStarted = true;
      } else if (currentSection == 'strengths') {
        final cleaned = _extractBulletPoint(trimmed);
        if (cleaned.isNotEmpty) strengths.add(cleaned);
      } else if (currentSection == 'weakAreas') {
        final cleaned = _extractBulletPoint(trimmed);
        if (cleaned.isNotEmpty) weakAreas.add(cleaned);
      } else if (currentSection == 'suggestedActions') {
        final cleaned = _extractBulletPoint(trimmed);
        if (cleaned.isNotEmpty) suggestedActions.add(cleaned);
      }
    }

    // Fallback if parsing fails
    if (summary.isEmpty) {
      summary = 'Analysis completed for ${metric.toLowerCase()}';
    }
    if (strengths.isEmpty) strengths.add('Data analysis in progress');
    if (weakAreas.isEmpty) weakAreas.add('Review pending');
    if (suggestedActions.isEmpty) {
      suggestedActions.add('Recommendations will be provided');
    }

    return AIInsightsReport(
      reportId: reportId,
      schoolCode: schoolCode,
      range: range,
      scopeKey: scopeKey,
      metric: metric,
      summary: summary.trim(),
      strengths: strengths.take(3).toList(),
      weakAreas: weakAreas.take(3).toList(),
      suggestedActions: suggestedActions.take(3).toList(),
      generatedAt: DateTime.now(),
    );
  }

  /// Extract bullet point content, handling -, •, *, or numbered lists
  static String _extractBulletPoint(String line) {
    final trimmed = line.trim();
    // Handle numbered lists: "1.", "2.", etc.
    final numMatch = RegExp(r'^\d+\.\s*(.*)').firstMatch(trimmed);
    if (numMatch != null) {
      return numMatch.group(1)?.trim() ?? '';
    }
    // Handle bullet points: -, •, *
    if (trimmed.startsWith('-') ||
        trimmed.startsWith('•') ||
        trimmed.startsWith('*')) {
      return trimmed.substring(1).trim();
    }
    return '';
  }
}
