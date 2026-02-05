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
          ? (data['multipleMedia'] as List)
                .map((m) => MediaMetadata.fromFirestore(m))
                .toList()
          : null,
      timestamp: timestampValue,
      deletedFor: data['deletedFor'] != null
          ? List<String>.from(data['deletedFor'])
          : null,
      isDeleted: data['isDeleted'] ?? false,
      type: data['type'],
      rawData: data,
    );
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
