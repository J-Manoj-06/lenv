import 'media_metadata.dart';

class GroupChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final String? imageUrl;
  final MediaMetadata? mediaMetadata; // WhatsApp-style media metadata
  final int timestamp;
  final List<String>? deletedFor; // List of user IDs who deleted this message
  final bool isDeleted; // Whether message was deleted by sender

  GroupChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    this.imageUrl,
    this.mediaMetadata,
    required this.timestamp,
    this.deletedFor,
    this.isDeleted = false,
  });

  factory GroupChatMessage.fromFirestore(Map<String, dynamic> data, String id) {
    return GroupChatMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      message: data['message'] ?? '',
      imageUrl: data['imageUrl'],
      mediaMetadata: data['mediaMetadata'] != null
          ? MediaMetadata.fromFirestore(data['mediaMetadata'])
          : null,
      timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
      deletedFor: data['deletedFor'] != null
          ? List<String>.from(data['deletedFor'])
          : null,
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'imageUrl': imageUrl,
      'mediaMetadata': mediaMetadata?.toFirestore(),
      'timestamp': timestamp,
      'deletedFor': deletedFor,
      'isDeleted': isDeleted,
    };
  }
}
