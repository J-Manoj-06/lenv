import 'package:hive/hive.dart';

part 'student_dashboard_data.g.dart';

/// Hive model for caching student dashboard data
@HiveType(typeId: 10)
class StudentDashboardData extends HiveObject {
  @HiveField(0)
  final String studentId;

  @HiveField(1)
  final String studentName;

  @HiveField(2)
  final List<MessageItem> messages;

  @HiveField(3)
  final List<AssignmentItem> assignments;

  @HiveField(4)
  final List<AnnouncementItem> announcements;

  @HiveField(5)
  final AttendanceSummary attendance;

  @HiveField(6)
  final DateTime cachedAt;

  StudentDashboardData({
    required this.studentId,
    required this.studentName,
    required this.messages,
    required this.assignments,
    required this.announcements,
    required this.attendance,
    required this.cachedAt,
  });

  factory StudentDashboardData.fromJson(Map<String, dynamic> json) {
    return StudentDashboardData(
      studentId: json['student_id'] ?? '',
      studentName: json['student_name'] ?? '',
      messages:
          (json['messages'] as List?)
              ?.map((e) => MessageItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      assignments:
          (json['assignments'] as List?)
              ?.map((e) => AssignmentItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      announcements:
          (json['announcements'] as List?)
              ?.map((e) => AnnouncementItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      attendance: json['attendance'] != null
          ? AttendanceSummary.fromJson(
              json['attendance'] as Map<String, dynamic>,
            )
          : AttendanceSummary.empty(),
      cachedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'student_id': studentId,
      'student_name': studentName,
      'messages': messages.map((e) => e.toJson()).toList(),
      'assignments': assignments.map((e) => e.toJson()).toList(),
      'announcements': announcements.map((e) => e.toJson()).toList(),
      'attendance': attendance.toJson(),
      'cached_at': cachedAt.toIso8601String(),
    };
  }
}

@HiveType(typeId: 11)
class MessageItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String senderName;

  @HiveField(2)
  final String message;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final bool isRead;

  MessageItem({
    required this.id,
    required this.senderName,
    required this.message,
    required this.timestamp,
    required this.isRead,
  });

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    return MessageItem(
      id: json['id'] ?? '',
      senderName: json['sender_name'] ?? '',
      message: json['message'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
          : DateTime.now(),
      isRead: json['is_read'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_name': senderName,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'is_read': isRead,
    };
  }
}

@HiveType(typeId: 12)
class AssignmentItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String subject;

  @HiveField(3)
  final DateTime dueDate;

  @HiveField(4)
  final String status; // 'pending', 'submitted', 'overdue'

  AssignmentItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.dueDate,
    required this.status,
  });

  factory AssignmentItem.fromJson(Map<String, dynamic> json) {
    return AssignmentItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      subject: json['subject'] ?? '',
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date']) ?? DateTime.now()
          : DateTime.now(),
      status: json['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subject': subject,
      'due_date': dueDate.toIso8601String(),
      'status': status,
    };
  }
}

@HiveType(typeId: 13)
class AnnouncementItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String content;

  @HiveField(3)
  final DateTime postedAt;

  @HiveField(4)
  final String priority; // 'high', 'medium', 'low'

  AnnouncementItem({
    required this.id,
    required this.title,
    required this.content,
    required this.postedAt,
    required this.priority,
  });

  factory AnnouncementItem.fromJson(Map<String, dynamic> json) {
    return AnnouncementItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      postedAt: json['posted_at'] != null
          ? DateTime.tryParse(json['posted_at']) ?? DateTime.now()
          : DateTime.now(),
      priority: json['priority'] ?? 'medium',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'posted_at': postedAt.toIso8601String(),
      'priority': priority,
    };
  }
}

@HiveType(typeId: 14)
class AttendanceSummary extends HiveObject {
  @HiveField(0)
  final double percentage;

  @HiveField(1)
  final int totalDays;

  @HiveField(2)
  final int presentDays;

  @HiveField(3)
  final int absentDays;

  AttendanceSummary({
    required this.percentage,
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      totalDays: json['total_days'] ?? 0,
      presentDays: json['present_days'] ?? 0,
      absentDays: json['absent_days'] ?? 0,
    );
  }

  factory AttendanceSummary.empty() {
    return AttendanceSummary(
      percentage: 0.0,
      totalDays: 0,
      presentDays: 0,
      absentDays: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'percentage': percentage,
      'total_days': totalDays,
      'present_days': presentDays,
      'absent_days': absentDays,
    };
  }
}
