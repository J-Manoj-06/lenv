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

  @HiveField(12)
  final List<dynamic>? multipleMedia; // For multi-image messages

  @HiveField(13)
  final bool isPending; // For pending upload messages

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
    this.multipleMedia,
    this.isPending = false,
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

    // 🔍 CRITICAL: Extract file URL from mediaMetadata if present
    // WHY: PDF files and other media are stored in mediaMetadata, not attachmentUrl
    String? finalAttachmentUrl =
        data['attachmentUrl'] ??
        data['mediaUrl'] ??
        data['imageUrl'] ??
        data['fileUrl'];

    String? finalAttachmentType =
        data['attachmentType'] ?? data['mediaType'] ?? data['type'];

    // Check if message has mediaMetadata field (used for PDFs and other files)
    if (data['mediaMetadata'] != null && data['mediaMetadata'] is Map) {
      final mediaData = data['mediaMetadata'] as Map<String, dynamic>;
      finalAttachmentUrl = mediaData['publicUrl'] ?? finalAttachmentUrl;

      // Determine attachment type from mimeType or originalFileName
      if (finalAttachmentType == null || finalAttachmentType == 'text') {
        final mimeType = mediaData['mimeType']?.toString().toLowerCase();
        final fileName = mediaData['originalFileName']
            ?.toString()
            .toLowerCase();

        if (mimeType != null || fileName != null) {
          if (mimeType?.contains('pdf') == true ||
              fileName?.endsWith('.pdf') == true) {
            finalAttachmentType = 'document';
          } else if (mimeType?.startsWith('image/') == true ||
              fileName?.endsWith('.jpg') == true ||
              fileName?.endsWith('.png') == true) {
            finalAttachmentType = 'image';
          } else if (mimeType?.startsWith('audio/') == true ||
              fileName?.endsWith('.mp3') == true) {
            finalAttachmentType = 'audio';
          } else if (mimeType?.startsWith('video/') == true ||
              fileName?.endsWith('.mp4') == true) {
            finalAttachmentType = 'video';
          } else {
            finalAttachmentType = 'document';
          }
        }
      }
    }

    List<dynamic>? multipleMedia;
    if (data['multipleMedia'] is List) {
      final rawList = data['multipleMedia'] as List;
      multipleMedia = rawList.map((item) {
        if (item is Map) {
          // Deep copy and convert all Timestamp objects to int
          final Map<String, dynamic> cleanedMap = {};
          (item).forEach((key, value) {
            if (value is Timestamp) {
              // Convert Firestore Timestamp to int
              cleanedMap[key.toString()] = value.millisecondsSinceEpoch;
            } else if (value is Map) {
              // Recursively clean nested maps
              final nestedMap = <String, dynamic>{};
              value.forEach((k, v) {
                nestedMap[k.toString()] = v is Timestamp ? v.millisecondsSinceEpoch : v;
              });
              cleanedMap[key.toString()] = nestedMap;
            } else {
              cleanedMap[key.toString()] = value;
            }
          });
          return cleanedMap;
        }
        return item;
      }).toList();
    }

    // Clean poll data if present
    Map<String, dynamic>? cleanedPollData;
    if (data['poll'] is Map) {
      cleanedPollData = _cleanMapFromTimestamps(data['poll']);
    }

    return LocalMessage(
      messageId: messageId,
      chatId: chatId,
      chatType: chatType,
      senderId: data['senderId'] ?? '',
      senderName: senderName,
      messageText: data['text'] ?? data['message'] ?? data['content'],
      timestamp: timestamp,
      attachmentUrl: finalAttachmentUrl,
      attachmentType: finalAttachmentType,
      pollData: cleanedPollData,
      isDeleted: data['isDeleted'] ?? false,
      replyToMessageId: data['replyToMessageId'],
      multipleMedia: multipleMedia,
      isPending: false, // Firebase messages are never pending
    );
  }

  /// Helper to recursively clean Timestamp objects from maps
  /// WHY: Hive cannot serialize Firestore Timestamp objects
  static Map<String, dynamic> _cleanMapFromTimestamps(dynamic data) {
    if (data is! Map) return {};
    
    final Map<String, dynamic> cleaned = {};
    data.forEach((key, value) {
      if (value is Timestamp) {
        cleaned[key.toString()] = value.millisecondsSinceEpoch;
      } else if (value is Map) {
        cleaned[key.toString()] = _cleanMapFromTimestamps(value);
      } else if (value is List) {
        cleaned[key.toString()] = value.map((item) {
          if (item is Timestamp) return item.millisecondsSinceEpoch;
          if (item is Map) return _cleanMapFromTimestamps(item);
          return item;
        }).toList();
      } else {
        cleaned[key.toString()] = value;
      }
    });
    return cleaned;
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
      'multipleMedia': multipleMedia,
      'poll': pollData,
      'isDeleted': isDeleted,
      'replyToMessageId': replyToMessageId,
      'isPending': isPending,
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

  /// Check if message is a file/media attachment
  /// WHY: Identify messages with attachments for file search
  bool hasAttachment() {
    return attachmentUrl != null && attachmentUrl!.isNotEmpty;
  }

  /// Check if message has file/media matching search query
  /// WHY: Enable searching for files by name or type (pdf, image, audio, etc.)
  bool matchesFileSearch(String query) {
    final lowerQuery = query.toLowerCase();

    // Must have attachment
    if (!hasAttachment()) return false;

    // Search in attachment type
    if (attachmentType != null &&
        attachmentType!.toLowerCase().contains(lowerQuery)) {
      return true;
    }

    // Extract filename from URL if available
    if (attachmentUrl != null) {
      final filename = attachmentUrl!.split('/').last.split('?').first;
      if (filename.toLowerCase().contains(lowerQuery)) {
        return true;
      }
    }

    // Search by common file type keywords
    if (attachmentType != null) {
      final type = attachmentType!.toLowerCase();

      // PDF search
      if (lowerQuery.contains('pdf') && type.contains('pdf')) {
        return true;
      }

      // Image search
      if ((lowerQuery.contains('image') ||
              lowerQuery.contains('photo') ||
              lowerQuery.contains('picture') ||
              lowerQuery.contains('img')) &&
          (type.contains('image') ||
              type.contains('photo') ||
              type.contains('img'))) {
        return true;
      }

      // Audio search
      if ((lowerQuery.contains('audio') ||
              lowerQuery.contains('voice') ||
              lowerQuery.contains('sound') ||
              lowerQuery.contains('music')) &&
          type.contains('audio')) {
        return true;
      }

      // Video search
      if ((lowerQuery.contains('video') || lowerQuery.contains('vid')) &&
          type.contains('video')) {
        return true;
      }

      // Document search - broaden this
      if ((lowerQuery.contains('document') ||
              lowerQuery.contains('doc') ||
              lowerQuery.contains('file')) &&
          (type.contains('document') || type.contains('application'))) {
        return true;
      }
    }

    // Also check if searching for generic "file" or "attachment"
    if (lowerQuery.contains('file') ||
        lowerQuery.contains('attachment') ||
        lowerQuery.contains('media')) {
      return true;
    }

    return false;
  }

  /// Get file extension from attachment
  String? getFileExtension() {
    if (attachmentUrl == null) return null;

    final filename = attachmentUrl!.split('/').last.split('?').first;
    final parts = filename.split('.');
    if (parts.length > 1) {
      return parts.last.toLowerCase();
    }

    return null;
  }

  /// Get display name for file
  String getFileName() {
    if (attachmentUrl == null) return 'File';

    final filename = attachmentUrl!.split('/').last.split('?').first;
    // Decode URL-encoded filename
    try {
      return Uri.decodeComponent(filename);
    } catch (e) {
      return filename;
    }
  }

  @override
  String toString() {
    return 'LocalMessage(id: $messageId, chat: $chatId, text: $messageText)';
  }
}
