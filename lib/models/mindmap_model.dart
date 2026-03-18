import 'package:cloud_firestore/cloud_firestore.dart';

class MindmapNode {
  final String title;
  final List<MindmapNode> children;

  const MindmapNode({required this.title, this.children = const []});

  factory MindmapNode.fromJson(Map<String, dynamic> json) {
    final childrenRaw = json['children'];
    final parsedChildren = childrenRaw is List
        ? childrenRaw
              .whereType<Map>()
              .map((e) => MindmapNode.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <MindmapNode>[];

    return MindmapNode(
      title: (json['title'] ?? '').toString(),
      children: parsedChildren,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'children': children.map((e) => e.toJson()).toList(),
    };
  }
}

class MindmapModel {
  final String id;
  final String groupId;
  final String classId;
  final String subjectId;
  final String topic;
  final MindmapNode root;
  final String createdBy;
  final DateTime? createdAt;

  const MindmapModel({
    required this.id,
    required this.groupId,
    required this.classId,
    required this.subjectId,
    required this.topic,
    required this.root,
    required this.createdBy,
    required this.createdAt,
  });

  factory MindmapModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};

    final structure = Map<String, dynamic>.from(
      (data['structure'] as Map?) ??
          {'title': data['topic'] ?? 'Mindmap', 'children': const []},
    );

    final createdAtRaw = data['created_at'];
    DateTime? createdAt;
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else if (createdAtRaw is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtRaw);
    }

    return MindmapModel(
      id: doc.id,
      groupId: (data['group_id'] ?? '').toString(),
      classId: (data['class_id'] ?? '').toString(),
      subjectId: (data['subject_id'] ?? '').toString(),
      topic: (data['topic'] ?? 'Mindmap').toString(),
      root: MindmapNode.fromJson(structure),
      createdBy: (data['created_by'] ?? '').toString(),
      createdAt: createdAt,
    );
  }
}
