import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/group_chat_message.dart';
import '../models/group_subject.dart';
import '../models/community.dart';

class GroupMessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache for student class IDs to prevent repeated Firestore queries
  static final Map<String, String> _classIdCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // ====================================================
  // GROUP CHAT METHODS
  // ====================================================

  /// Send a message to a class subject group
  /// ✅ OPTIMIZATION: Updates teacher_groups index for real-time unread counts
  Future<void> sendGroupMessage(
    String classId,
    String subjectId,
    GroupChatMessage message,
  ) async {
    try {
      // Add message to Firestore
      await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .doc(subjectId)
          .collection('messages')
          .add(message.toFirestore());

      // Update teacher_groups index for this class-subject combo
      // This updates the teacher's unread count in real-time without scanning messages
      await _updateTeacherGroupsAfterMessage(classId, subjectId, message);

      // ✅ NEW: Update class document for students so they see groups reorder in real-time
      await _updateClassAfterMessage(classId, subjectId, message);
    } catch (e) {
      throw Exception('Failed to send group message: $e');
    }
  }

  /// ✅ OPTIMIZATION: Update teacher_groups collection when message sent
  /// Increments unread count for teacher, updates lastMessage/lastMessageAt
  Future<void> _updateTeacherGroupsAfterMessage(
    String classId,
    String subjectId,
    GroupChatMessage message,
  ) async {
    try {
      // Get class document to find the teacher for this subject
      final classDoc = await _firestore
          .collection('classes')
          .doc(classId)
          .get();

      if (!classDoc.exists) return;

      final classData = classDoc.data();
      if (classData == null) return;

      final subjectTeachers =
          classData['subjectTeachers'] as Map<String, dynamic>?;
      if (subjectTeachers == null) return;

      // Find the teacher assigned to this subject
      final subjectData = subjectTeachers[subjectId] as Map<String, dynamic>?;
      if (subjectData == null) return;

      final teacherId = subjectData['teacherId'] as String?;
      if (teacherId == null) return;

      // Don't increment unread if message is from teacher themselves
      if (message.senderId == teacherId) return;

      // Update teacher_groups document
      final groupId = '${classId}_$subjectId';
      await _firestore.collection('teacher_groups').doc(teacherId).set({
        'groups': {
          groupId: {
            'unreadCount': FieldValue.increment(1),
            'lastMessage': message.message.length > 50
                ? '${message.message.substring(0, 50)}...'
                : message.message,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastMessageBy': message.senderName,
            'classId': classId,
            'subjectId': subjectId,
            'className': classData['className'] ?? '',
            'section': classData['section'] ?? '',
            'subject': subjectId,
            'teacherName': subjectData['teacherName'] ?? '',
            'schoolCode': classData['schoolCode'] ?? '',
          },
        },
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Don't throw - message was already sent successfully
    }
  }

  /// ✅ NEW: Update class document with subject-level last message time
  /// This allows students' group lists to reorder in real-time
  Future<void> _updateClassAfterMessage(
    String classId,
    String subjectId,
    GroupChatMessage message,
  ) async {
    try {
      // Store last message time by subject so list can sort by it
      await _firestore.collection('classes').doc(classId).set({
        'subjectLastMessageTime': {subjectId: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (e) {
      // Don't throw - message was already sent successfully
    }
  }

  /// Get real-time stream of group messages
  /// ✅ OPTIMIZED: Added .limit(50) for pagination
  Stream<List<GroupChatMessage>> getGroupMessages(
    String classId,
    String subjectId, {
    int limit = 50, // ✅ Default 50 messages
  }) {
    return _firestore
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subjectId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit) // ✅ OPTIMIZATION: Limit messages loaded
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .where((doc) {
                // Filter out documents with invalid data
                final data = doc.data();
                // ✅ FIXED: Also filter out deleted messages
                return data['timestamp'] != null &&
                    !(data['isDeleted'] ?? false);
              })
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
            'lastReadBy': {teacherId: now},
          }, SetOptions(merge: true));
    } catch (e) {}
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
      return 0;
    }
  }

  /// Get subjects for a specific class
  Future<List<GroupSubject>> getClassSubjects(String classId) async {
    try {
      // Get the class document with server read to avoid stale cache
      final classDoc = await _firestore
          .collection('classes')
          .doc(classId)
          .get(const GetOptions(source: Source.server));

      if (!classDoc.exists) {
        return [];
      }

      final classData = classDoc.data();
      if (classData == null) {
        return [];
      }

      // Get subjects array and subjectTeachers map
      final subjectsList = classData['subjects'] as List?;
      final subjectTeachers =
          classData['subjectTeachers'] as Map<String, dynamic>?;

      if (subjectsList == null || subjectsList.isEmpty) {
        return [];
      }

      // Create GroupSubject objects from subjects array and subjectTeachers map
      final List<GroupSubject> groupSubjects = [];

      for (final subject in subjectsList) {
        if (subject is String && subject.isNotEmpty) {
          // Get teacher info from subjectTeachers map
          final subjectKey = subject.toLowerCase().trim();
          final teacherInfo =
              subjectTeachers?[subjectKey] as Map<String, dynamic>?;

          final teacherName =
              teacherInfo?['teacherName'] as String? ?? 'Teacher';

          groupSubjects.add(
            GroupSubject(
              id: subjectKey.replaceAll(' ', '_'),
              name: _capitalizeSubject(subject),
              teacherName: teacherName,
              icon: _getIconForSubject(subject),
            ),
          );
        }
      }

      return groupSubjects;
    } catch (e) {
      return [];
    }
  }

  /// Capitalize subject name properly
  String _capitalizeSubject(String subject) {
    return subject
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? ''
              : word[0].toUpperCase() + word.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  String _getIconForSubject(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return '🔢';
    if (s.contains('science') &&
        !s.contains('social') &&
        !s.contains('computer')) {
      return '🔬';
    }
    if (s.contains('social')) return '🌍';
    if (s.contains('english')) return '📖';
    if (s.contains('hindi')) return '📚';
    if (s.contains('chem')) return '🧪';
    if (s.contains('phy') && !s.contains('education')) return '⚡';
    if (s.contains('bio')) return '🧬';
    if (s.contains('computer')) return '💻';
    if (s.contains('history')) return '📜';
    if (s.contains('physical') || s.contains('education')) return '⚽';
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
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .where((doc) {
                // Filter out documents with invalid data
                final data = doc.data();
                return data['timestamp'] != null;
              })
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
    // Check cache first (cache valid for 5 minutes)
    if (_classIdCache.containsKey(studentId)) {
      final cacheAge = DateTime.now().difference(_cacheTimestamps[studentId]!);
      if (cacheAge.inMinutes < 5) {
        debugPrint('📦 Using cached classId for student $studentId');
        return _classIdCache[studentId];
      }
    }

    final classId = await _getStudentClassIdInternal(studentId, isRetry: false);

    // Cache the result (even if null, to prevent repeated failed queries)
    if (classId != null) {
      _classIdCache[studentId] = classId;
      _cacheTimestamps[studentId] = DateTime.now();
      debugPrint('💾 Cached classId $classId for student $studentId');
    }

    return classId;
  }

  Future<String?> _getStudentClassIdInternal(
    String studentId, {
    required bool isRetry,
  }) async {
    try {
      debugPrint(
        '🔍 Fetching classId for student $studentId (retry: $isRetry)',
      );

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
        debugPrint(
          '✅ Found student in students collection: $fullClassName - $sectionField',
        );
      } else {
        // Fallback: Try users collection
        debugPrint('⚠️ Student not in students collection, trying users...');
        final userDoc = await _firestore
            .collection('users')
            .doc(studentId)
            .get();

        if (!userDoc.exists || userDoc.data() == null) {
          debugPrint('❌ Student not found in users collection either');
          return null;
        }

        final userData = userDoc.data()!;
        fullClassName = userData['className'] ?? '';
        sectionField = userData['section'] ?? '';
        schoolCode = userData['schoolId'] ?? userData['schoolCode'] ?? '';
        debugPrint(
          '✅ Found student in users collection: $fullClassName - $sectionField',
        );
      }

      if (fullClassName == null || fullClassName.isEmpty) {
        debugPrint('❌ className is empty');
        if (!isRetry) {
          // Try one more time with a delay
          await Future.delayed(const Duration(milliseconds: 1500));
          return _getStudentClassIdInternal(studentId, isRetry: true);
        } else {
          return null;
        }
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

      return null;
    } catch (e) {
      return null;
    }
  }

  // Search group messages by content or file names
  Future<List<GroupChatMessage>> searchGroupMessages({
    required String classId,
    required String subjectId,
    required String query,
    int limit = 25,
  }) async {
    try {
      final lowerQuery = query.toLowerCase();

      // Get all messages for this group
      final messagesSnapshot = await _firestore
          .collection('classes')
          .doc(classId)
          .collection('subjects')
          .doc(subjectId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(500) // Search in recent messages
          .get();

      // Filter messages that match the query
      final results = <GroupChatMessage>[];

      for (final doc in messagesSnapshot.docs) {
        try {
          final message = GroupChatMessage.fromFirestore(doc.data(), doc.id);

          // Search in message text
          if (message.message.toLowerCase().contains(lowerQuery)) {
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
