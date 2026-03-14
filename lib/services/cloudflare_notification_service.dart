import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Service to trigger notifications via Cloudflare Worker
///
/// Usage:
/// ```dart
/// await CloudflareNotificationService.sendChatNotification(
///   messageId: messageRef.id,
///   senderId: currentUserId,
///   receiverId: receiverId,
///   text: text,
///   messageType: 'text',
/// );
/// ```
class CloudflareNotificationService {
  // Replace with your actual Cloudflare Worker URL
  static const String _workerUrl =
      'https://lenv-notification-worker.giridharannj.workers.dev/notify';

  // TODO: Add your API secret if using authentication
  static const String? _apiSecret = null;

  static Future<bool> _post(Map<String, dynamic> payload) async {
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {
          'Content-Type': 'application/json',
          if (_apiSecret != null) 'Authorization': 'Bearer $_apiSecret',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('Cloudflare notification sent: $data');
        return data['success'] == true;
      }

      debugPrint(
        'Failed to send Cloudflare notification: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('Error sending Cloudflare notification: $e');
      return false;
    }
  }

  /// Send chat notification
  static Future<bool> sendChatNotification({
    required String messageId,
    required String senderId,
    required String receiverId,
    required String text,
    required String messageType, // 'text' or 'image'
  }) async {
    return sendDirectChatNotification(
      messageId: messageId,
      senderId: senderId,
      recipientId: receiverId,
      text: text,
      messageType: messageType,
    );
  }

  static Future<bool> sendDirectChatNotification({
    required String messageId,
    required String senderId,
    required String recipientId,
    required String text,
    required String messageType,
    String? deepLinkRoute,
    Map<String, dynamic>? metadata,
  }) {
    return _post({
      'type': 'direct_chat',
      'messageId': messageId,
      'senderId': senderId,
      'recipientId': recipientId,
      'text': text,
      'messageType': messageType,
      if (deepLinkRoute != null) 'deepLinkRoute': deepLinkRoute,
      if (metadata != null) 'metadata': metadata,
    });
  }

  static Future<bool> sendGroupMessageNotification({
    required String messageId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String groupType,
    required String groupId,
    required List<String> recipientIds,
    required String content,
    required String messageType,
    String? groupName,
    String? deepLinkRoute,
    Map<String, dynamic>? metadata,
  }) {
    return _post({
      'type': 'group_message',
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'groupType': groupType,
      'groupId': groupId,
      'recipientIds': recipientIds,
      'content': content,
      'messageType': messageType,
      if (groupName != null) 'groupName': groupName,
      if (deepLinkRoute != null) 'deepLinkRoute': deepLinkRoute,
      if (metadata != null) 'metadata': metadata,
    });
  }

  /// Send assignment notification
  static Future<bool> sendAssignmentNotification({
    required String assignmentId,
    required String title,
    required String classId,
    required String createdBy,
  }) async {
    return sendTestAssignmentNotification(
      testId: assignmentId,
      title: title,
      subject: '',
      teacherId: createdBy,
      className: classId,
      section: '',
      schoolCode: '',
      studentIds: const [],
    );
  }

  static Future<bool> sendTestAssignmentNotification({
    required String testId,
    required String title,
    required String subject,
    required String teacherId,
    required String className,
    required String section,
    required String schoolCode,
    required List<String> studentIds,
    String? teacherName,
    String? deepLinkRoute,
    Map<String, dynamic>? metadata,
  }) {
    return _post({
      'type': 'test_assignment',
      'testId': testId,
      'title': title,
      'subject': subject,
      'teacherId': teacherId,
      'className': className,
      'section': section,
      'schoolCode': schoolCode,
      'studentIds': studentIds,
      if (teacherName != null) 'teacherName': teacherName,
      if (deepLinkRoute != null) 'deepLinkRoute': deepLinkRoute,
      if (metadata != null) 'metadata': metadata,
    });
  }

  static Future<bool> sendRewardStatusNotification({
    required String requestId,
    required String status,
    required String productName,
    required String studentId,
    String? parentId,
    String? deepLinkRoute,
    Map<String, dynamic>? metadata,
  }) {
    return _post({
      'type': 'reward_status',
      'requestId': requestId,
      'status': status,
      'productName': productName,
      'studentId': studentId,
      if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
      if (deepLinkRoute != null) 'deepLinkRoute': deepLinkRoute,
      if (metadata != null) 'metadata': metadata,
    });
  }

  /// Send announcement notification
  static Future<bool> sendAnnouncementNotification({
    required String announcementId,
    required String title,
    required String description,
    String targetRole = 'all', // 'student', 'parent', 'teacher', 'all'
    required String createdBy,
  }) async {
    return _post({
      'type': 'announcement',
      'announcementId': announcementId,
      'title': title,
      'description': description,
      'targetRole': targetRole,
      'createdBy': createdBy,
    });
  }

  static Future<bool> sendAudienceAnnouncementNotification({
    required String announcementId,
    required String collection,
    required String createdBy,
    required String text,
    required String audienceType,
    required String schoolId,
    List<String>? standards,
    List<String>? sections,
    bool important = false,
    String? title,
    String? deepLinkRoute,
    Map<String, dynamic>? metadata,
  }) {
    return _post({
      'type': 'announcement',
      'announcementId': announcementId,
      'collection': collection,
      'createdBy': createdBy,
      'text': text,
      'audienceType': audienceType,
      'schoolId': schoolId,
      'important': important,
      if (title != null && title.isNotEmpty) 'title': title,
      if (standards != null) 'standards': standards,
      if (sections != null) 'sections': sections,
      if (deepLinkRoute != null) 'deepLinkRoute': deepLinkRoute,
      if (metadata != null) 'metadata': metadata,
    });
  }

  /// Check worker health
  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse(_workerUrl.replaceAll('/notify', '/health')),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Worker health: $data');
        return data['status'] == 'ok';
      }
      return false;
    } catch (e) {
      debugPrint('Error checking worker health: $e');
      return false;
    }
  }
}
