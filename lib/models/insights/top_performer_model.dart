import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for individual student in top performers list
class TopPerformerStudent {
  final String studentId;
  final String name;
  final String section;
  final double avgScore;
  final int rank;

  TopPerformerStudent({
    required this.studentId,
    required this.name,
    required this.section,
    required this.avgScore,
    required this.rank,
  });

  factory TopPerformerStudent.fromJson(Map<String, dynamic> json, int rank) {
    return TopPerformerStudent(
      studentId: json['studentId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      section: json['section'] as String? ?? '',
      avgScore: (json['avgScore'] as num?)?.toDouble() ?? 0.0,
      rank: rank,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'name': name,
      'section': section,
      'avgScore': avgScore,
    };
  }
}

/// Model for standard-wise top performers
class StandardTopPerformers {
  final String standard;
  final List<TopPerformerStudent> top3;

  StandardTopPerformers({required this.standard, required this.top3});

  factory StandardTopPerformers.fromJson(Map<String, dynamic> json) {
    final top3List = json['top3'] as List<dynamic>? ?? [];
    return StandardTopPerformers(
      standard: json['standard'] as String? ?? '',
      top3: top3List
          .asMap()
          .entries
          .map(
            (e) => TopPerformerStudent.fromJson(
              e.value as Map<String, dynamic>,
              e.key + 1,
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'standard': standard, 'top3': top3.map((s) => s.toJson()).toList()};
  }
}

/// Main model for top performers summary document
class TopPerformersSummary {
  final String schoolCode;
  final String range;
  final DateTime updatedAt;
  final List<StandardTopPerformers> standards;

  TopPerformersSummary({
    required this.schoolCode,
    required this.range,
    required this.updatedAt,
    required this.standards,
  });

  factory TopPerformersSummary.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final standardsList = data['standards'] as List<dynamic>? ?? [];

    return TopPerformersSummary(
      schoolCode: data['schoolCode'] as String? ?? '',
      range: data['range'] as String? ?? '7d',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      standards: standardsList
          .map((s) => StandardTopPerformers.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schoolCode': schoolCode,
      'range': range,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'standards': standards.map((s) => s.toJson()).toList(),
    };
  }
}

/// Model for full standard ranking (for "View More" page)
class StandardFullRanking {
  final String standard;
  final DateTime updatedAt;
  final List<TopPerformerStudent> students;

  StandardFullRanking({
    required this.standard,
    required this.updatedAt,
    required this.students,
  });

  factory StandardFullRanking.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final studentsList = data['students'] as List<dynamic>? ?? [];

    return StandardFullRanking(
      standard: data['standard'] as String? ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      students: studentsList
          .asMap()
          .entries
          .map(
            (e) => TopPerformerStudent.fromJson(
              e.value as Map<String, dynamic>,
              e.key + 1,
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'standard': standard,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'students': students.map((s) => s.toJson()).toList(),
    };
  }
}
