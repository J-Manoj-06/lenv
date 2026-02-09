import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'local_message.g.dart';

/// Local message model stored in Hive database
/// WHY: Offline-first storage for all messages, enabling instant search and display
@HiveType(typeId: 0)
class LocalMessage extends HiveObject {
  @HiveField(0)
  final String messageId; // Primary key

  @HiveField(1)
  final String chatId; // For filtering by chat

  @HiveField(2)
  final String chatType; // 'staff_room', 'community', 'private'

  @HiveField(3)
  final String senderId;

  @HiveField(4)
  final String senderName;

  @HiveField(5)
  final String? messageText; // The actual text content

  @HiveField(6)
  final int timestamp; // For sorting (milliseconds since epoch)

  @HiveField(7)
  final String? attachmentUrl;

  @HiveField(8)
  final String? attachmentType; // 'image', 'document', 'audio', etc.

  @HiveField(9)
  final Map<String, dynamic>? pollData; // For poll messages

  @HiveField(10)
  final bool isDeleted; // Soft delete flag

  @HiveField(11)
  final String? replyToMessageId; // For threaded conversations

  LocalMessage({
    required this.messageId,
    required this.chatId,
    required this.chatType,
    required this.senderId,
    required this.senderName,
    this.messageText,
    required this.timestamp,
    this.attachmentUrl,
    this.attachmentType,
    this.pollData,
    this.isDeleted = false,
    this.replyToMessageId,
  });

  /// Convert from Firebase document
  /// WHY: Transform Firebase data into local storage format
  factory LocalMessage.fromFirestore(
    Map<String, dynamic> data,
    String messageId,
    String chatId,
    String chatType,
  ) {
    // Parse timestamp properly from Firebase
    int timestamp;
    final createdAt = data['createdAt'];
    final timestampField = data['timestamp'];

    if (createdAt != null) {
      if (createdAt is Timestamp) {
        timestamp = createdAt.millisecondsSinceEpoch;
      } else if (createdAt is int) {
        timestamp = createdAt;
      } else {
        timestamp = DateTime.now().millisecondsSinceEpoch;
      }
    } else if (timestampField != null) {
      if (timestampField is Timestamp) {
        timestamp = timestampField.millisecondsSinceEpoch;
      } else if (timestampField is int) {
        timestamp = timestampField;
      } else {
        timestamp = DateTime.now().millisecondsSinceEpoch;
      }
    } else {
      timestamp = DateTime.now().millisecondsSinceEpoch;
    }

    // For private chats (teacher-parent), use senderRole as fallback if senderName is missing
    String senderName = data['senderName'] ?? '';
    if (senderName.isEmpty && chatType == 'private') {
      final senderRole = data['senderRole']?.toString() ?? '';
      if (senderRole == 'teacher') {
        senderName = 'Teacher';
      } else if (senderRole == 'parent') {
        senderName = 'Parent';
      }
    }

    return LocalMessage(
      messageId: messageId,
      chatId: chatId,
      chatType: chatType,
      senderId: data['senderId'] ?? '',
      senderName: senderName,
      messageText: data['text'] ?? data['message'] ?? data['content'],
      timestamp: timestamp,
      attachmentUrl:
          data['attachmentUrl'] ??
          data['mediaUrl'] ??
          data['imageUrl'] ??
          data['fileUrl'],
      attachmentType:
          data['attachmentType'] ?? data['mediaType'] ?? data['type'],
      pollData: data['poll'],
      isDeleted: data['isDeleted'] ?? false,
      replyToMessageId: data['replyToMessageId'],
    );
  }

  /// Convert to Map for display in UI
  /// WHY: UI widgets expect Map<String, dynamic> format
  Map<String, dynamic> toMap() {
    return {
      'id': messageId,
      'chatId': chatId,
      'chatType': chatType,
      'senderId': senderId,
      'senderName': senderName,
      'text': messageText,
      'message': messageText,
      'createdAt': timestamp,
      'attachmentUrl': attachmentUrl,
      'mediaUrl': attachmentUrl,
      'attachmentType': attachmentType,
      'mediaType': attachmentType,
      'poll': pollData,
      'isDeleted': isDeleted,
      'replyToMessageId': replyToMessageId,
      'isPending': false, // Local messages are never pending
    };
  }

  /// Check if message matches search query
  /// WHY: Fast in-memory filtering before database query
  bool matchesSearch(String query) {
    final lowerQuery = query.toLowerCase();

    // Search in message text
    if (messageText != null &&
        messageText!.toLowerCase().contains(lowerQuery)) {
      return true;
    }

    // Search in sender name
    if (senderName.toLowerCase().contains(lowerQuery)) {
      return true;
    }

    // Search in poll question
    if (pollData != null) {
      final pollQuestion = pollData!['question'] as String?;
      if (pollQuestion != null &&
          pollQuestion.toLowerCase().contains(lowerQuery)) {
        return true;
      }
    }

    return false;
  }

  @override
  String toString() {
    return 'LocalMessage(id: $messageId, chat: $chatId, text: $messageText)';
  }
}
