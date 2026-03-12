import 'package:cloud_firestore/cloud_firestore.dart';
import 'cloudflare_r2_service.dart';
import '../config/cloudflare_config.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _conversationId({
    required String schoolCode,
    required String teacherId,
    required String parentId,
    required String studentId,
  }) => '${schoolCode}__${teacherId}__${parentId}__$studentId';

  Future<String> ensureConversation({
    required String schoolCode,
    required String teacherId,
    required String parentId,
    required String studentId,
    required String studentName,
    required String className,
    String? section,
  }) async {
    final id = _conversationId(
      schoolCode: schoolCode,
      teacherId: teacherId,
      parentId: parentId,
      studentId: studentId,
    );
    final docRef = _db.collection('conversations').doc(id);
    final doc = await docRef.get();
    if (!doc.exists) {
      await docRef.set({
        'schoolCode': schoolCode,
        'teacherId': teacherId,
        'parentId': parentId,
        'studentId': studentId,
        'studentName': studentName,
        'className': className,
        'section': section,
        'lastMessage': null,
        'lastTimestamp': null,
        'unreadForParent': 0,
        'unreadForTeacher': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(
    String conversationId,
  ) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  Future<void> sendMessage({
    required String conversationId,
    required String text,
    required String senderRole, // 'parent' or 'teacher'
    Map<String, dynamic>? mediaMetadata,
  }) async {
    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc();
    final convRef = _db.collection('conversations').doc(conversationId);

    await _db.runTransaction((tx) async {
      // 1) READS first
      final convSnap = await tx.get(convRef);
      final isParent = senderRole == 'parent';
      int unreadParent = 0;
      int unreadTeacher = 0;

      if (convSnap.exists) {
        unreadParent = (convSnap.data()?['unreadForParent'] ?? 0) as int;
        unreadTeacher = (convSnap.data()?['unreadForTeacher'] ?? 0) as int;
      } else {
        // Create the conversation doc if missing (safety net)
        tx.set(convRef, {
          'lastMessage': null,
          'lastTimestamp': null,
          'unreadForParent': 0,
          'unreadForTeacher': 0,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 2) WRITES after reads
      final messageData = {
        'text': text,
        'senderRole': senderRole,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'deliveredToParent': false,
        'deliveredToTeacher': false,
        'readByParent': false,
        'readByTeacher': false,
      };

      // Add media metadata if present
      if (mediaMetadata != null) {
        messageData['mediaMetadata'] = mediaMetadata;
      }

      tx.set(msgRef, messageData);

      tx.update(convRef, {
        'lastMessage': text,
        'lastTimestamp': FieldValue.serverTimestamp(),
        'unreadForParent': isParent ? unreadParent : unreadParent + 1,
        'unreadForTeacher': isParent ? unreadTeacher + 1 : unreadTeacher,
      });
    });
  }

  Future<void> markDelivered({
    required String conversationId,
    required String viewerRole, // 'parent' | 'teacher'
  }) async {
    final msgsRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages');

    final otherRole = viewerRole == 'parent' ? 'teacher' : 'parent';
    final deliveredField = viewerRole == 'parent'
        ? 'deliveredToParent'
        : 'deliveredToTeacher';

    // Simpler query - just get recent messages from other role
    final q = await msgsRef
        .where('senderRole', isEqualTo: otherRole)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();

    if (q.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in q.docs) {
      final data = d.data();
      // Only update if not already delivered
      if (data[deliveredField] != true) {
        batch.update(d.reference, {deliveredField: true});
      }
    }
    await batch.commit();
  }

  Future<void> markMessagesRead({
    required String conversationId,
    required String viewerRole, // 'parent' | 'teacher'
  }) async {
    final msgsRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages');

    final otherRole = viewerRole == 'parent' ? 'teacher' : 'parent';
    final readField = viewerRole == 'parent' ? 'readByParent' : 'readByTeacher';
    final deliveredField = viewerRole == 'parent'
        ? 'deliveredToParent'
        : 'deliveredToTeacher';

    // Simpler query - just get recent messages from other role
    final q = await msgsRef
        .where('senderRole', isEqualTo: otherRole)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();

    if (q.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in q.docs) {
      final data = d.data();
      // Only update if not already read
      if (data[readField] != true) {
        batch.update(d.reference, {readField: true, deliveredField: true});
      }
    }
    await batch.commit();
  }

  Future<void> markAsRead({
    required String conversationId,
    required String viewerRole, // 'parent' or 'teacher'
  }) async {
    final convRef = _db.collection('conversations').doc(conversationId);
    await convRef.update({
      viewerRole == 'parent' ? 'unreadForParent' : 'unreadForTeacher': 0,
    });
  }

  /// Delete a message for everyone (only sender can delete)
  /// Extracts R2 keys from all media sources and deletes files from R2 storage
  /// to prevent storage bloat before soft-deleting the message in Firestore.
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final msgRef = _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId);

    try {
      // Get message data to extract R2 keys
      final snapshot = await msgRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null) {
          // Extract R2 keys from all media sources
          final r2Keys = _extractR2KeysFromMessage(data);

          // Delete files from R2 storage
          if (r2Keys.isNotEmpty) {
            try {
              final r2Service = CloudflareR2Service(
                accountId: CloudflareConfig.accountId,
                bucketName: CloudflareConfig.bucketName,
                accessKeyId: CloudflareConfig.accessKeyId,
                secretAccessKey: CloudflareConfig.secretAccessKey,
                r2Domain: CloudflareConfig.r2Domain,
              );

              for (final key in r2Keys) {
                try {
                  await r2Service.deleteFile(key: key);
                } catch (e) {
                  // Continue with other files
                }
              }
            } catch (e) {
            }
          }
        }
      }
    } catch (e) {
    }

    // Soft-delete message in Firestore
    await msgRef.update({
      'text': '',
      'isDeleted': true,
      'mediaMetadata': FieldValue.delete(),
      'multipleMedia': FieldValue.delete(),
      'imageUrl': FieldValue.delete(),
      'fileUrl': FieldValue.delete(),
      'attachmentUrl': FieldValue.delete(),
      'thumbnailUrl': FieldValue.delete(),
    });
  }

  /// Extract R2 keys from message data
  /// Handles: mediaMetadata, multipleMedia, legacy fields
  List<String> _extractR2KeysFromMessage(Map<String, dynamic> data) {
    final keys = <String>[];

    // 1. Extract from mediaMetadata (primary source)
    final mediaMetadata = data['mediaMetadata'] as Map<String, dynamic>?;
    if (mediaMetadata != null) {
      final r2Key = mediaMetadata['r2Key'] as String?;
      if (r2Key != null && r2Key.isNotEmpty) {
        keys.add(r2Key);
      }

      final thumbnailKey = mediaMetadata['thumbnailR2Key'] as String?;
      if (thumbnailKey != null && thumbnailKey.isNotEmpty) {
        keys.add(thumbnailKey);
      }
    }

    // 2. Extract from multipleMedia array
    final multipleMedia = data['multipleMedia'] as List<dynamic>?;
    if (multipleMedia != null) {
      for (final media in multipleMedia) {
        if (media is Map<String, dynamic>) {
          final r2Key = media['r2Key'] as String?;
          if (r2Key != null && r2Key.isNotEmpty) {
            keys.add(r2Key);
          }

          final thumbnailKey = media['thumbnailR2Key'] as String?;
          if (thumbnailKey != null && thumbnailKey.isNotEmpty) {
            keys.add(thumbnailKey);
          }
        }
      }
    }

    // 3. Extract from legacy fields (imageUrl, fileUrl, attachmentUrl)
    final legacyFields = [
      'imageUrl',
      'fileUrl',
      'attachmentUrl',
      'thumbnailUrl',
    ];
    for (final field in legacyFields) {
      final url = data[field] as String?;
      if (url != null && url.isNotEmpty) {
        final key = _extractR2KeyFromUrl(url);
        if (key != null && !keys.contains(key)) {
          keys.add(key);
        }
      }
    }

    return keys;
  }

  /// Extract R2 key from full URL
  /// Example: https://files.lenv1.tech/conversations/abc123.jpg -> conversations/abc123.jpg
  String? _extractR2KeyFromUrl(String url) {
    try {
      if (url.isEmpty) return null;

      final uri = Uri.parse(url);
      final path = uri.path;

      if (path.isEmpty) return null;

      // Remove leading slash
      return path.startsWith('/') ? path.substring(1) : path;
    } catch (e) {
      return null;
    }
  }
}
