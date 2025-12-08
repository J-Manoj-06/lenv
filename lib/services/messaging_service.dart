import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';

class MessagingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch parent data for a given student ID
  /// ✅ OPTIMIZED: Uses student.parentId field (2 reads instead of 100+)
  /// Returns: {parentId, parentName, parentEmail, parentPhotoUrl, parentAuthUid}
  Future<Map<String, dynamic>?> fetchParentForStudent(
    String studentId, {
    String? parentPhone,
    String? studentEmail,
  }) async {
    try {
      print('🔍 Looking for parent of student: $studentId');

      // ✅ OPTIMIZATION: Strategy 1 - Direct lookup via student.parentId
      print('📋 Strategy 1: Reading parent from student document...');
      final studentDoc = await _firestore
          .collection('students')
          .doc(studentId)
          .get();

      if (studentDoc.exists && studentDoc.data() != null) {
        final studentData = studentDoc.data()!;
        final parentId = studentData['parentId'] as String?;
        final parentAuthUid = studentData['parentAuthUid'] as String?;
        final parentName = studentData['parentName'] as String?;
        final parentEmail = studentData['parentEmail'] as String?;
        final parentPhone = studentData['parentPhone'] as String?;

        if (parentId != null && parentId.isNotEmpty) {
          print('✅ Found parent via student.parentId: $parentId');

          // If we have parentAuthUid, return immediately (1 read total)
          if (parentAuthUid != null && parentAuthUid.isNotEmpty) {
            print('✅ Using cached parentAuthUid from student doc');
            return {
              'parentId': parentId,
              'parentAuthUid': parentAuthUid,
              'parentName': parentName ?? 'Parent',
              'parentEmail': parentEmail ?? '',
              'parentPhotoUrl': null,
              'phoneNumber': parentPhone ?? '',
            };
          }

          // Otherwise, fetch parent document for photoUrl (2 reads total)
          final parentDoc = await _firestore
              .collection('parents')
              .doc(parentId)
              .get();

          if (parentDoc.exists && parentDoc.data() != null) {
            final parentData = parentDoc.data()!;
            print('✅ Fetched parent document for additional details');

            return {
              'parentId': parentId,
              'parentAuthUid': parentAuthUid ?? '',
              'parentName':
                  parentName ??
                  parentData['parentName'] ??
                  parentData['name'] ??
                  'Parent',
              'parentEmail': parentEmail ?? parentData['email'] ?? '',
              'parentPhotoUrl': parentData['photoUrl']?.toString(),
              'phoneNumber':
                  parentPhone ??
                  parentData['phoneNumber'] ??
                  parentData['phone'] ??
                  '',
            };
          }

          // Parent doc doesn't exist, use student data
          return {
            'parentId': parentId,
            'parentAuthUid': parentAuthUid ?? '',
            'parentName': parentName ?? 'Parent',
            'parentEmail': parentEmail ?? '',
            'parentPhotoUrl': null,
            'phoneNumber': parentPhone ?? '',
          };
        }
      }

      print(
        '⚠️ Student document has no parentId field, falling back to legacy scan',
      );

      // ✅ FALLBACK: Legacy method - scan parents (only if parentId not set)
      print(
        '📋 Strategy 2 (Fallback): Scanning parent linkedStudents arrays...',
      );
      final allParents = await _firestore
          .collection('parents')
          .limit(100)
          .get();

      for (final doc in allParents.docs) {
        final data = doc.data();
        final linked = (data['linkedStudents'] as List?)?.cast<dynamic>() ?? [];

        for (final entry in linked) {
          if (entry is Map) {
            final entryId =
                (entry['id'] ??
                        entry['studentId'] ??
                        entry['uid'] ??
                        entry['student_id'])
                    ?.toString() ??
                '';

            if (entryId == studentId) {
              print('✅ Found parent via linkedStudents: ${doc.id}');
              final parentEmail = (data['email'] ?? '').toString();
              String? parentAuthUid;
              if (parentEmail.isNotEmpty) {
                final usersSnap = await _firestore
                    .collection('users')
                    .where('email', isEqualTo: parentEmail)
                    .limit(1)
                    .get();
                if (usersSnap.docs.isNotEmpty) {
                  final u = usersSnap.docs.first;
                  final uData = u.data();
                  parentAuthUid =
                      (uData['uid']?.toString().trim().isNotEmpty ?? false)
                      ? uData['uid']?.toString()
                      : u.id;
                }
              }

              return {
                'parentId': doc.id,
                'parentAuthUid': parentAuthUid,
                'parentName': (data['parentName'] ?? data['name'] ?? 'Parent')
                    .toString(),
                'parentEmail': parentEmail,
                'parentPhotoUrl': data['photoUrl']?.toString(),
                'phoneNumber': (data['phoneNumber'] ?? data['phone'] ?? '')
                    .toString(),
              };
            }
          }
        }
      }

      // Strategy 3: Match by phone number if available
      if (parentPhone != null && parentPhone.isNotEmpty) {
        print('📱 Strategy 3: Matching by phone: $parentPhone');

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
            final parentEmail = (parentData['email'] ?? '').toString();
            String? parentAuthUid;
            if (parentEmail.isNotEmpty) {
              final usersSnap = await _firestore
                  .collection('users')
                  .where('email', isEqualTo: parentEmail)
                  .limit(1)
                  .get();
              if (usersSnap.docs.isNotEmpty) {
                final u = usersSnap.docs.first;
                final uData = u.data();
                parentAuthUid =
                    (uData['uid']?.toString().trim().isNotEmpty ?? false)
                    ? uData['uid']?.toString()
                    : u.id;
              }
            }

            return {
              'parentId': parentDoc.id,
              'parentAuthUid': parentAuthUid,
              'parentName':
                  (parentData['parentName'] ?? parentData['name'] ?? 'Parent')
                      .toString(),
              'parentEmail': parentEmail,
              'parentPhotoUrl': parentData['photoUrl']?.toString(),
              'phoneNumber':
                  (parentData['phoneNumber'] ?? parentData['phone'] ?? '')
                      .toString(),
            };
          }
        }
      }

      // Strategy 4: Match by email pattern (if student email suggests parent email)
      if (studentEmail != null && studentEmail.isNotEmpty) {
        print('📧 Strategy 4: Attempting email pattern match...');
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
              // Resolve parent auth UID
              final parentEmail = (parentData['email'] ?? '').toString();
              String? parentAuthUid;
              if (parentEmail.isNotEmpty) {
                final usersSnap = await _firestore
                    .collection('users')
                    .where('email', isEqualTo: parentEmail)
                    .limit(1)
                    .get();
                if (usersSnap.docs.isNotEmpty) {
                  final u = usersSnap.docs.first;
                  final uData = u.data();
                  parentAuthUid =
                      (uData['uid']?.toString().trim().isNotEmpty ?? false)
                      ? uData['uid']?.toString()
                      : u.id;
                  print('✅ Resolved parent auth UID via users: $parentAuthUid');
                }
              }

              return {
                'parentId': parentDoc.id,
                'parentAuthUid': parentAuthUid,
                'parentName':
                    (parentData['parentName'] ?? parentData['name'] ?? 'Parent')
                        .toString(),
                'parentEmail': parentEmail,
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
