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

  static const String _curriculumGuardrails =
      'You are an educational curriculum assistant for the Lenv learning platform. '
      'Generate a structured mind map strictly based on the student\'s academic level and syllabus. '
      'Rules: (1) match grade level exactly, (2) avoid advanced/college concepts, '
      '(3) follow school curriculum patterns (CBSE/ICSE/State Board), '
      '(4) keep nodes very short, keyword-style, (5) textbook-aligned topics only, '
      '(6) no long explanations, (7) max depth 3, (8) max 5 children per node, '
      '(9) optimize for visual revision, (10) avoid unnecessary theory. '
      'Return JSON only.';

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
      final gradeLevel = _extractGradeLevel(className);
      final prompt = _buildCurriculumPrompt(
        topic: topic,
        gradeLevel: gradeLevel,
        subjectName: subjectName,
        className: className,
        section: section,
        topicCount: topicCount,
        depthLevel: depthLevel,
        learningStyle: learningStyle,
      );

      final body = jsonEncode({
        'topic': topic.trim(),
        'topicCount': topicCount,
        'depthLevel': depthLevel,
        'learningStyle': learningStyle,
        'subject': subjectName.isNotEmpty ? subjectName : 'General',
        'standard': className.isNotEmpty ? className : '',
        'section': section.isNotEmpty ? section : '',
        'gradeLevel': gradeLevel,
        'guardrails': _curriculumGuardrails,
        'instructionPrompt': prompt,
        'responseFormat': {
          'title': 'Main Topic',
          'nodes': [
            {
              'name': 'Subtopic',
              'children': [
                {
                  'name': 'Concept',
                  'children': [
                    {'name': 'Example or Key Point'},
                  ],
                },
              ],
            },
          ],
        },
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
      final root = _extractNormalizedRoot(
        data,
        fallbackTopic: topic,
        topicCount: topicCount,
      );
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

  String _extractGradeLevel(String className) {
    final match = RegExp(r'\d+').firstMatch(className);
    if (match != null) return match.group(0)!;
    return className.trim().isEmpty ? 'Unknown' : className.trim();
  }

  String _buildCurriculumPrompt({
    required String topic,
    required String gradeLevel,
    required String subjectName,
    required String className,
    required String section,
    required int topicCount,
    required String depthLevel,
    required String learningStyle,
  }) {
    return '''
$_curriculumGuardrails

Target:
- Topic: ${topic.trim()}
- Grade/Standard: ${className.isNotEmpty ? className : gradeLevel}
- Section: ${section.isNotEmpty ? section : '-'}
- Subject: ${subjectName.isNotEmpty ? subjectName : 'General'}
- Main branches requested: $topicCount
- Depth preference: $depthLevel
- Learning style: $learningStyle

Strict output JSON shape:
{
  "title": "Main Topic",
  "nodes": [
    {
      "name": "Subtopic",
      "children": [
        {
          "name": "Concept",
          "children": [
            {"name": "Example or Key Point"}
          ]
        }
      ]
    }
  ]
}
''';
  }

  Map<String, dynamic> _extractNormalizedRoot(
    Map<String, dynamic> data, {
    required String fallbackTopic,
    required int topicCount,
  }) {
    final dynamic primary = data['structure'] ?? data['mindmap'] ?? data;
    final root = _normalizeToRoot(primary, fallbackTopic: fallbackTopic);
    _enforceTreeLimits(root, maxDepth: 3, maxChildren: 5, currentDepth: 0);
    _trimBranchCount(root, topicCount);
    return root;
  }

  Map<String, dynamic> _normalizeToRoot(
    dynamic payload, {
    required String fallbackTopic,
  }) {
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);

      final root = map['root'];
      if (root is Map) {
        return _normalizeNode(
          Map<String, dynamic>.from(root),
          fallbackTitle: fallbackTopic,
        );
      }

      if (map.containsKey('title') || map.containsKey('name')) {
        return _normalizeNode(map, fallbackTitle: fallbackTopic);
      }

      if (map.containsKey('nodes')) {
        return {
          'title': _sanitizeLabel(fallbackTopic),
          'children': _normalizeChildren(map['nodes']),
        };
      }
    }

    if (payload is List) {
      return {
        'title': _sanitizeLabel(fallbackTopic),
        'children': _normalizeChildren(payload),
      };
    }

    return {
      'title': _sanitizeLabel(fallbackTopic),
      'children': <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _normalizeNode(
    Map<String, dynamic> node, {
    required String fallbackTitle,
  }) {
    final title = _sanitizeLabel(
      (node['title'] ?? node['name'] ?? node['topic'] ?? fallbackTitle)
          .toString(),
    );

    final rawChildren = node['children'] ?? node['nodes'] ?? const [];
    return {'title': title, 'children': _normalizeChildren(rawChildren)};
  }

  List<Map<String, dynamic>> _normalizeChildren(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.map((child) {
      if (child is String) {
        return {
          'title': _sanitizeLabel(child),
          'children': <Map<String, dynamic>>[],
        };
      }
      if (child is Map) {
        return _normalizeNode(
          Map<String, dynamic>.from(child),
          fallbackTitle: 'Node',
        );
      }
      return {'title': 'Node', 'children': <Map<String, dynamic>>[]};
    }).toList();
  }

  void _enforceTreeLimits(
    Map<String, dynamic> node, {
    required int maxDepth,
    required int maxChildren,
    required int currentDepth,
  }) {
    final children =
        (node['children'] as List?)?.whereType<Map>().toList() ?? <Map>[];

    if (currentDepth >= maxDepth) {
      node['children'] = <Map<String, dynamic>>[];
      return;
    }

    final limited = children
        .take(maxChildren)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    node['children'] = limited;

    for (final child in limited) {
      _enforceTreeLimits(
        child,
        maxDepth: maxDepth,
        maxChildren: maxChildren,
        currentDepth: currentDepth + 1,
      );
    }
  }

  void _trimBranchCount(Map<String, dynamic> root, int topicCount) {
    final children =
        (root['children'] as List?)?.whereType<Map>().toList() ?? <Map>[];
    if (children.isEmpty) return;
    final capped = topicCount.clamp(1, 5);
    root['children'] = children
        .take(capped)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _sanitizeLabel(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'Node';
    if (cleaned.length <= 56) return cleaned;
    return '${cleaned.substring(0, 56).trim()}…';
  }
}
