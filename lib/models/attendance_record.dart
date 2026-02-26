import 'package:cloud_firestore/cloud_firestore.dart';

/// Attendance record model for a student
class AttendanceRecord {
  final DateTime date;
  final String status; // "present", "absent", "holiday"

  AttendanceRecord({required this.date, required this.status});

  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    DateTime date;
    if (map['date'] is Timestamp) {
      date = (map['date'] as Timestamp).toDate();
    } else if (map['date'] is String) {
      date = DateTime.parse(map['date'] as String);
    } else {
      date = DateTime.now();
    }

    return AttendanceRecord(
      date: date,
      status: (map['status'] ?? 'absent') as String,
    );
  }

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'status': status,
  };
}
