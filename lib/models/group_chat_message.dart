import 'package:cloud_firestore/cloud_firestore.dart';
import 'media_metadata.dart';

class GroupChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final String? imageUrl;
  final MediaMetadata? mediaMetadata; // WhatsApp-style media metadata
  final List<MediaMetadata>?
  multipleMedia; // For multiple images in one message
  final int timestamp;
  final List<String>? deletedFor; // List of user IDs who deleted this message
  final bool isDeleted; // Whether message was deleted by sender
  final String? type; // Message type (e.g., 'poll', 'text', 'image')
  final Map<String, dynamic>? rawData; // Store raw Firestore data for polls
  final String? classId; // Class ID for group chat
  final String? subjectId; // Subject ID for group chat
  final Map<String, int> reactionSummary; // emoji -> count
  final int reactionCount;

  GroupChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    this.imageUrl,
    this.mediaMetadata,
    this.multipleMedia,
    required this.timestamp,
    this.deletedFor,
    this.isDeleted = false,
    this.type,
    this.rawData,
    this.classId,
    this.subjectId,
    this.reactionSummary = const <String, int>{},
    this.reactionCount = 0,
  });

  factory GroupChatMessage.fromFirestore(Map<String, dynamic> data, String id) {
    // Handle timestamp - can be either int or Timestamp
    int timestampValue;
    final timestampData = data['timestamp'];
    if (timestampData is Timestamp) {
      timestampValue = timestampData.toDate().millisecondsSinceEpoch;
    } else if (timestampData is int) {
      timestampValue = timestampData;
    } else {
      timestampValue = DateTime.now().millisecondsSinceEpoch;
    }

    return GroupChatMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      message: data['message'] ?? '',
      imageUrl: data['imageUrl'],
      mediaMetadata: data['mediaMetadata'] != null
          ? MediaMetadata.fromFirestore(data['mediaMetadata'])
          : null,
      multipleMedia: data['multipleMedia'] != null
          ? (() {
              try {
                return (data['multipleMedia'] as List)
                    .whereType<Map<String, dynamic>>()
                    .map((m) => MediaMetadata.fromFirestore(m))
                    .toList();
              } catch (_) {
                return null;
              }
            })()
          : null,
      timestamp: timestampValue,
      deletedFor: data['deletedFor'] != null
          ? List<String>.from(data['deletedFor'])
          : null,
      isDeleted: data['isDeleted'] ?? false,
      type: data['type'],
      rawData: data,
      classId: data['classId'],
      subjectId: data['subjectId'],
      reactionSummary: _parseReactionSummary(data),
      reactionCount: _parseReactionCount(data),
    );
  }

  static Map<String, int> _parseReactionSummary(Map<String, dynamic> data) {
    final summary = <String, int>{};
    final rawSummary = data['reactionSummary'];
    if (rawSummary is Map) {
      for (final entry in rawSummary.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isEmpty) continue;
        if (value is int && value > 0) {
          summary[key] = value;
        } else if (value is num && value > 0) {
          summary[key] = value.toInt();
        }
      }
      if (summary.isNotEmpty) return summary;
    }

    // Backward compatibility with legacy map: emoji -> list<userId>
    final legacy = data['reactions'];
    if (legacy is Map) {
      for (final entry in legacy.entries) {
        final key = entry.key.toString();
        if (key.isEmpty) continue;
        final value = entry.value;
        if (value is List && value.isNotEmpty) {
          summary[key] = value.length;
        }
      }
    }

    return summary;
  }

  static int _parseReactionCount(Map<String, dynamic> data) {
    final raw = data['reactionCount'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();

    final summary = _parseReactionSummary(data);
    return summary.values.fold<int>(0, (sum, value) => sum + value);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'imageUrl': imageUrl,
      'mediaMetadata': mediaMetadata?.toFirestore(),
      'multipleMedia': multipleMedia?.map((m) => m.toFirestore()).toList(),
      'timestamp': timestamp,
      'deletedFor': deletedFor,
      'isDeleted': isDeleted,
      'type': type,
      'reactionSummary': reactionSummary,
      'reactionCount': reactionCount,
    };
  }

  Map<String, dynamic> toMap() {
    // For poll messages, return the raw data; otherwise return toFirestore
    if (rawData != null) {
      return rawData!;
    }
    return toFirestore();
  }
}
