import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for individual teacher statistics
class TeacherStats {
  final String teacherId;
  final String name;
  final int totalTests;
  final Map<String, int> classSplit; // {"10-A": 4, "10-B": 3}

  TeacherStats({
    required this.teacherId,
    required this.name,
    required this.totalTests,
    required this.classSplit,
  });

  factory TeacherStats.fromJson(Map<String, dynamic> json) {
    final splitData = json['classSplit'] as Map<String, dynamic>? ?? {};
    final classSplit = splitData.map(
      (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
    );

    return TeacherStats(
      teacherId: json['teacherId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      totalTests: (json['totalTests'] as num?)?.toInt() ?? 0,
      classSplit: classSplit,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teacherId': teacherId,
      'name': name,
      'totalTests': totalTests,
      'classSplit': classSplit,
    };
  }
}

/// Main model for teacher stats summary document
class TeacherStatsSummary {
  final String schoolCode;
  final String range;
  final DateTime updatedAt;
  final List<TeacherStats> teachers;

  TeacherStatsSummary({
    required this.schoolCode,
    required this.range,
    required this.updatedAt,
    required this.teachers,
  });

  factory TeacherStatsSummary.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final teachersList = data['teachers'] as List<dynamic>? ?? [];

    return TeacherStatsSummary(
      schoolCode: data['schoolCode'] as String? ?? '',
      range: data['range'] as String? ?? '7d',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      teachers: teachersList
          .map((t) => TeacherStats.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schoolCode': schoolCode,
      'range': range,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'teachers': teachers.map((t) => t.toJson()).toList(),
    };
  }
}

/// Model for individual test summary
class TestSummary {
  final String testId;
  final String title;
  final String standard;
  final String section;
  final double avgScore;
  final DateTime date;

  TestSummary({
    required this.testId,
    required this.title,
    required this.standard,
    required this.section,
    required this.avgScore,
    required this.date,
  });

  factory TestSummary.fromJson(Map<String, dynamic> json) {
    return TestSummary(
      testId: json['testId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      standard: json['standard'] as String? ?? '',
      section: json['section'] as String? ?? '',
      avgScore: (json['avgScore'] as num?)?.toDouble() ?? 0.0,
      date: (json['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'testId': testId,
      'title': title,
      'standard': standard,
      'section': section,
      'avgScore': avgScore,
      'date': Timestamp.fromDate(date),
    };
  }
}

/// Model for teacher detailed tests (for detail page)
class TeacherTestsDetail {
  final String teacherId;
  final String schoolCode;
  final String range;
  final DateTime updatedAt;
  final List<TestSummary> recentTests;

  TeacherTestsDetail({
    required this.teacherId,
    required this.schoolCode,
    required this.range,
    required this.updatedAt,
    required this.recentTests,
  });

  factory TeacherTestsDetail.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final testsList = data['recentTests'] as List<dynamic>? ?? [];

    return TeacherTestsDetail(
      teacherId: data['teacherId'] as String? ?? '',
      schoolCode: data['schoolCode'] as String? ?? '',
      range: data['range'] as String? ?? '7d',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      recentTests: testsList
          .map((t) => TestSummary.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'teacherId': teacherId,
      'schoolCode': schoolCode,
      'range': range,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'recentTests': recentTests.map((t) => t.toJson()).toList(),
    };
  }
}
