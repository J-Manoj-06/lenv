import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String senderRole; // 'teacher' or 'parent'
  final String text;
  final DateTime createdAt;
  final bool readByTeacher;
  final bool readByParent;
  // True while the write hasn't been committed on the server yet
  final bool isPending;
  final Map<String, int> reactionSummary;
  final int reactionCount;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.text,
    required this.createdAt,
    this.readByTeacher = false,
    this.readByParent = false,
    this.isPending = false,
    this.reactionSummary = const <String, int>{},
    this.reactionCount = 0,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderRole: data['senderRole'] ?? 'teacher',
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readByTeacher: data['readByTeacher'] ?? false,
      readByParent: data['readByParent'] ?? false,
      isPending: doc.metadata.hasPendingWrites,
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
    }
    return summary;
  }

  static int _parseReactionCount(Map<String, dynamic> data) {
    final raw = data['reactionCount'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return _parseReactionSummary(
      data,
    ).values.fold<int>(0, (sum, value) => sum + value);
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderRole': senderRole,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'readByTeacher': readByTeacher,
      'readByParent': readByParent,
      'reactionSummary': reactionSummary,
      'reactionCount': reactionCount,
    };
  }
}

class Conversation {
  final String id;
  final String teacherId;
  final String parentId;
  final String studentId;
  final String studentName;
  final String parentName;
  final String? parentPhotoUrl;
  final String lastMessage;
  final String lastSenderId;
  final DateTime lastTimestamp;
  final int unreadForTeacher;
  final int unreadForParent;

  Conversation({
    required this.id,
    required this.teacherId,
    required this.parentId,
    required this.studentId,
    required this.studentName,
    required this.parentName,
    this.parentPhotoUrl,
    this.lastMessage = '',
    this.lastSenderId = '',
    required this.lastTimestamp,
    this.unreadForTeacher = 0,
    this.unreadForParent = 0,
  });

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      teacherId: data['teacherId'] ?? '',
      parentId: data['parentId'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      parentName: data['parentName'] ?? '',
      parentPhotoUrl: data['parentPhotoUrl'],
      lastMessage: data['lastMessage'] ?? '',
      lastSenderId: data['lastSenderId'] ?? '',
      lastTimestamp:
          (data['lastTimestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      unreadForTeacher: data['unreadForTeacher'] ?? 0,
      unreadForParent: data['unreadForParent'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'teacherId': teacherId,
      'parentId': parentId,
      'studentId': studentId,
      'studentName': studentName,
      'parentName': parentName,
      if (parentPhotoUrl != null) 'parentPhotoUrl': parentPhotoUrl,
      'lastMessage': lastMessage,
      'lastSenderId': lastSenderId,
      'lastTimestamp': Timestamp.fromDate(lastTimestamp),
      'unreadForTeacher': unreadForTeacher,
      'unreadForParent': unreadForParent,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
