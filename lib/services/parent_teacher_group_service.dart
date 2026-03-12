import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/parent_teacher_group.dart';
import '../models/community_message_model.dart';
import '../models/student_model.dart';
import '../models/media_metadata.dart';
import 'cloudflare_r2_service.dart';
import '../config/cloudflare_config.dart';

class ParentTeacherGroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String buildGroupId({
    required String schoolCode,
    required String className,
    required String section,
  }) {
    final normalizedClass = _normalizeClassName(className);
    final normalizedSection = section.trim();
    final safeSchool = (schoolCode.isNotEmpty ? schoolCode : 'SCHOOL')
        .replaceAll(' ', '_')
        .toLowerCase();
    final safeClass = (normalizedClass.isNotEmpty ? normalizedClass : 'class')
        .replaceAll(' ', '_')
        .toLowerCase();
    final safeSection =
        (normalizedSection.isNotEmpty ? normalizedSection : 'section')
            .replaceAll(' ', '_')
            .toLowerCase();
    return '${safeSchool}_${safeClass}_${safeSection}_parents_teachers';
  }

  String _normalizeClassName(String className) {
    final trimmed = className.trim();
    if (trimmed.isEmpty) return '';

    // Prefer numeric grade if present (handles "Grade 10", "10th", "10")
    final digitMatch = RegExp(r'\d+').firstMatch(trimmed);
    if (digitMatch != null) {
      return digitMatch.group(0)!;
    }

    // Fallback: strip common prefixes
    return trimmed
        .replaceAll(RegExp(r'(?i)grade\s+'), '')
        .replaceAll(RegExp(r'(?i)class\s+'), '')
        .trim();
  }

  /// Ensure parent-teacher section group exists and return its metadata
  Future<ParentTeacherGroup> ensureGroupForChild({
    required StudentModel child,
  }) async {
    final className = child.className ?? '';
    final section = child.section ?? '';
    final schoolCode = child.schoolCode ?? '';
    return ensureGroupForClassSection(
      schoolCode: schoolCode,
      className: className,
      section: section,
    );
  }

  /// Ensure group for a class-section pair (shared by teachers and parents)
  Future<ParentTeacherGroup> ensureGroupForClassSection({
    required String schoolCode,
    required String className,
    required String section,
  }) async {
    final normalizedId = buildGroupId(
      schoolCode: schoolCode,
      className: className,
      section: section,
    );

    final legacyId = _buildLegacyGroupId(
      schoolCode: schoolCode,
      className: className,
      section: section,
    );

    // Prefer normalized doc; fall back to legacy if it already exists
    final normalizedRef = _firestore
        .collection('parent_teacher_groups')
        .doc(normalizedId);
    final normalizedSnap = await normalizedRef.get();

    DocumentReference<Map<String, dynamic>> targetRef = normalizedRef;
    DocumentSnapshot<Map<String, dynamic>>? targetSnap = normalizedSnap;

    if (!normalizedSnap.exists && legacyId != normalizedId) {
      final legacyRef = _firestore
          .collection('parent_teacher_groups')
          .doc(legacyId);
      final legacySnap = await legacyRef.get();
      if (legacySnap.exists) {
        targetRef = legacyRef;
        targetSnap = legacySnap;
      }
    }

    if (targetSnap.exists != true) {
      final groupName = _buildGroupName(className: className, section: section);
      await targetRef.set({
        'name': groupName,
        'className': className,
        'section': section,
        'schoolCode': schoolCode,
        'lastMessage': '',
        'lastMessageAt': null,
        'memberCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return ParentTeacherGroup.empty(
        id: targetRef.id,
        name: groupName,
        className: className,
        section: section,
        schoolCode: schoolCode,
      );
    }

    final data = targetSnap.data() as Map<String, dynamic>;
    return ParentTeacherGroup(
      id: targetRef.id,
      name:
          (data['name'] as String?) ??
          _buildGroupName(className: className, section: section),
      className: data['className'] ?? className,
      section: data['section'] ?? section,
      schoolCode: data['schoolCode'] ?? schoolCode,
      lastMessage: data['lastMessage'] ?? '',
      lastMessageAt: data['lastMessageAt'] != null
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : null,
      memberCount: data['memberCount'] ?? 0,
    );
  }

  // Legacy build (without class normalization) to re-use existing docs
  String _buildLegacyGroupId({
    required String schoolCode,
    required String className,
    required String section,
  }) {
    final safeSchool = (schoolCode.isNotEmpty ? schoolCode : 'SCHOOL')
        .replaceAll(' ', '_')
        .toLowerCase();
    final safeClass = (className.isNotEmpty ? className : 'class')
        .replaceAll(' ', '_')
        .toLowerCase();
    final safeSection = (section.isNotEmpty ? section : 'section')
        .replaceAll(' ', '_')
        .toLowerCase();
    return '${safeSchool}_${safeClass}_${safeSection}_parents_teachers';
  }

  String _buildGroupName({required String className, required String section}) {
    final cls = className.isNotEmpty ? className : 'Class';
    final sec = section.isNotEmpty ? section : '';
    return '$cls ${sec.isNotEmpty ? sec : ''} Parents & Teachers'.trim();
  }

  /// Stream latest messages (paginated, default 100 to catch new uploads)
  Stream<List<CommunityMessageModel>> getMessagesStream(
    String groupId, {
    int limit = 100,
  }) {
    return _firestore
        .collection('parent_teacher_groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final messages = <CommunityMessageModel>[];
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              final createdAtType = data['createdAt']?.runtimeType;
              final hasMulti = data['multipleMedia'] != null;
              final multiCount = hasMulti
                  ? (data['multipleMedia'] as List?)?.length ?? 0
                  : 0;

              // Filter out documents with invalid timestamp data or deleted messages
              if (data['createdAt'] != null && !(data['isDeleted'] ?? false)) {
                final msg = CommunityMessageModel.fromFirestore(doc);
                messages.add(msg);
              } else {
              }
            } catch (e, stack) {
              // Skip messages that fail to parse (e.g., corrupted data)
            }
          }
          return messages;
        });
  }

  /// ✅ OPTIMIZED: Paginated message fetching for loading older messages
  Future<List<CommunityMessageModel>> getMessagesPaginated({
    required String groupId,
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection('parent_teacher_groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['createdAt'] == null) return null;
            return CommunityMessageModel.fromFirestore(doc);
          })
          .whereType<CommunityMessageModel>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Send a message (text or media)
  Future<void> sendMessage({
    required String groupId,
    required String senderId,
    required String senderName,
    required String senderRole, // 'parent' or 'teacher'
    required String content,
    String mediaType = 'text', // text | image | pdf | audio
    MediaMetadata? mediaMetadata,
  }) async {
    final messageRef = _firestore
        .collection('parent_teacher_groups')
        .doc(groupId)
        .collection('messages')
        .doc();

    final hasMedia = mediaMetadata != null;
    final messageData = {
      'communityId': groupId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'senderAvatar': '',
      'type': mediaType,
      'content': content,
      'imageUrl': '',
      'fileUrl': '',
      'fileName': mediaMetadata?.originalFileName ?? '',
      'mediaMetadata': mediaMetadata?.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': null,
      'isEdited': false,
      'isDeleted': false,
      'isPinned': false,
      'reactions': {},
      'replyTo': '',
      'replyCount': 0,
      'isReported': false,
      'reportCount': 0,
    };

    // Write message and update group metadata atomically
    final batch = _firestore.batch();
    batch.set(messageRef, messageData);

    final groupRef = _firestore
        .collection('parent_teacher_groups')
        .doc(groupId);
    // Derive a friendly last message
    final lastMessage = hasMedia
        ? _lastMessageLabel(mediaType, mediaMetadata)
        : content;

    batch.set(groupRef, {
      'lastMessage': lastMessage.length > 100
          ? '${lastMessage.substring(0, 100)}...'
          : lastMessage,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  String _lastMessageLabel(String mediaType, MediaMetadata? metadata) {
    switch (mediaType) {
      case 'image':
        return 'Sent a photo';
      case 'pdf':
        return metadata?.originalFileName?.isNotEmpty == true
            ? 'Shared ${metadata!.originalFileName}'
            : 'Shared a document';
      case 'audio':
        return 'Sent an audio';
      default:
        return 'Sent a file';
    }
  }

  /// Delete messages for everyone
  /// Extracts R2 keys from all media sources and deletes files from R2 storage
  /// to prevent storage bloat before soft-deleting messages in Firestore.
  Future<void> deleteMessagesForEveryone({
    required String groupId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;

    final batch = _firestore.batch();
    final messagesRef = _firestore
        .collection('parent_teacher_groups')
        .doc(groupId)
        .collection('messages');

    // Collect all R2 keys to delete
    final r2KeysToDelete = <String>{};

    // First pass: Extract R2 keys from all messages
    for (final messageId in messageIds) {
      try {
        final docSnapshot = await messagesRef.doc(messageId).get();
        if (!docSnapshot.exists) continue;

        final data = docSnapshot.data();
        if (data == null) continue;

        // Extract R2 keys from message data
        final keys = _extractR2KeysFromMessage(data);
        r2KeysToDelete.addAll(keys);

        // Mark as deleted in batch
        batch.update(messagesRef.doc(messageId), {
          'isDeleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'content': '',
          'imageUrl': '',
          'fileUrl': '',
          'mediaMetadata': null,
          'multipleMedia': FieldValue.delete(),
        });
      } catch (e) {
      }
    }

    // Delete files from R2 storage
    if (r2KeysToDelete.isNotEmpty) {
      try {
        final r2Service = CloudflareR2Service(
          accountId: CloudflareConfig.accountId,
          bucketName: CloudflareConfig.bucketName,
          accessKeyId: CloudflareConfig.accessKeyId,
          secretAccessKey: CloudflareConfig.secretAccessKey,
          r2Domain: CloudflareConfig.r2Domain,
        );

        int successCount = 0;

        for (final key in r2KeysToDelete) {
          try {
            await r2Service.deleteFile(key: key);
            successCount++;
          } catch (e) {
            // Continue with other files
          }
        }

      } catch (e) {
      }
    }

    // Commit soft-delete batch
    await batch.commit();
  }

  /// Extract R2 keys from message data
  /// Handles: mediaMetadata.r2Key, thumbnailR2Key, multipleMedia, legacy imageUrl/fileUrl
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

    // 3. Extract from legacy imageUrl (old format with full URL)
    final imageUrl = data['imageUrl'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final key = _extractR2KeyFromUrl(imageUrl);
      if (key != null) {
        keys.add(key);
      }
    }

    // 4. Extract from legacy fileUrl (old format with full URL)
    final fileUrl = data['fileUrl'] as String?;
    if (fileUrl != null && fileUrl.isNotEmpty) {
      final key = _extractR2KeyFromUrl(fileUrl);
      if (key != null) {
        keys.add(key);
      }
    }

    return keys;
  }

  /// Extract R2 key from full URL
  /// Example: https://files.lenv1.tech/parent_teacher_groups/abc123.jpg -> parent_teacher_groups/abc123.jpg
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

  // Search parent-teacher group messages by content or file names
  Future<List<CommunityMessageModel>> searchParentGroupMessages({
    required String groupId,
    required String query,
    int limit = 25,
  }) async {
    try {
      final lowerQuery = query.toLowerCase();

      // Get all messages for this group
      final messagesSnapshot = await _firestore
          .collection('parent_teacher_groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(500) // Search in recent messages
          .get();

      // Filter messages that match the query
      final results = <CommunityMessageModel>[];

      for (final doc in messagesSnapshot.docs) {
        try {
          final message = CommunityMessageModel.fromFirestore(doc);

          // Skip deleted messages
          if (message.isDeleted ?? false) {
            continue;
          }

          // Search in message text
          if (message.content.toLowerCase().contains(lowerQuery)) {
            results.add(message);
            if (results.length >= limit) break;
            continue;
          }

          // Search in file names
          if (message.mediaMetadata != null) {
            final fileName =
                message.mediaMetadata?.originalFileName?.toLowerCase() ?? '';
            if (fileName.contains(lowerQuery)) {
              results.add(message);
              if (results.length >= limit) break;
            }
          }
        } catch (e) {
          continue;
        }
      }

      return results;
    } catch (e) {
      return [];
    }
  }
}
