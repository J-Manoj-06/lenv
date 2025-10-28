import 'package:cloud_firestore/cloud_firestore.dart';

class RewardPointsModel {
  final String id;
  final String studentId;
  final String testId;
  final double marks;
  final double totalMarks;
  final int pointsEarned;
  final DateTime timestamp;

  RewardPointsModel({
    required this.id,
    required this.studentId,
    required this.testId,
    required this.marks,
    required this.totalMarks,
    required this.pointsEarned,
    required this.timestamp,
  });

  factory RewardPointsModel.fromJson(Map<String, dynamic> json, {String? id}) {
    return RewardPointsModel(
      id: id ?? (json['id'] as String? ?? ''),
      studentId: (json['studentId'] as String? ?? ''),
      testId: (json['testId'] as String? ?? ''),
      marks: (json['marks'] as num? ?? 0).toDouble(),
      totalMarks: (json['totalMarks'] as num? ?? 0).toDouble(),
      pointsEarned: (json['pointsEarned'] as num? ?? 0).toInt(),
      timestamp: (json['timestamp'] is Timestamp)
          ? (json['timestamp'] as Timestamp).toDate()
          : (json['timestamp'] is DateTime)
          ? json['timestamp'] as DateTime
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'studentId': studentId,
    'testId': testId,
    'marks': marks,
    'totalMarks': totalMarks,
    'pointsEarned': pointsEarned,
    'timestamp': Timestamp.fromDate(timestamp),
  };
}
