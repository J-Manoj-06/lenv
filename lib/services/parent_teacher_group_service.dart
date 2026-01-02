import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/parent_teacher_group.dart';
import '../models/community_message_model.dart';
import '../models/student_model.dart';
import '../models/media_metadata.dart';

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

  /// Stream latest messages (paginated, default 50)
  Stream<List<CommunityMessageModel>> getMessagesStream(
    String groupId, {
    int limit = 50,
  }) {
    return _firestore
        .collection('parent_teacher_groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                if (data['createdAt'] == null) return null;
                return CommunityMessageModel.fromFirestore(doc);
              })
              .whereType<CommunityMessageModel>()
              .toList(),
        );
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
      print('❌ Error fetching paginated messages: $e');
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

    for (final messageId in messageIds) {
      // Mark as deleted instead of actually deleting to preserve chat history structure
      batch.update(messagesRef.doc(messageId), {
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'content': '',
        'imageUrl': '',
        'fileUrl': '',
        'mediaMetadata': null,
      });
    }

    await batch.commit();
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
          print('Error parsing message: $e');
          continue;
        }
      }

      return results;
    } catch (e) {
      print('Error searching messages: $e');
      return [];
    }
  }
}
