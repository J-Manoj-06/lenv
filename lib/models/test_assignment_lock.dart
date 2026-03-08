import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a lock that prevents multiple teachers from assigning
/// tests to the same class/section at overlapping times.
/// The lock is keyed by class + section, so it blocks ALL subjects.
class TestAssignmentLock {
  final String id;
  final String classId; // e.g. "Grade 10"
  final String sectionId; // e.g. "A"  — used as part of the document key
  final String subjectName; // e.g. "Mathematics" — stored for display only
  final String assignedByTeacherName;
  final String teacherId;
  final DateTime assignedAtTimestamp;
  final DateTime nextAvailableTimestamp;
  final bool isLocked;

  const TestAssignmentLock({
    required this.id,
    required this.classId,
    required this.sectionId,
    required this.subjectName,
    required this.assignedByTeacherName,
    required this.teacherId,
    required this.assignedAtTimestamp,
    required this.nextAvailableTimestamp,
    required this.isLocked,
  });

  /// Returns true if the lock is currently active (not yet expired).
  bool get isActive =>
      isLocked && DateTime.now().isBefore(nextAvailableTimestamp);

  factory TestAssignmentLock.fromJson(Map<String, dynamic> data, String id) {
    DateTime toDateTime(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.now();
    }

    return TestAssignmentLock(
      id: id,
      classId: data['classId'] as String? ?? '',
      sectionId: data['sectionId'] as String? ?? '',
      subjectName: data['subjectName'] as String? ?? '',
      assignedByTeacherName:
          data['assignedByTeacherName'] as String? ?? 'Unknown Teacher',
      teacherId: data['teacherId'] as String? ?? '',
      assignedAtTimestamp: toDateTime(data['assignedAtTimestamp']),
      nextAvailableTimestamp: toDateTime(data['nextAvailableTimestamp']),
      isLocked: data['isLocked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'classId': classId,
    'sectionId': sectionId,
    'subjectName': subjectName,
    'assignedByTeacherName': assignedByTeacherName,
    'teacherId': teacherId,
    'assignedAtTimestamp': Timestamp.fromDate(assignedAtTimestamp),
    'nextAvailableTimestamp': Timestamp.fromDate(nextAvailableTimestamp),
    'isLocked': isLocked,
  };

  TestAssignmentLock copyWith({
    String? id,
    String? classId,
    String? sectionId,
    String? subjectName,
    String? assignedByTeacherName,
    String? teacherId,
    DateTime? assignedAtTimestamp,
    DateTime? nextAvailableTimestamp,
    bool? isLocked,
  }) {
    return TestAssignmentLock(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      sectionId: sectionId ?? this.sectionId,
      subjectName: subjectName ?? this.subjectName,
      assignedByTeacherName:
          assignedByTeacherName ?? this.assignedByTeacherName,
      teacherId: teacherId ?? this.teacherId,
      assignedAtTimestamp: assignedAtTimestamp ?? this.assignedAtTimestamp,
      nextAvailableTimestamp:
          nextAvailableTimestamp ?? this.nextAvailableTimestamp,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}
