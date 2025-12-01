import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/group_chat_message.dart';
import '../models/group_subject.dart';
import '../models/community.dart';

class GroupMessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ====================================================
  // GROUP CHAT METHODS
  // ====================================================

  /// Send a message to a class subject group
  Future<void> sendGroupMessage(
    String classId,
    String subjectId,
    GroupChatMessage message,
  ) async {
    try {
      // Use the format: classes/{classId}/subjects/{subjectId}/messages
      await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .doc(subjectId)
          .collection('messages')
          .add(message.toFirestore());
    } catch (e) {
      throw Exception('Failed to send group message: $e');
    }
  }

  /// Get real-time stream of group messages
  Stream<List<GroupChatMessage>> getGroupMessages(
    String classId,
    String subjectId,
  ) {
    return _firestore
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subjectId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GroupChatMessage.fromFirestore(doc.data(), doc.id))
              .toList();
        });
  }

  /// Get subjects for a specific class
  Future<List<GroupSubject>> getClassSubjects(String classId) async {
    try {
      // First, try to get subjects from subcollection
      final subjectsSnapshot = await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .get();

      if (subjectsSnapshot.docs.isNotEmpty) {
        return subjectsSnapshot.docs
            .map((doc) => GroupSubject.fromFirestore(doc.data(), doc.id))
            .toList();
      }

      // If no subcollection, try to get subjects array from the class document itself
      final classDoc = await _firestore
          .collection('classes')
          .doc(classId)
          .get();
      final classData = classDoc.data();

      if (classData != null && classData['subjects'] is List) {
        final subjectsList = classData['subjects'] as List;
        return subjectsList
            .map((subject) {
              if (subject is String) {
                // If subjects are just strings, create GroupSubject with default values
                return GroupSubject(
                  id: subject.toLowerCase().replaceAll(' ', '_'),
                  name: subject,
                  teacherName: 'Teacher',
                  icon: _getIconForSubject(subject),
                );
              } else if (subject is Map) {
                // If subjects are objects with details
                return GroupSubject(
                  id:
                      subject['id']?.toString() ??
                      subject['name']?.toString().toLowerCase().replaceAll(
                        ' ',
                        '_',
                      ) ??
                      '',
                  name: subject['name']?.toString() ?? '',
                  teacherName: subject['teacherName']?.toString() ?? 'Teacher',
                  icon:
                      subject['icon']?.toString() ??
                      _getIconForSubject(subject['name']?.toString() ?? ''),
                );
              }
              return GroupSubject(id: '', name: '', teacherName: '', icon: '');
            })
            .where((s) => s.name.isNotEmpty)
            .toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  String _getIconForSubject(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return '🔢';
    if (s.contains('science')) return '🔬';
    if (s.contains('social')) return '🌍';
    if (s.contains('english')) return '📖';
    if (s.contains('hindi')) return '📚';
    if (s.contains('chem')) return '🧪';
    if (s.contains('phy')) return '⚡';
    if (s.contains('bio')) return '🧬';
    if (s.contains('computer')) return '💻';
    if (s.contains('history')) return '📜';
    return '📕';
  }

  // ====================================================
  // COMMUNITY CHAT METHODS
  // ====================================================

  /// Send a message to a community
  Future<void> sendCommunityMessage(
    String communityId,
    GroupChatMessage message,
  ) async {
    try {
      await _firestore
          .collection('communities')
          .doc(communityId)
          .collection('messages')
          .add(message.toFirestore());
    } catch (e) {
      throw Exception('Failed to send community message: $e');
    }
  }

  /// Get real-time stream of community messages
  Stream<List<GroupChatMessage>> getCommunityMessages(String communityId) {
    return _firestore
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GroupChatMessage.fromFirestore(doc.data(), doc.id))
              .toList();
        });
  }

  /// Get all available communities
  Future<List<Community>> getAllCommunities() async {
    try {
      final snapshot = await _firestore.collection('communities').get();

      return snapshot.docs
          .map((doc) => Community.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ====================================================
  // UTILITY METHODS
  // ====================================================

  /// Get student's class ID from their profile
  Future<String?> getStudentClassId(String studentId) async {
    try {
      final doc = await _firestore.collection('users').doc(studentId).get();
      final data = doc.data();

      if (data != null) {
        final className = data['className'] ?? '';
        final section = data['section'] ?? '';

        if (className.isNotEmpty && section.isNotEmpty) {
          // Query classes collection to find the matching document
          final classesQuery = await _firestore
              .collection('classes')
              .where('className', isEqualTo: className)
              .where('section', isEqualTo: section)
              .limit(1)
              .get();

          if (classesQuery.docs.isNotEmpty) {
            return classesQuery.docs.first.id;
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
