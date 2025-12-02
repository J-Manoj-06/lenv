import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

  factory CommunityMessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse reactions map
    Map<String, List<String>> reactionsMap = {};
    if (data['reactions'] != null) {
      final reactionsData = data['reactions'] as Map<String, dynamic>;
      reactionsData.forEach((key, value) {
        reactionsMap[key] = List<String>.from(value ?? []);
      });
    }

    return CommunityMessageModel(
      messageId: doc.id,
      communityId: data['communityId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderRole: data['senderRole'] ?? 'student',
      senderAvatar: data['senderAvatar'] ?? '',
      type: data['type'] ?? 'text',
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      fileUrl: data['fileUrl'] ?? '',
      fileName: data['fileName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      isEdited: data['isEdited'] ?? false,
      isDeleted: data['isDeleted'] ?? false,
      isPinned: data['isPinned'] ?? false,
      reactions: reactionsMap,
      replyTo: data['replyTo'] ?? '',
      replyCount: data['replyCount'] ?? 0,
      isReported: data['isReported'] ?? false,
      reportCount: data['reportCount'] ?? 0,
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
