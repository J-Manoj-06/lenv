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

  /// Send chat notification
  static Future<bool> sendChatNotification({
    required String messageId,
    required String senderId,
    required String receiverId,
    required String text,
    required String messageType, // 'text' or 'image'
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {
          'Content-Type': 'application/json',
          if (_apiSecret != null) 'Authorization': 'Bearer $_apiSecret',
        },
        body: jsonEncode({
          'type': 'chat',
          'messageId': messageId,
          'senderId': senderId,
          'receiverId': receiverId,
          'text': text,
          'messageType': messageType,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Chat notification sent: $data');
        return data['success'] ?? false;
      } else {
        debugPrint(
          'Failed to send chat notification: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('Error sending chat notification: $e');
      return false;
    }
  }

  /// Send assignment notification
  static Future<bool> sendAssignmentNotification({
    required String assignmentId,
    required String title,
    required String classId,
    required String createdBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {
          'Content-Type': 'application/json',
          if (_apiSecret != null) 'Authorization': 'Bearer $_apiSecret',
        },
        body: jsonEncode({
          'type': 'assignment',
          'assignmentId': assignmentId,
          'title': title,
          'classId': classId,
          'createdBy': createdBy,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Assignment notification sent: $data');
        return data['success'] ?? false;
      } else {
        debugPrint(
          'Failed to send assignment notification: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('Error sending assignment notification: $e');
      return false;
    }
  }

  /// Send announcement notification
  static Future<bool> sendAnnouncementNotification({
    required String announcementId,
    required String title,
    required String description,
    String targetRole = 'all', // 'student', 'parent', 'teacher', 'all'
    required String createdBy,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_workerUrl),
        headers: {
          'Content-Type': 'application/json',
          if (_apiSecret != null) 'Authorization': 'Bearer $_apiSecret',
        },
        body: jsonEncode({
          'type': 'announcement',
          'announcementId': announcementId,
          'title': title,
          'description': description,
          'targetRole': targetRole,
          'createdBy': createdBy,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Announcement notification sent: $data');
        return data['success'] ?? false;
      } else {
        debugPrint(
          'Failed to send announcement notification: ${response.statusCode} ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('Error sending announcement notification: $e');
      return false;
    }
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
