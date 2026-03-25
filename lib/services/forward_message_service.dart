import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/forward_message_data.dart';

/// Handles writing forwarded messages to any supported Firestore destination.
/// No media is re-uploaded – existing public URLs are reused directly.
class ForwardMessageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final ForwardMessageService _instance =
      ForwardMessageService._internal();
  factory ForwardMessageService() => _instance;
  ForwardMessageService._internal();

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Forward [messages] to every [destinations].
  /// Returns a map: destinationId → error string (null = success).
  Future<Map<String, String?>> forwardMessages({
    required List<ForwardMessageData> messages,
    required List<ForwardDestination> destinations,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final results = <String, String?>{};

    for (final dest in destinations) {
      try {
        for (final msg in messages) {
          await _forwardSingle(
            message: msg,
            destination: dest,
            senderId: senderId,
            senderName: senderName,
            senderRole: senderRole,
          );
        }
        results[dest.id] = null; // success
      } catch (e) {
        results[dest.id] = e.toString();
      }
    }

    return results;
  }

  // ─── Routing ─────────────────────────────────────────────────────────────────

  Future<void> _forwardSingle({
    required ForwardMessageData message,
    required ForwardDestination destination,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    switch (destination.type) {
      case 'community':
        await _forwardToCommunity(
          message: message,
          communityId: destination.id,
          senderId: senderId,
          senderName: senderName,
          senderRole: senderRole,
        );
        return;

      case 'group':
        final classId = destination.metadata?['classId'] as String?;
        final subjectId = destination.metadata?['subjectId'] as String?;
        if (classId == null || subjectId == null) {
          throw Exception(
            'Missing classId/subjectId metadata for group destination',
          );
        }
        await _forwardToGroup(
          message: message,
          classId: classId,
          subjectId: subjectId,
          senderId: senderId,
          senderName: senderName,
          senderRole: senderRole,
        );
        return;

      case 'staff_room':
        await _forwardToStaffRoom(
          message: message,
          instituteId: destination.id,
          senderId: senderId,
          senderName: senderName,
          senderRole: senderRole,
        );
        return;

      case 'parent_teacher_group':
        await _forwardToParentTeacherGroup(
          message: message,
          groupId: destination.id,
          senderId: senderId,
          senderName: senderName,
          senderRole: senderRole,
        );
        return;

      default:
        throw Exception('Unsupported destination type: ${destination.type}');
    }
  }

  // ─── Destination writers ──────────────────────────────────────────────────────

  Future<void> _forwardToCommunity({
    required ForwardMessageData message,
    required String communityId,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final map = message.toForwardedFirestoreMap(
      newSenderId: senderId,
      newSenderName: senderName,
      newSenderRole: senderRole,
    );
    await _firestore
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .add(map);
  }

  Future<void> _forwardToGroup({
    required ForwardMessageData message,
    required String classId,
    required String subjectId,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final map = message.toForwardedFirestoreMap(
      newSenderId: senderId,
      newSenderName: senderName,
      newSenderRole: senderRole,
    );
    await _firestore
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subjectId)
        .collection('messages')
        .add(map);
  }

  Future<void> _forwardToStaffRoom({
    required ForwardMessageData message,
    required String instituteId,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Staff room uses `text` (not `message`) and both `timestamp` + `createdAt`
    final map = <String, dynamic>{
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'text': message.text ?? '',
      'createdAt': now,
      'timestamp': FieldValue.serverTimestamp(),
      'isDeleted': false,
      'forwarded': true,
      'originalSenderId': message.originalSenderId,
      'originalSenderName': message.originalSenderName,
      'type': message.messageType,
    };

    if (message.messageType == 'image' && message.mediaUrl != null) {
      map['imageUrl'] = message.mediaUrl;
      map['mediaMetadata'] = _buildMetadata(message, now);
    } else if (message.messageType == 'multi_image' &&
        message.multipleImageUrls != null) {
      map['multipleMedia'] = message.multipleImageUrls!
          .asMap()
          .entries
          .map(
            (e) => {
              'publicUrl': e.value,
              'r2Key': '',
              'thumbnail': '',
              'originalFileName': 'image_${e.key}.jpg',
              'fileSize': 0,
              'mimeType': 'image/jpeg',
              'serverStatus': 'available',
              'uploadedAt': now,
              'expiresAt': now + const Duration(days: 30).inMilliseconds,
            },
          )
          .toList();
    } else if (message.mediaUrl != null) {
      map['mediaMetadata'] = _buildMetadata(message, now);
    }

    await _firestore
        .collection('staff_rooms')
        .doc(instituteId)
        .collection('messages')
        .add(map);
  }

  Future<void> _forwardToParentTeacherGroup({
    required ForwardMessageData message,
    required String groupId,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final base = message.toForwardedFirestoreMap(
      newSenderId: senderId,
      newSenderName: senderName,
      newSenderRole: senderRole,
    );

    final map = <String, dynamic>{
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'senderAvatar': '',
      'type': base['type'] ?? message.messageType,
      'content': base['message'] ?? message.text ?? '',
      'imageUrl': base['imageUrl'] ?? '',
      'fileUrl': '',
      'fileName': message.fileName ?? '',
      'mediaMetadata': base['mediaMetadata'],
      'multipleMedia': base['multipleMedia'],
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': now,
      'isEdited': false,
      'isDeleted': false,
      'isPinned': false,
      'reactions': {},
      'replyTo': '',
      'replyCount': 0,
      'isReported': false,
      'reportCount': 0,
      'forwarded': true,
      'originalSenderId': message.originalSenderId,
      'originalSenderName': message.originalSenderName,
    };

    map.removeWhere((key, value) => value == null);

    await _firestore
        .collection('parent_teacher_groups')
        .doc(groupId)
        .collection('messages')
        .add(map);
  }

  Map<String, dynamic> _buildMetadata(ForwardMessageData msg, int now) => {
    'publicUrl': msg.mediaUrl ?? '',
    'r2Key': '',
    'thumbnail': '',
    'originalFileName': msg.fileName ?? '',
    'fileSize': msg.fileSize ?? 0,
    'mimeType': msg.mimeType ?? 'application/octet-stream',
    'serverStatus': 'available',
    'uploadedAt': now,
    'expiresAt': now + const Duration(days: 30).inMilliseconds,
  };
}
