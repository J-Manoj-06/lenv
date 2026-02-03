import 'media_metadata.dart';

class StaffRoomMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final String? imageUrl;
  final MediaMetadata? mediaMetadata;
  final int createdAt;
  final bool isDeleted;

  StaffRoomMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.imageUrl,
    this.mediaMetadata,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory StaffRoomMessage.fromFirestore(Map<String, dynamic> data, String id) {
    return StaffRoomMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      text: data['text'] ?? '',
      imageUrl: data['imageUrl'],
      mediaMetadata: data['mediaMetadata'] != null
          ? MediaMetadata.fromFirestore(data['mediaMetadata'])
          : null,
      createdAt: data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'imageUrl': imageUrl,
      'mediaMetadata': mediaMetadata?.toFirestore(),
      'createdAt': createdAt,
      'isDeleted': isDeleted,
    };
  }
}
