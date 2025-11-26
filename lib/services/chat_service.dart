import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _conversationId({
    required String schoolCode,
    required String teacherId,
    required String parentId,
    required String studentId,
  }) => '${schoolCode}__${teacherId}__${parentId}__${studentId}';

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
      tx.set(msgRef, {
        'text': text,
        'senderRole': senderRole,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'deliveredToParent': false,
        'deliveredToTeacher': false,
        'readByParent': false,
        'readByTeacher': false,
      });

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

    final q = await msgsRef
        .where('senderRole', isEqualTo: otherRole)
        .where(deliveredField, isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();

    if (q.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {deliveredField: true});
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

    final q = await msgsRef
        .where('senderRole', isEqualTo: otherRole)
        .where(readField, isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();

    if (q.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {readField: true, deliveredField: true});
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
}
