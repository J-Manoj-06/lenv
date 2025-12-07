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

  /// Mark a group as read by storing the last read timestamp for a teacher
  Future<void> markGroupAsRead(
    String classId,
    String subjectId,
    String teacherId,
  ) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .doc(subjectId)
          .set({
        'lastReadBy': {
          teacherId: now,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error marking group as read: $e');
    }
  }

  /// Get the last read timestamp for a teacher in a specific group
  Future<int?> getLastReadTimestamp(
    String classId,
    String subjectId,
    String teacherId,
  ) async {
    try {
      final doc = await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .doc(subjectId)
          .get();
      
      if (!doc.exists || doc.data() == null) return null;
      
      final lastReadBy = doc.data()?['lastReadBy'] as Map<String, dynamic>?;
      if (lastReadBy == null) return null;
      
      return lastReadBy[teacherId] as int?;
    } catch (e) {
      print('Error getting last read timestamp: $e');
      return null;
    }
  }

  /// Get unread count for a teacher in a specific group
  Future<int> getUnreadCount(
    String classId,
    String subjectId,
    String teacherId,
  ) async {
    try {
      final lastReadTimestamp = await getLastReadTimestamp(
        classId,
        subjectId,
        teacherId,
      );

      final messagesSnapshot = await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .doc(subjectId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(300)
          .get();

      if (messagesSnapshot.docs.isEmpty) return 0;

      int unreadCount = 0;
      for (var doc in messagesSnapshot.docs) {
        final msg = doc.data();
        final senderId = msg['senderId'] as String?;
        final timestamp = msg['timestamp'] as int?;

        // Skip teacher's own messages
        if (senderId == null || senderId == teacherId) continue;

        // If we have a last read timestamp, only count messages after it
        if (lastReadTimestamp != null) {
          if (timestamp != null && timestamp > lastReadTimestamp) {
            unreadCount++;
          }
        } else {
          // If no last read timestamp, count all student messages
          unreadCount++;
        }
      }

      return unreadCount;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
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
      // ✅ FIX: Check students collection first (primary source for student data)
      final studentDoc = await _firestore
          .collection('students')
          .doc(studentId)
          .get();

      String? fullClassName;
      String? sectionField;
      String? schoolCode;

      if (studentDoc.exists && studentDoc.data() != null) {
        // Student found in students collection
        final studentData = studentDoc.data()!;
        fullClassName = studentData['className'] ?? '';
        sectionField = studentData['section'] ?? '';
        schoolCode = studentData['schoolCode'] ?? '';

        print(
          '📚 Found student in students collection: className=$fullClassName, section=$sectionField, schoolCode=$schoolCode',
        );
      } else {
        // Fallback: Try users collection
        final userDoc = await _firestore
            .collection('users')
            .doc(studentId)
            .get();

        if (!userDoc.exists || userDoc.data() == null) {
          print(
            '❌ User document not found in both students and users for: $studentId',
          );
          return null;
        }

        final userData = userDoc.data()!;
        fullClassName = userData['className'] ?? '';
        sectionField = userData['section'] ?? '';
        schoolCode = userData['schoolId'] ?? userData['schoolCode'] ?? '';

        print(
          '📚 Found student in users collection: className=$fullClassName, section=$sectionField',
        );
      }

      if (fullClassName == null || fullClassName.isEmpty) {
        print('❌ className is empty for user: $studentId');
        return null;
      }

      // Parse className to extract grade (e.g., "Grade 10" from "Grade 10 - A")
      String grade = '';
      String section = sectionField ?? '';

      final gradeMatch = RegExp(
        r'Grade\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(fullClassName);

      if (gradeMatch != null) {
        grade = 'Grade ${gradeMatch.group(1)}';
      }

      // Extract section from className if not in separate field
      if (section.isEmpty) {
        final sectionMatch = RegExp(
          r'-\s*([A-Z])\s*$',
        ).firstMatch(fullClassName);
        if (sectionMatch != null) {
          section = sectionMatch.group(1)!;
        }
      }

      if (grade.isEmpty) {
        grade = fullClassName; // Fallback to full className
      }

      print(
        '🔍 Looking for class: grade=$grade, section=$section, schoolCode=$schoolCode',
      );

      // Approach 1: Try with schoolCode if available (most specific)
      if (schoolCode != null && schoolCode.isNotEmpty && section.isNotEmpty) {
        final query1 = await _firestore
            .collection('classes')
            .where('schoolCode', isEqualTo: schoolCode)
            .where('className', isEqualTo: grade)
            .where('section', isEqualTo: section)
            .limit(1)
            .get();

        if (query1.docs.isNotEmpty) {
          print('✅ Found class via schoolCode: ${query1.docs.first.id}');
          return query1.docs.first.id;
        }
      }

      // Approach 2: className + section (fallback)
      if (section.isNotEmpty) {
        final query2 = await _firestore
            .collection('classes')
            .where('className', isEqualTo: grade)
            .where('section', isEqualTo: section)
            .limit(1)
            .get();

        if (query2.docs.isNotEmpty) {
          print('✅ Found class via className+section: ${query2.docs.first.id}');
          return query2.docs.first.id;
        }
      }

      // Approach 3: Query with just className and manually filter by section
      final query3 = await _firestore
          .collection('classes')
          .where('className', isEqualTo: grade)
          .limit(10)
          .get();

      if (query3.docs.isNotEmpty) {
        // Try to match section if specified
        if (section.isNotEmpty) {
          for (var doc in query3.docs) {
            final docSection = doc.data()['section'] ?? '';
            if (docSection == section) {
              return doc.id;
            }
          }
        }
        // Return first match if no section or no match found
        return query3.docs.first.id;
      }

      // Approach 4: Try with fullClassName as-is
      final query4 = await _firestore
          .collection('classes')
          .where('className', isEqualTo: fullClassName)
          .limit(1)
          .get();

      if (query4.docs.isNotEmpty) {
        return query4.docs.first.id;
      }

      print(
        'No class found for: grade=$grade, section=$section, fullClassName=$fullClassName',
      );
      return null;
    } catch (e) {
      print('Error getting student class ID: $e');
      return null;
    }
  }
}
