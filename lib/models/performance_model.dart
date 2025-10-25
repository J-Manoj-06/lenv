import 'package:cloud_firestore/cloud_firestore.dart';

class TestSubmission {
  final String testId;
  final String testTitle;
  final int score;
  final int totalPoints;
  final double percentage;
  final DateTime submittedAt;

  TestSubmission({
    required this.testId,
    required this.testTitle,
    required this.score,
    required this.totalPoints,
    required this.percentage,
    required this.submittedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'testId': testId,
      'testTitle': testTitle,
      'score': score,
      'totalPoints': totalPoints,
      'percentage': percentage,
      'submittedAt': Timestamp.fromDate(submittedAt),
    };
  }

  factory TestSubmission.fromJson(Map<String, dynamic> json) {
    return TestSubmission(
      testId: json['testId'] ?? '',
      testTitle: json['testTitle'] ?? '',
      score: json['score'] ?? 0,
      totalPoints: json['totalPoints'] ?? 0,
      percentage: json['percentage']?.toDouble() ?? 0.0,
      submittedAt: (json['submittedAt'] as Timestamp).toDate(),
    );
  }
}

class PerformanceModel {
  final String id;
  final String studentId;
  final String studentName;
  final String instituteId;
  final List<TestSubmission> submissions;
  final double averageScore;
  final int totalTestsTaken;
  final int totalRewardsReceived;
  final String? rank; // Class rank
  final DateTime lastUpdated;

  PerformanceModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.instituteId,
    required this.submissions,
    required this.averageScore,
    required this.totalTestsTaken,
    required this.totalRewardsReceived,
    this.rank,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'studentName': studentName,
      'instituteId': instituteId,
      'submissions': submissions.map((s) => s.toJson()).toList(),
      'averageScore': averageScore,
      'totalTestsTaken': totalTestsTaken,
      'totalRewardsReceived': totalRewardsReceived,
      'rank': rank,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  factory PerformanceModel.fromJson(Map<String, dynamic> json) {
    return PerformanceModel(
      id: json['id'] ?? '',
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'] ?? '',
      instituteId: json['instituteId'] ?? '',
      submissions: json['submissions'] != null
          ? (json['submissions'] as List)
                .map((s) => TestSubmission.fromJson(s))
                .toList()
          : [],
      averageScore: json['averageScore']?.toDouble() ?? 0.0,
      totalTestsTaken: json['totalTestsTaken'] ?? 0,
      totalRewardsReceived: json['totalRewardsReceived'] ?? 0,
      rank: json['rank'],
      lastUpdated: (json['lastUpdated'] as Timestamp).toDate(),
    );
  }
}
