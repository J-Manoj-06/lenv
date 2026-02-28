import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/mindmap_service.dart';

class MindmapReviewPage extends StatefulWidget {
  final String classId;
  final String subjectId;
  final String teacherId;
  final String teacherName;
  final String subjectName;
  final String className;
  final String section;
  final String topic;
  final int topicCount;
  final String depthLevel;
  final String learningStyle;
  final Map<String, dynamic> initialStructure;
  final VoidCallback? onMindmapSent;

  const MindmapReviewPage({
    super.key,
    required this.classId,
    required this.subjectId,
    required this.teacherId,
    required this.teacherName,
    required this.subjectName,
    required this.className,
    required this.section,
    required this.topic,
    required this.topicCount,
    required this.depthLevel,
    required this.learningStyle,
    required this.initialStructure,
    this.onMindmapSent,
  });

  @override
  State<MindmapReviewPage> createState() => _MindmapReviewPageState();
}

class _MindmapReviewPageState extends State<MindmapReviewPage> {
  final MindmapService _mindmapService = MindmapService();
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  late Map<String, dynamic> _structure;
  bool _isWorking = false;
  final Set<String> _expanded = {'root'};

  static const double _canvasSize = 4600;
  static const double _nodeW = 166;
  static const double _nodeH = 58;
  static const Offset _rootCenter = Offset(220, _canvasSize / 2);

