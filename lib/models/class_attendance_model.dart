import 'package:flutter/material.dart';
import 'student_attendance_model.dart';

class ClassAttendanceModel {
  final String classId;
  final String className;
  final int totalStudents;
  final int presentCount;
  final int absentCount;
  final double percentage;
  final List<StudentAttendanceModel> students;

  ClassAttendanceModel({
    required this.classId,
    required this.className,
    required this.totalStudents,
    required this.presentCount,
    required this.absentCount,
    required this.percentage,
    required this.students,
  });

  factory ClassAttendanceModel.fromJson(Map<String, dynamic> json) {
    final studentsList =
        (json['students'] as List<dynamic>?)
            ?.map(
              (s) => StudentAttendanceModel.fromJson(s as Map<String, dynamic>),
            )
            .toList() ??
        [];

    return ClassAttendanceModel(
      classId: json['classId'] as String,
      className: json['className'] as String,
      totalStudents: json['totalStudents'] as int,
      presentCount: json['presentCount'] as int,
      absentCount: json['absentCount'] as int,
      percentage: (json['percentage'] as num).toDouble(),
      students: studentsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'classId': classId,
      'className': className,
      'totalStudents': totalStudents,
      'presentCount': presentCount,
      'absentCount': absentCount,
      'percentage': percentage,
      'students': students.map((s) => s.toJson()).toList(),
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
