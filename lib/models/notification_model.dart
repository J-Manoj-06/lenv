import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType { chat, assignment, announcement, general }

class NotificationModel {
  final String notificationId;
  final String userId;
  final String title;
  final String body;
  final NotificationType type;
  final String? referenceId; // messageId, assignmentId, or announcementId
  final bool isRead;
  final DateTime timestamp;
  final Map<String, dynamic>? data; // Additional data for navigation

  NotificationModel({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.referenceId,
    required this.isRead,
    required this.timestamp,
    this.data,
  });

  // Create from Firestore document
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      notificationId: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: _parseNotificationType(data['type']),
      referenceId: data['referenceId'],
      isRead: data['isRead'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      data: data['data'] as Map<String, dynamic>?,
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'body': body,
      'type': type.name,
      'referenceId': referenceId,
      'isRead': isRead,
      'timestamp': Timestamp.fromDate(timestamp),
      'data': data,
    };
  }

  // Parse notification type from string
  static NotificationType _parseNotificationType(String? typeString) {
    switch (typeString) {
      case 'chat':
        return NotificationType.chat;
      case 'assignment':
        return NotificationType.assignment;
      case 'announcement':
        return NotificationType.announcement;
      default:
        return NotificationType.general;
    }
  }

  // Copy with method for updating fields
  NotificationModel copyWith({
    String? notificationId,
    String? userId,
    String? title,
    String? body,
    NotificationType? type,
    String? referenceId,
    bool? isRead,
    DateTime? timestamp,
    Map<String, dynamic>? data,
  }) {
    return NotificationModel(
      notificationId: notificationId ?? this.notificationId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      referenceId: referenceId ?? this.referenceId,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp ?? this.timestamp,
      data: data ?? this.data,
    );
  }

  @override
  String toString() {
    return 'NotificationModel(notificationId: $notificationId, title: $title, type: ${type.name}, isRead: $isRead)';
  }
}
