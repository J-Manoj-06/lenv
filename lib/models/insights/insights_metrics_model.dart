import 'package:cloud_firestore/cloud_firestore.dart';

/// Aggregated metrics for AI analysis
class InsightsMetrics {
  final String schoolCode;
  final String range;
  final String scopeKey; // "school", "STD10", "STD10_A"
  final DateTime updatedAt;
  final double avgScore;
  final double attendanceAvg;
  final double participationAvg;
  final Map<String, double> subjectAverages; // {"Math": 71, "Science": 69}
  final int weakStudentsCount;
  final int topImproversCount;
  final int testCount;

  InsightsMetrics({
    required this.schoolCode,
    required this.range,
    required this.scopeKey,
    required this.updatedAt,
    required this.avgScore,
    required this.attendanceAvg,
    required this.participationAvg,
    required this.subjectAverages,
    required this.weakStudentsCount,
    required this.topImproversCount,
    required this.testCount,
  });

  factory InsightsMetrics.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final subjectsData = data['subjectAverages'] as Map<String, dynamic>? ?? {};
    final subjectAverages = subjectsData.map(
      (key, value) => MapEntry(key, (value as num?)?.toDouble() ?? 0.0),
    );

    return InsightsMetrics(
      schoolCode: data['schoolCode'] as String? ?? '',
      range: data['range'] as String? ?? '7d',
      scopeKey: data['scopeKey'] as String? ?? 'school',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      avgScore: (data['avgScore'] as num?)?.toDouble() ?? 0.0,
      attendanceAvg: (data['attendanceAvg'] as num?)?.toDouble() ?? 0.0,
      participationAvg: (data['participationAvg'] as num?)?.toDouble() ?? 0.0,
      subjectAverages: subjectAverages,
      weakStudentsCount: (data['weakStudentsCount'] as num?)?.toInt() ?? 0,
      topImproversCount: (data['topImproversCount'] as num?)?.toInt() ?? 0,
      testCount: (data['testCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schoolCode': schoolCode,
      'range': range,
      'scopeKey': scopeKey,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'avgScore': avgScore,
      'attendanceAvg': attendanceAvg,
      'participationAvg': participationAvg,
      'subjectAverages': subjectAverages,
      'weakStudentsCount': weakStudentsCount,
      'topImproversCount': topImproversCount,
      'testCount': testCount,
    };
  }

  // Helper to convert metrics to JSON string for AI prompt
  String toAIPromptJson() {
    return '''
{
  "avgScore": $avgScore,
  "attendanceAvg": $attendanceAvg,
  "participationAvg": $participationAvg,
  "subjectAverages": ${_formatSubjectAverages()},
  "weakStudentsCount": $weakStudentsCount,
  "topImproversCount": $topImproversCount,
  "testCount": $testCount,
  "scope": "$scopeKey",
  "timeRange": "$range"
}
''';
  }

  String _formatSubjectAverages() {
    final entries = subjectAverages.entries
        .map((e) => '"${e.key}": ${e.value}')
        .join(', ');
    return '{$entries}';
  }
}