  @override
  void initState() {
    super.initState();
    print(
      '📋 [MindmapReviewPage] Initializing with structure keys: ${widget.initialStructure.keys}',
    );
    print(
      '📋 [MindmapReviewPage] Root title: ${widget.initialStructure['title']}',
    );
    _structure = _normalize(widget.initialStructure, widget.topic);
    print(
      '✅ [MindmapReviewPage] Normalized structure title: ${_structure['title']}',
    );
    print(
      '✅ [MindmapReviewPage] Children count: ${(_structure['children'] as List?)?.length ?? 0}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _center());
  }

  Map<String, dynamic> _normalize(
    Map<String, dynamic> raw,
    String fallbackTopic,
  ) {
    if (raw.containsKey('title') && raw.containsKey('children')) {
      return Map<String, dynamic>.from(raw);
    }

    final topic = (raw['topic'] ?? fallbackTopic).toString();
    final branches = (raw['branches'] as List?) ?? [];

    List<Map<String, dynamic>> convertChildren(dynamic children) {
      if (children is! List) return <Map<String, dynamic>>[];
      return children.map((child) {
        if (child is String) {
          return {'title': child, 'children': <Map<String, dynamic>>[]};
        }
        if (child is Map) {
          final map = Map<String, dynamic>.from(child);
          return {
            'title': (map['title'] ?? 'Node').toString(),
            'children': convertChildren(map['children']),
          };
        }
        return {'title': 'Node', 'children': <Map<String, dynamic>>[]};
      }).toList();
    }

    final normalizedBranches = branches.whereType<Map>().map((branch) {
      final b = Map<String, dynamic>.from(branch);
      return {
        'title': (b['title'] ?? 'Branch').toString(),
        'children': convertChildren(b['children']),
      };
    }).toList();

    return {'title': topic, 'children': normalizedBranches};
  }

  Future<void> _regenerate() async {
    setState(() => _isWorking = true);
    try {
      final raw = await _mindmapService.generateMindmapDraft(
        classId: widget.classId,
        subjectId: widget.subjectId,
        topic: widget.topic,
        topicCount: widget.topicCount,
        depthLevel: widget.depthLevel,
        learningStyle: widget.learningStyle,
        subjectName: widget.subjectName,
        className: widget.className,
        section: widget.section,
      );

      if (!mounted) return;
      setState(() {
        _structure = _normalize(raw, widget.topic);
        _expanded
          ..clear()
          ..add('root');
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Regenerate failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _send() async {
    setState(() => _isWorking = true);
    try {
      final topic = (_structure['title'] ?? widget.topic).toString();
      final mindmapId = await _mindmapService.publishMindmap(
        classId: widget.classId,
        subjectId: widget.subjectId,
        topic: topic,
        depthLevel: widget.depthLevel,
        learningStyle: widget.learningStyle,
        topicCount: widget.topicCount,
        structure: _structure,
      );

      final children = (_structure['children'] as List?) ?? [];
      final preview = children
          .whereType<Map>()
          .map((e) => (e['title'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .take(4)
          .toList();

      await _mindmapService.sendMindmapMessage(
        classId: widget.classId,
        subjectId: widget.subjectId,
        senderId: widget.teacherId,
        senderName: widget.teacherName,
        mindmapId: mindmapId,
        topic: topic,
        previewNodes: preview,
      );

      if (!mounted) return;
      widget.onMindmapSent?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mindmap sent to students')));
      Navigator.pop(context);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  void _center() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.of(context).size;
    final targetRootX = size.width * 0.30;
    final dx = targetRootX - _rootCenter.dx;
    final dy = (size.height / 2) - _rootCenter.dy;

    _transformController.value = Matrix4.identity()..translate(dx, dy);
  }

  List<_NodePos> _layout() {
    final nodes = <_NodePos>[];

    void walk(
      Map<String, dynamic> node,
      String path,
      Offset center,
      int level,
      String? parent,
      double spread,
    ) {
      nodes.add(
        _NodePos(
          path: path,
          node: node,
          center: center,
          level: level,
          parentPath: parent,
        ),
      );

      if (!_expanded.contains(path)) return;
      final children =
          (node['children'] as List?)?.whereType<Map>().toList() ?? <Map>[];
      if (children.isEmpty) return;

      final count = children.length;
      // HORIZONTAL LAYOUT: Children expand to the RIGHT (left to right)
      final x = center.dx + 220; // Move right instead of down
      final startY =
          center.dy - ((count - 1) * spread / 2); // Spread vertically
      final nextSpread = math.max(140, spread * 0.75).toDouble();

      for (int i = 0; i < count; i++) {
        walk(
          Map<String, dynamic>.from(children[i]),
          '$path/$i',
          Offset(x, startY + (i * spread)), // Horizontal positioning
          level + 1,
          path,
          nextSpread,
        );
      }
    }

    // Start root node on left side, centered vertically for horizontal expansion
    walk(_structure, 'root', _rootCenter, 0, null, 260);
    return nodes;
  }

  Future<void> _editNode(_NodePos nodePos) async {
    final titleCtrl = TextEditingController(
      text: (nodePos.node['title'] ?? '').toString(),
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF191922),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Node title'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'add'),
                      child: const Text('Add Child'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: nodePos.path == 'root'
                          ? null
                          : () => Navigator.pop(ctx, 'delete'),
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (action == null) return;

    setState(() {
      final node = _nodeByPath(_structure, nodePos.path);
      if (node == null) return;

      if (action == 'save') {
        node['title'] = titleCtrl.text.trim().isEmpty
            ? 'Node'
            : titleCtrl.text.trim();
      } else if (action == 'add') {
        final children =
            (node['children'] as List?) ?? <Map<String, dynamic>>[];
        children.add({
          'title': 'New Node',
          'children': <Map<String, dynamic>>[],
        });
        node['children'] = children;
        _expanded.add(nodePos.path);
      } else if (action == 'delete') {
        _deleteNode(_structure, nodePos.path);
      }
    });
  }

  Map<String, dynamic>? _nodeByPath(Map<String, dynamic> root, String path) {
    if (path == 'root') return root;
    final parts = path.split('/').skip(1).map(int.parse).toList();
    Map<String, dynamic> current = root;
    for (final idx in parts) {
      final children =
          (current['children'] as List?)?.whereType<Map>().toList() ?? <Map>[];
      if (idx < 0 || idx >= children.length) return null;
      current = Map<String, dynamic>.from(children[idx]);
      _writeNodeByPath(
        root,
        path.split('/').take(parts.indexOf(idx) + 2).join('/'),
        current,
      );
    }
    return _writeNodeByPath(root, path, current);
  }

  Map<String, dynamic>? _writeNodeByPath(
    Map<String, dynamic> root,
    String path,
    Map<String, dynamic> replacement,
  ) {
    if (path == 'root') {
      root
        ..clear()
        ..addAll(replacement);
      return root;
    }
    final parts = path.split('/').skip(1).map(int.parse).toList();
    Map<String, dynamic> current = root;
    for (int i = 0; i < parts.length; i++) {
      final idx = parts[i];
      final children =
          (current['children'] as List?) ?? <Map<String, dynamic>>[];
      if (idx < 0 || idx >= children.length) return null;
      if (i == parts.length - 1) {
        children[idx] = replacement;
      } else {
        current = Map<String, dynamic>.from(children[idx]);
      }
      current['children'] = children;
    }
    return replacement;
  }

  void _deleteNode(Map<String, dynamic> root, String path) {
    final parts = path.split('/').skip(1).map(int.parse).toList();
    if (parts.isEmpty) return;

    Map<String, dynamic> parent = root;
    for (int i = 0; i < parts.length - 1; i++) {
      final children =
          (parent['children'] as List?)?.whereType<Map>().toList() ?? <Map>[];
      parent = Map<String, dynamic>.from(children[parts[i]]);
    }

    final children = (parent['children'] as List?) ?? <Map<String, dynamic>>[];
    children.removeAt(parts.last);
    parent['children'] = children;
    _writeNodeByPath(
      root,
      path.split('/').take(parts.length).join('/').isEmpty
          ? 'root'
          : path.split('/').take(parts.length).join('/'),
      parent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _layout();
    final byPath = {for (final n in nodes) n.path: n};

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text((_structure['title'] ?? widget.topic).toString()),
      ),
      body: Column(
        children: [
          Expanded(
            child: SizedBox.expand(
              key: _viewerKey,
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.4,
                maxScale: 2.8,
                constrained: false,
                child: Container(
                  width: _canvasSize,
                  height: _canvasSize,
                  color: const Color(0xFF0D0D12),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ConnPainter(nodes: nodes, byPath: byPath),
                        ),
                      ),
                      ...nodes.map((n) {
                        final hasChildren =
                            ((n.node['children'] as List?) ?? []).isNotEmpty;
                        final isExpanded = _expanded.contains(n.path);
                        final nodeTitle = (n.node['title'] ?? 'Node')
                            .toString();

                        final color = n.level == 0
                            ? const Color(0xFF4775FF)
                            : n.level == 1
                            ? const Color(0xFF2DBF73)
                            : const Color(0xFF8E5BFF);

                        return Positioned(
                          left: n.center.dx - (_nodeW / 2),
                          top: n.center.dy - (_nodeH / 2),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (hasChildren) {
                                  if (isExpanded) {
                                    _expanded.remove(n.path);
                                  } else {
                                    _expanded.add(n.path);
                                  }
                                }
                              });
                            },
                            onLongPress: () => _editNode(n),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: _nodeW,
                              height: _nodeH,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      nodeTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (hasChildren)
                                    Icon(
                                      isExpanded
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            color: const Color(0xFF12121A),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isWorking ? null : _regenerate,
                        child: const Text('Regenerate'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isWorking ? null : _send,
                        child: _isWorking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Send to Students'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 0),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NodePos {
  final String path;
  final Map<String, dynamic> node;
  final Offset center;
  final int level;
  final String? parentPath;

  const _NodePos({
    required this.path,
    required this.node,
    required this.center,
    required this.level,
    required this.parentPath,
  });
}

class _ConnPainter extends CustomPainter {
  final List<_NodePos> nodes;
  final Map<String, _NodePos> byPath;

  const _ConnPainter({required this.nodes, required this.byPath});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x997A5CFF)
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke;

    for (final node in nodes) {
      if (node.parentPath == null) continue;
      final parent = byPath[node.parentPath!];
      if (parent == null) continue;

      final start = Offset(parent.center.dx + 78, parent.center.dy);
      final end = Offset(node.center.dx - 78, node.center.dy);
      final c1 = Offset(start.dx + 56, start.dy);
      final c2 = Offset(end.dx - 56, end.dy);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnPainter oldDelegate) {
    return oldDelegate.nodes != nodes;
  }
}
