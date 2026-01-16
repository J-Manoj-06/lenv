import 'package:flutter/material.dart';

class AttendanceSummaryModel {
  final DateTime date;
  final int totalStudents;
  final int totalPresent;
  final int totalAbsent;
  final double percentage;

  AttendanceSummaryModel({
    required this.date,
    required this.totalStudents,
    required this.totalPresent,
    required this.totalAbsent,
    required this.percentage,
  });

  factory AttendanceSummaryModel.fromJson(Map<String, dynamic> json) {
    return AttendanceSummaryModel(
      date: DateTime.parse(json['date'] as String),
      totalStudents: json['totalStudents'] as int,
      totalPresent: json['totalPresent'] as int,
      totalAbsent: json['totalAbsent'] as int,
      percentage: (json['percentage'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'totalStudents': totalStudents,
      'totalPresent': totalPresent,
      'totalAbsent': totalAbsent,
      'percentage': percentage,
    };
  }

  String get attendanceStatus {
    if (percentage >= 85) return 'Good';
    if (percentage >= 75) return 'Average';
    return 'Low';
  }

  Color get statusColor {
    if (percentage >= 85) return const Color(0xFF34D399);
    if (percentage >= 75) return const Color(0xFFFBBF24);
    return const Color(0xFFFB7185);
  }
}
