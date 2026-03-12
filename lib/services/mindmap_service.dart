import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

import '../models/mindmap_model.dart';

class MindmapGenerationResult {
  final String mindmapId;
  final String topic;
  final List<String> previewNodes;
  final Map<String, dynamic>? structure;

  const MindmapGenerationResult({
    required this.mindmapId,
    required this.topic,
    required this.previewNodes,
    this.structure,
  });
}

class MindmapService {
  final FirebaseFirestore _firestore;
  static const String _workerUrl =
      'https://deepseek-ai-worker.giridharannj.workers.dev';

  MindmapService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Generate mindmap draft (preview only)
  Future<Map<String, dynamic>> generateMindmapDraft({
    required String classId,
    required String subjectId,
    required String topic,
    required int topicCount,
    required String depthLevel,
    required String learningStyle,
    required String subjectName,
    required String className,
    required String section,
  }) async {
    try {

      final body = jsonEncode({
        'topic': topic.trim(),
        'topicCount': topicCount,
        'depthLevel': depthLevel,
        'learningStyle': learningStyle,
        'subject': subjectName.isNotEmpty ? subjectName : 'General',
        'standard': className.isNotEmpty ? className : '',
        'section': section.isNotEmpty ? section : '',
      });

      final response = await http
          .post(
            Uri.parse('$_workerUrl/mindmap/generate'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));


      if (response.statusCode != 200) {
        final error = _parseError(response);
        throw Exception('HTTP ${response.statusCode}: $error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final structure = data['structure'];

      if (structure is! Map) {
        throw Exception(
          'Invalid AI mindmap structure: expected Map, got ${structure.runtimeType}',
        );
      }

      // Extract the root from the structure
      final root = structure['root'] as Map<String, dynamic>?;
      if (root == null) {
        throw Exception('Invalid mindmap structure: missing root node');
      }

      return root;
    } on http.ClientException catch (e) {
      throw Exception('Network error: ${e.message}');
    } on TimeoutException catch (e) {
      throw Exception('Request timeout: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  /// Publish mindmap (save to Firestore)
  Future<String> publishMindmap({
    required String classId,
    required String subjectId,
    required String topic,
    required String depthLevel,
    required String learningStyle,
    required int topicCount,
    required Map<String, dynamic> structure,
  }) async {
    try {

      // Wrap root node with proper structure for worker validation
      final publishStructure = {
        'root': structure, // Wrap the root node
      };

      final response = await http
          .post(
            Uri.parse('$_workerUrl/mindmap/publish'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'classId': classId,
              'subjectId': subjectId,
              'topic': topic,
              'depthLevel': depthLevel,
              'learningStyle': learningStyle,
              'topicCount': topicCount,
              'structure': publishStructure,
            }),
          )
          .timeout(const Duration(seconds: 65));


      if (response.statusCode != 200) {
        final error = _parseError(response);
        throw Exception('Failed to publish mindmap: $error');
      }


      // Generate local ID for now
      final mindmapId = 'mindmap_${DateTime.now().millisecondsSinceEpoch}';

      // Save structure to Firestore for later retrieval
      await _firestore.collection('group_mindmaps').doc(mindmapId).set({
        'classId': classId,
        'subjectId': subjectId,
        'topic': topic,
        'structure': structure,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return mindmapId;
    } on http.ClientException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      rethrow;
    }
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

    // Step 1: Add message to messages collection
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

    // Step 2: Update subject lastActivity
    await _firestore
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subjectId)
        .set({'lastActivity': now}, SetOptions(merge: true));

    // Step 3: Update teacher_groups index for real-time unread counts
    try {
      final classDoc = await _firestore
          .collection('classes')
          .doc(classId)
          .get();

      if (classDoc.exists) {
        final classData = classDoc.data();
        if (classData != null) {
          final subjectTeachers =
              classData['subjectTeachers'] as Map<String, dynamic>?;
          if (subjectTeachers != null) {
            final subjectData =
                subjectTeachers[subjectId] as Map<String, dynamic>?;
            if (subjectData != null) {
              final teacherId = subjectData['teacherId'] as String?;
              if (teacherId != null && senderId != teacherId) {
                // Only increment unread if message is from student (not teacher)
                final groupId = '${classId}_$subjectId';
                final messagePreview = 'Mindmap: $topic';

                await _firestore
                    .collection('teacher_groups')
                    .doc(teacherId)
                    .set({
                      'groups': {
                        groupId: {
                          'unreadCount': FieldValue.increment(1),
                          'lastMessage': messagePreview,
                          'lastMessageAt': FieldValue.serverTimestamp(),
                          'lastMessageBy': senderName,
                          'classId': classId,
                          'subjectId': subjectId,
                          'className': classData['className'] ?? '',
                          'section': classData['section'] ?? '',
                          'subject': subjectId,
                          'teacherName': subjectData['teacherName'] ?? '',
                          'schoolCode': classData['schoolCode'] ?? '',
                        },
                      },
                    }, SetOptions(merge: true));
              }
            }
          }
        }
      }
    } catch (e) {
      // Continue anyway - message was still sent
    }
  }

  Future<MindmapModel?> getMindmapById(String mindmapId) async {
    final doc = await _firestore
        .collection('group_mindmaps')
        .doc(mindmapId)
        .get();

    if (!doc.exists) return null;
    return MindmapModel.fromFirestore(doc);
  }

  String _parseError(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['error'] ?? data['message'] ?? response.statusCode.toString();
    } catch (_) {
      return response.statusCode.toString();
    }
  }
}
