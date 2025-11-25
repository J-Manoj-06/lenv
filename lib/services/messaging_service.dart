import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';

class MessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch parent data for a given student ID
  /// Optional fallbacks: parentPhone to match by phone; if still not found, scans a small subset client-side.
  /// Returns: {parentId, parentName, parentEmail, parentPhotoUrl}
  Future<Map<String, dynamic>?> fetchParentForStudent(
    String studentId, {
    String? parentPhone,
    String? studentEmail,
  }) async {
    try {
      print('🔍 Looking for parent of student: $studentId');
      print('   Phone hint: ${parentPhone ?? "none"}');
      print('   Email hint: ${studentEmail ?? "none"}');

      // Strategy 1: Client-side scan of linkedStudents (most reliable)
      // This approach handles various data structures and field names
      print('📋 Strategy 1: Scanning parent linkedStudents arrays...');
      final allParents = await _firestore
          .collection('parents')
          .limit(100)
          .get();

      for (final doc in allParents.docs) {
        final data = doc.data();
        final linked = (data['linkedStudents'] as List?)?.cast<dynamic>() ?? [];

        for (final entry in linked) {
          if (entry is Map) {
            // Check multiple possible field names for student ID
            final entryId =
                (entry['id'] ??
                        entry['studentId'] ??
                        entry['uid'] ??
                        entry['student_id'])
                    ?.toString() ??
                '';

            if (entryId == studentId) {
              print('✅ Found parent via linkedStudents: ${doc.id}');
              return {
                'parentId': doc.id,
                'parentName': (data['parentName'] ?? data['name'] ?? 'Parent')
                    .toString(),
                'parentEmail': (data['email'] ?? '').toString(),
                'parentPhotoUrl': data['photoUrl']?.toString(),
                'phoneNumber': (data['phoneNumber'] ?? data['phone'] ?? '')
                    .toString(),
              };
            }
          }
        }
      }

      // Strategy 2: Match by phone number if available
      if (parentPhone != null && parentPhone.isNotEmpty) {
        print('📱 Strategy 2: Matching by phone: $parentPhone');

        // Try multiple possible phone field names
        for (final phoneField in ['phoneNumber', 'phone', 'parent_contact']) {
          final byPhone = await _firestore
              .collection('parents')
              .where(phoneField, isEqualTo: parentPhone)
              .limit(1)
              .get();

          if (byPhone.docs.isNotEmpty) {
            final parentDoc = byPhone.docs.first;
            final parentData = parentDoc.data();
            print('✅ Found parent via phone ($phoneField): ${parentDoc.id}');
            return {
              'parentId': parentDoc.id,
              'parentName':
                  (parentData['parentName'] ?? parentData['name'] ?? 'Parent')
                      .toString(),
              'parentEmail': (parentData['email'] ?? '').toString(),
              'parentPhotoUrl': parentData['photoUrl']?.toString(),
              'phoneNumber':
                  (parentData['phoneNumber'] ?? parentData['phone'] ?? '')
                      .toString(),
            };
          }
        }
      }

      // Strategy 3: Match by email pattern (if student email suggests parent email)
      if (studentEmail != null && studentEmail.isNotEmpty) {
        print('📧 Strategy 3: Attempting email pattern match...');
        // Some schools use patterns like student@school.com and parent@school.com
        // Or studentname.parent@school.com
        final emailParts = studentEmail.split('@');
        if (emailParts.length == 2) {
          final possibleParentEmails = [
            '${emailParts[0]}.parent@${emailParts[1]}',
            'parent.${emailParts[0]}@${emailParts[1]}',
          ];

          for (final possibleEmail in possibleParentEmails) {
            final byEmail = await _firestore
                .collection('parents')
                .where('email', isEqualTo: possibleEmail)
                .limit(1)
                .get();

            if (byEmail.docs.isNotEmpty) {
              final parentDoc = byEmail.docs.first;
              final parentData = parentDoc.data();
              print('✅ Found parent via email pattern: ${parentDoc.id}');
              return {
                'parentId': parentDoc.id,
                'parentName':
                    (parentData['parentName'] ?? parentData['name'] ?? 'Parent')
                        .toString(),
                'parentEmail': (parentData['email'] ?? '').toString(),
                'parentPhotoUrl': parentData['photoUrl']?.toString(),
                'phoneNumber':
                    (parentData['phoneNumber'] ?? parentData['phone'] ?? '')
                        .toString(),
              };
            }
          }
        }
      }

      print('❌ No parent found for student $studentId after all strategies');
      return null;
    } catch (e) {
      print('❌ Error fetching parent for student: $e');
      return null;
    }
  }

  /// Get or create a conversation between teacher and parent
  Future<String> getOrCreateConversation({
    required String teacherId,
    required String parentId,
    required String studentId,
    required String studentName,
    required String parentName,
    String? parentPhotoUrl,
  }) async {
    // Use deterministic ID: teacherId_parentId_studentId
    final conversationId = '${teacherId}_${parentId}_$studentId';

    final conversationRef = _firestore
        .collection('conversations')
        .doc(conversationId);
    final conversationSnap = await conversationRef.get();

    if (!conversationSnap.exists) {
      // Create new conversation
      await conversationRef.set({
        'teacherId': teacherId,
        'parentId': parentId,
        'studentId': studentId,
        'studentName': studentName,
        'parentName': parentName,
        if (parentPhotoUrl != null) 'parentPhotoUrl': parentPhotoUrl,
        'lastMessage': '',
        'lastSenderId': '',
        'lastTimestamp': FieldValue.serverTimestamp(),
        'unreadForTeacher': 0,
        'unreadForParent': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    return conversationId;
  }

  /// Send a message in a conversation
  Future<String?> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderRole, // 'teacher' or 'parent'
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final conversationRef = _firestore
        .collection('conversations')
        .doc(conversationId);
    final messagesRef = conversationRef.collection('messages');

    // Add message to subcollection and capture ID
    final docRef = await messagesRef.add({
      'senderId': senderId,
      'senderRole': senderRole,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'readByTeacher': senderRole == 'teacher',
      'readByParent': senderRole == 'parent',
    });

    // Update conversation metadata
    await conversationRef.update({
      'lastMessage': trimmed,
      'lastSenderId': senderId,
      'lastTimestamp': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (senderRole == 'teacher') 'unreadForParent': FieldValue.increment(1),
      if (senderRole == 'parent') 'unreadForTeacher': FieldValue.increment(1),
    });

    return docRef.id;
  }

  /// Stream messages for a conversation (real-time)
  Stream<List<ChatMessage>> streamMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => ChatMessage.fromFirestore(doc))
              .toList();
        });
  }

  /// Stream all conversations for a teacher (real-time)
  Stream<List<Conversation>> streamConversationsForTeacher(String teacherId) {
    return _firestore
        .collection('conversations')
        .where('teacherId', isEqualTo: teacherId)
        .orderBy('lastTimestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Conversation.fromFirestore(doc))
              .toList();
        });
  }

  /// Mark messages as read when opening conversation
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String userRole, // 'teacher' or 'parent'
  }) async {
    final conversationRef = _firestore
        .collection('conversations')
        .doc(conversationId);
    final messagesRef = conversationRef.collection('messages');

    // Find unread messages sent by the other party
    final unreadQuery = messagesRef
        .where(
          userRole == 'teacher' ? 'readByTeacher' : 'readByParent',
          isEqualTo: false,
        )
        .where(
          'senderRole',
          isEqualTo: userRole == 'teacher' ? 'parent' : 'teacher',
        );

    final unreadSnapshot = await unreadQuery.get();

    // Batch update
    final batch = _firestore.batch();
    for (final doc in unreadSnapshot.docs) {
      batch.update(doc.reference, {
        userRole == 'teacher' ? 'readByTeacher' : 'readByParent': true,
      });
    }

    // Reset unread count in conversation
    batch.update(conversationRef, {
      userRole == 'teacher' ? 'unreadForTeacher' : 'unreadForParent': 0,
    });

    await batch.commit();
  }

  /// Get conversation metadata
  Future<Conversation?> getConversation(String conversationId) async {
    try {
      final doc = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();
      if (!doc.exists) return null;
      return Conversation.fromFirestore(doc);
    } catch (e) {
      print('Error getting conversation: $e');
      return null;
    }
  }
}
