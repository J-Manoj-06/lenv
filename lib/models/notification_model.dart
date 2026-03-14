import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationCategory {
  messaging,
  tests,
  rewards,
  announcements,
  academic,
  alerts,
  general,
}

enum NotificationPriority { low, normal, high, critical }

class NotificationModel {
  final String notificationId;
  final String userId;
  final String role;
  final String schoolId;
  final NotificationCategory category;
  final String title;
  final String body;
  final String iconType;
  final NotificationPriority priority;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool isRead;
  final DateTime createdAt;
  final String? targetType;
  final String? targetId;
  final String? deepLinkRoute;
  final Map<String, dynamic>? metadata;
  final String? dedupeKey;

  NotificationModel({
    required this.notificationId,
    required this.userId,
    required this.role,
    required this.schoolId,
    required this.category,
    required this.title,
    required this.body,
    required this.iconType,
    required this.priority,
    this.soundEnabled = false,
    this.vibrationEnabled = false,
    required this.isRead,
    required this.createdAt,
    this.targetType,
    this.targetId,
    this.deepLinkRoute,
    this.metadata,
    this.dedupeKey,
  });

  // Create from Firestore document
  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final metadata = _safeMap(data['metadata'] ?? data['data']);

    return NotificationModel(
      notificationId: doc.id,
      userId: data['userId'] ?? '',
      role: (data['role'] ?? '').toString(),
      schoolId: (data['schoolId'] ?? '').toString(),
      category: _parseNotificationCategory(data['category'] ?? data['type']),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      iconType: (data['iconType'] ?? data['type'] ?? 'notifications')
          .toString(),
      priority: _parsePriority(data['priority']),
      soundEnabled: data['soundEnabled'] == true,
      vibrationEnabled: data['vibrationEnabled'] == true,
      isRead: data['isRead'] ?? false,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          (data['timestamp'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      targetType: data['targetType']?.toString(),
      targetId: data['targetId']?.toString() ?? data['referenceId']?.toString(),
      deepLinkRoute:
          data['deepLinkRoute']?.toString() ??
          metadata?['deepLinkRoute']?.toString(),
      metadata: metadata,
      dedupeKey: data['dedupeKey']?.toString(),
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'notificationId': notificationId,
      'userId': userId,
      'role': role,
      'schoolId': schoolId,
      'category': category.name,
      'title': title,
      'body': body,
      'iconType': iconType,
      'priority': priority.name,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'targetType': targetType,
      'targetId': targetId,
      'deepLinkRoute': deepLinkRoute,
      'metadata': metadata,
      'dedupeKey': dedupeKey,

      // Backward-compatible fields
      'type': category.name,
      'referenceId': targetId,
      'timestamp': Timestamp.fromDate(createdAt),
      'data': metadata,
    };
  }

  static NotificationCategory _parseNotificationCategory(dynamic raw) {
    final typeString = (raw ?? '').toString().toLowerCase();
    switch (typeString) {
      case 'chat':
      case 'message':
      case 'messaging':
      case 'teacher_group_message':
        return NotificationCategory.messaging;
      case 'assignment':
      case 'test':
      case 'tests':
      case 'result':
      case 'deadline':
      case 'learning':
        return NotificationCategory.tests;
      case 'reward':
      case 'rewards':
      case 'gamification':
        return NotificationCategory.rewards;
      case 'announcement':
      case 'announcements':
        return NotificationCategory.announcements;
      case 'academic':
        return NotificationCategory.academic;
      case 'alert':
      case 'alerts':
        return NotificationCategory.alerts;
      default:
        return NotificationCategory.general;
    }
  }

  static NotificationPriority _parsePriority(dynamic raw) {
    final priority = (raw ?? '').toString().toLowerCase();
    switch (priority) {
      case 'critical':
        return NotificationPriority.critical;
      case 'high':
        return NotificationPriority.high;
      case 'low':
      case 'silent':
        return NotificationPriority.low;
      default:
        return NotificationPriority.normal;
    }
  }

  static Map<String, dynamic>? _safeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return null;
  }

  // Copy with method for updating fields
  NotificationModel copyWith({
    String? notificationId,
    String? userId,
    String? role,
    String? schoolId,
    NotificationCategory? category,
    String? title,
    String? body,
    String? iconType,
    NotificationPriority? priority,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? isRead,
    DateTime? createdAt,
    String? targetType,
    String? targetId,
    String? deepLinkRoute,
    Map<String, dynamic>? metadata,
    String? dedupeKey,
  }) {
    return NotificationModel(
      notificationId: notificationId ?? this.notificationId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      schoolId: schoolId ?? this.schoolId,
      category: category ?? this.category,
      title: title ?? this.title,
      body: body ?? this.body,
      iconType: iconType ?? this.iconType,
      priority: priority ?? this.priority,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      deepLinkRoute: deepLinkRoute ?? this.deepLinkRoute,
      metadata: metadata ?? this.metadata,
      dedupeKey: dedupeKey ?? this.dedupeKey,
    );
  }

  @override
  String toString() {
    return 'NotificationModel(notificationId: $notificationId, title: $title, category: ${category.name}, isRead: $isRead)';
  }
}
