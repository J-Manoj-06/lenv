import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/parent_teacher_group.dart';
import '../models/community_message_model.dart';
import '../models/student_model.dart';

class ParentTeacherGroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String buildGroupId({
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

  /// Ensure parent-teacher section group exists and return its metadata
  Future<ParentTeacherGroup> ensureGroupForChild({
    required StudentModel child,
  }) async {
    final className = child.className ?? '';
    final section = child.section ?? '';
    final schoolCode = child.schoolCode ?? '';
    final groupId = buildGroupId(
      schoolCode: schoolCode,
      className: className,
      section: section,
    );

    final groupRef = _firestore
        .collection('parent_teacher_groups')
        .doc(groupId);
    final snap = await groupRef.get();

    if (!snap.exists) {
      final groupName = _buildGroupName(className: className, section: section);
      await groupRef.set({
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
        id: groupId,
        name: groupName,
        className: className,
        section: section,
        schoolCode: schoolCode,
      );
    }

    final data = snap.data() as Map<String, dynamic>;
    return ParentTeacherGroup(
      id: groupId,
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
              .map((doc) => CommunityMessageModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// Send a text message
  Future<void> sendMessage({
    required String groupId,
    required String senderId,
    required String senderName,
    required String senderRole, // 'parent' or 'teacher'
    required String content,
  }) async {
    final messageRef = _firestore
        .collection('parent_teacher_groups')
        .doc(groupId)
        .collection('messages')
        .doc();

    final messageData = {
      'communityId': groupId,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'senderAvatar': '',
      'type': 'text',
      'content': content,
      'imageUrl': '',
      'fileUrl': '',
      'fileName': '',
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
    batch.set(groupRef, {
      'lastMessage': content.length > 100
          ? '${content.substring(0, 100)}...'
          : content,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }
}
