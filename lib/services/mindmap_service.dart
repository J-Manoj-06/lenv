import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/mindmap_model.dart';

class MindmapGenerationResult {
  final String mindmapId;
  final String topic;
  final List<String> previewNodes;

  const MindmapGenerationResult({
    required this.mindmapId,
    required this.topic,
    required this.previewNodes,
  });
}

class MindmapService {
  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  MindmapService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
    : _functions = functions ?? FirebaseFunctions.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  Future<MindmapGenerationResult> generateMindmap({
    required String classId,
    required String subjectId,
    required String topic,
    required int topicCount,
    required String depthLevel,
    required String learningStyle,
  }) async {
    final callable = _functions.httpsCallable(
      'generateMindmap',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
    );

    final result = await callable.call(<String, dynamic>{
      'classId': classId,
      'subjectId': subjectId,
      'topic': topic.trim(),
      'topicCount': topicCount,
      'depthLevel': depthLevel,
      'learningStyle': learningStyle,
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    final preview =
        (data['previewNodes'] as List?)?.map((e) => e.toString()).toList() ??
        <String>[];

    return MindmapGenerationResult(
      mindmapId: (data['mindmapId'] ?? '').toString(),
      topic: (data['topic'] ?? topic).toString(),
      previewNodes: preview,
    );
  }

  Future<void> sendMindmapMessage({
    required String classId,
    required String subjectId,
    required String senderId,
    required String senderName,
    required String mindmapId,
    required String topic,
    required List<String> previewNodes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _firestore
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subjectId)
        .collection('messages')
        .add({
          'senderId': senderId,
          'senderName': senderName,
          'message': 'Mindmap: $topic',
          'content': 'Mindmap: $topic',
          'type': 'mindmap',
          'mindmapId': mindmapId,
          'mindmapTopic': topic,
          'previewNodes': previewNodes,
          'timestamp': now,
          'isDeleted': false,
          'classId': classId,
          'subjectId': subjectId,
        });

    await _firestore
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subjectId)
        .set({'lastActivity': now}, SetOptions(merge: true));
  }

  Future<MindmapModel?> getMindmapById(String mindmapId) async {
    final doc = await _firestore
        .collection('group_mindmaps')
        .doc(mindmapId)
        .get();

    if (!doc.exists) return null;
    return MindmapModel.fromFirestore(doc);
  }
}
