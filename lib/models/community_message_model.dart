import 'package:cloud_firestore/cloud_firestore.dart';
import 'media_metadata.dart';

class CommunityMessageModel {
  final String messageId;
  final String communityId;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String senderAvatar;
  final String type;
  final String content;
  final String imageUrl;
  final String fileUrl;
  final String fileName;
  final MediaMetadata? mediaMetadata; // WhatsApp-style media metadata
  final List<MediaMetadata>?
  multipleMedia; // For multiple images in one message
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isEdited;
  final bool isDeleted;
  final bool isPinned;
  final Map<String, List<String>> reactions;
  final String replyTo;
  final int replyCount;
  final bool isReported;
  final int reportCount;
  final List<String>? deletedFor; // List of user IDs who deleted this message
  final DocumentSnapshot? documentSnapshot; // ✅ For pagination support

  CommunityMessageModel({
    required this.messageId,
    required this.communityId,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.senderAvatar,
    required this.type,
    required this.content,
    required this.imageUrl,
    required this.fileUrl,
    required this.fileName,
    this.mediaMetadata,
    this.multipleMedia,
    required this.createdAt,
    this.updatedAt,
    required this.isEdited,
    required this.isDeleted,
    required this.isPinned,
    required this.reactions,
    required this.replyTo,
    required this.replyCount,
    required this.isReported,
    required this.reportCount,
    this.deletedFor,
    this.documentSnapshot,
  });

  factory CommunityMessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    String asString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      return value.toString();
    }

    bool asBool(dynamic value, {bool fallback = false}) {
      if (value is bool) return value;
      if (value is String) {
        final v = value.toLowerCase().trim();
        if (v == 'true') return true;
        if (v == 'false') return false;
      }
      return fallback;
    }

    int asInt(dynamic value, {int fallback = 0}) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    // Parse reactions map safely
    final reactionsMap = <String, List<String>>{};
    if (data['reactions'] is Map) {
      final reactionsData = Map<dynamic, dynamic>.from(
        data['reactions'] as Map,
      );
      reactionsData.forEach((key, value) {
        final emoji = asString(key);
        if (emoji.isEmpty) return;
        if (value is List) {
          reactionsMap[emoji] = value
              .map((v) => asString(v))
              .where((v) => v.isNotEmpty)
              .toList();
        } else {
          reactionsMap[emoji] = <String>[];
        }
      });
    }

    MediaMetadata? parsedMediaMetadata;
    try {
      if (data['mediaMetadata'] != null) {
        parsedMediaMetadata = MediaMetadata.fromFirestore(
          Map<String, dynamic>.from(data['mediaMetadata'] as Map),
        );
      }
    } catch (_) {
      parsedMediaMetadata = null;
    }

    List<MediaMetadata>? parsedMultipleMedia;
    if (data['multipleMedia'] is List) {
      final safeList = <MediaMetadata>[];
      for (final item in (data['multipleMedia'] as List)) {
        try {
          if (item is Map) {
            safeList.add(
              MediaMetadata.fromFirestore(Map<String, dynamic>.from(item)),
            );
          }
        } catch (_) {
          // Skip only malformed media item, not the entire message.
        }
      }
      parsedMultipleMedia = safeList.isNotEmpty ? safeList : null;
    }

    return CommunityMessageModel(
      messageId: doc.id,
      communityId: asString(data['communityId']),
      senderId: asString(data['senderId']),
      senderName: asString(data['senderName']),
      senderRole: asString(data['senderRole']).isNotEmpty
          ? asString(data['senderRole'])
          : 'student',
      senderAvatar: asString(data['senderAvatar']),
      type: asString(data['type']).isNotEmpty ? asString(data['type']) : 'text',
      content: asString(data['content']),
      imageUrl: asString(data['imageUrl']),
      fileUrl: asString(data['fileUrl']),
      fileName: asString(data['fileName']),
      mediaMetadata: parsedMediaMetadata,
      multipleMedia: parsedMultipleMedia,
      createdAt:
          parseDate(data['createdAt']) ??
          parseDate(data['timestamp']) ??
          DateTime.now(),
      updatedAt: parseDate(data['updatedAt']),
      isEdited: asBool(data['isEdited']),
      isDeleted: asBool(data['isDeleted']),
      isPinned: asBool(data['isPinned']),
      reactions: reactionsMap,
      replyTo: asString(data['replyTo']),
      replyCount: asInt(data['replyCount']),
      isReported: asBool(data['isReported']),
      reportCount: asInt(data['reportCount']),
      deletedFor: data['deletedFor'] is List
          ? (data['deletedFor'] as List)
                .map((v) => asString(v))
                .where((v) => v.isNotEmpty)
                .toList()
          : null,
      documentSnapshot: doc, // ✅ Store for pagination
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'communityId': communityId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'senderAvatar': senderAvatar,
      'type': type,
      'content': content,
      'imageUrl': imageUrl,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'mediaMetadata': mediaMetadata?.toFirestore(),
      'multipleMedia': multipleMedia?.map((m) => m.toFirestore()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'isPinned': isPinned,
      'reactions': reactions,
      'replyTo': replyTo,
      'replyCount': replyCount,
      'isReported': isReported,
      'reportCount': reportCount,
      'deletedFor': deletedFor,
    };
  }

  // Get total reaction count
  int get totalReactions {
    int total = 0;
    reactions.forEach((emoji, userIds) {
      total += userIds.length;
    });
    return total;
  }

  // Check if user has reacted with specific emoji
  bool hasUserReacted(String userId, String emoji) {
    return reactions[emoji]?.contains(userId) ?? false;
  }

  // Get all emojis user has reacted with
  List<String> getUserReactions(String userId) {
    List<String> userReactions = [];
    reactions.forEach((emoji, userIds) {
      if (userIds.contains(userId)) {
        userReactions.add(emoji);
      }
    });
    return userReactions;
  }
}
