import 'dart:math' as math;

import 'package:flutter/gestures.dart';
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
  final Map<String, Offset> _manualNodeOffsets = <String, Offset>{};
  String? _draggingPath;

  static const double _canvasSize = 4600;
  static const double _nodeW = 166;
  static const double _nodeH = 58;
  static const double _minScale = 0.5;
  static const double _maxScale = 2.5;
  static const Offset _rootCenter = Offset(220, _canvasSize / 2);
  static const Size _miniMapSize = Size(140, 100);

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

    // Auto-expand all nodes on initial load
    _expandAllNodes(_structure, 'root');
    print('✅ [MindmapReviewPage] Expanded nodes: $_expanded');
    print('✅ [MindmapReviewPage] Total expanded count: ${_expanded.length}');

    // Initialize with centered view immediately
    _initializeCenteredView();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _center();
      setState(() {}); // Force rebuild after centering
    });
  }

  void _initializeCenteredView() {
    // Pre-calculate initial centered position to show nodes immediately
    // We need to translate so root at (220, 2300) appears in visible viewport
    // Assume screen size ~540 x 960 (will be adjusted in postFrameCallback)
    const estimatedScreenWidth = 540.0;
    const estimatedScreenHeight = 960.0;

    // Calculate translation to center the root node
    final targetRootX = estimatedScreenWidth * 0.30; // 30% from left
    final targetRootY = estimatedScreenHeight / 2; // Middle of screen

    final dx = targetRootX - _rootCenter.dx;
    final dy = targetRootY - _rootCenter.dy;

    _transformController.value = Matrix4.identity()..translate(dx, dy);
    print('🎯 [Init] Centered view: dx=$dx, dy=$dy');
  }

  void _expandAllNodes(Map<String, dynamic> node, String path) {
    _expanded.add(path);
    final children =
        (node['children'] as List?)?.whereType<Map>().toList() ?? <Map>[];
    print(
      '📍 [MindmapReviewPage] Expanding path: $path, children: ${children.length}',
    );
    for (int i = 0; i < children.length; i++) {
      final child = Map<String, dynamic>.from(children[i]);
      final childPath = '$path/$i';
      _expandAllNodes(child, childPath);
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
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
        _manualNodeOffsets.clear();
        _draggingPath = null;
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
    // Handle case where box hasn't been laid out yet
    final size = box?.hasSize == true ? box!.size : MediaQuery.of(context).size;
    final targetRootX = size.width * 0.30;
    final dx = targetRootX - _rootCenter.dx;
    final dy = (size.height / 2) - _rootCenter.dy;

    _transformController.value = Matrix4.identity()..translate(dx, dy);
  }

  double _currentScale() {
    return _transformController.value.getMaxScaleOnAxis();
  }

  Rect _viewportInScene() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    // Handle case where box hasn't been laid out yet
    final size = box?.hasSize == true ? box!.size : MediaQuery.of(context).size;
    final topLeft = _transformController.toScene(Offset.zero);
    final bottomRight = _transformController.toScene(
      Offset(size.width, size.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _zoomBy(double step) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    // Handle case where box hasn't been laid out yet
    final size = box?.hasSize == true ? box!.size : MediaQuery.of(context).size;
    _zoomAt(Offset(size.width / 2, size.height / 2), 1 + step);
  }

  void _zoomAt(Offset viewportFocalPoint, double factor) {
    final oldScale = _currentScale();
    final nextScale = (oldScale * factor).clamp(_minScale, _maxScale);
    if ((nextScale - oldScale).abs() < 0.0001) return;

    final sceneFocal = _transformController.toScene(viewportFocalPoint);
    final next = Matrix4.identity()
      ..translate(viewportFocalPoint.dx, viewportFocalPoint.dy)
      ..scale(nextScale)
      ..translate(-sceneFocal.dx, -sceneFocal.dy);

    _transformController.value = next;
    setState(() {});
  }

  void _moveViewportCenterToScene(Offset targetSceneCenter) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.of(context).size;
    final scale = _currentScale();
    final tx = (size.width / 2) - (targetSceneCenter.dx * scale);
    final ty = (size.height / 2) - (targetSceneCenter.dy * scale);
    _transformController.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
    setState(() {});
  }

  Offset _clampCenter(Offset center) {
    const double pad = 20;
    return Offset(
      center.dx.clamp(_nodeW / 2 + pad, _canvasSize - (_nodeW / 2 + pad)),
      center.dy.clamp(_nodeH / 2 + pad, _canvasSize - (_nodeH / 2 + pad)),
    );
  }

  List<_NodePos> _layout({bool applyManualOffsets = true}) {
    final nodes = <_NodePos>[];
    print('🎨 [Layout] Starting layout calculation, _expanded: $_expanded');
    print('🎨 [Layout] Structure title: ${_structure['title']}');

    void walk(
      Map<String, dynamic> node,
      String path,
      Offset center,
      int level,
      String? parent,
      double spread,
    ) {
      print(
        '🚶 [Layout Walk] path: $path, title: ${node['title']}, expanded: ${_expanded.contains(path)}',
      );
      nodes.add(
        _NodePos(
          path: path,
          node: node,
          center: applyManualOffsets
              ? center + (_manualNodeOffsets[path] ?? Offset.zero)
              : center,
          level: level,
          parentPath: parent,
        ),
      );

      if (!_expanded.contains(path)) {
        print('  ⏸️ [Layout Walk] Skipping children - not expanded');
        return;
      }
      final children =
          (node['children'] as List?)?.whereType<Map>().toList() ?? <Map>[];
      if (children.isEmpty) {
        print('  ⏸️ [Layout Walk] Skipping - no children');
        return;
      }

      print('  ➡️ [Layout Walk] Processing ${children.length} children');
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
    print('🎨 [Layout] Finished, total nodes: ${nodes.length}');
    return nodes;
  }

  void _dragNode(_NodePos nodePos, DragUpdateDetails details) {
    final scale = _currentScale();
    if (scale <= 0) return;

    final deltaScene = details.delta / scale;
    if (deltaScene == Offset.zero) return;

    final baseNodes = _layout(applyManualOffsets: false);
    final baseByPath = {for (final n in baseNodes) n.path: n};
    final currentNodes = _layout();
    final currentByPath = {for (final n in currentNodes) n.path: n};

    final base = baseByPath[nodePos.path];
    final current = currentByPath[nodePos.path];
    if (base == null || current == null) return;

    final clamped = _clampCenter(current.center + deltaScene);
    _manualNodeOffsets[nodePos.path] = clamped - base.center;

    _gentlyPushOverlappingNodes(nodePos.path, baseByPath, currentByPath);

    setState(() {});
  }

  void _gentlyPushOverlappingNodes(
    String draggingPath,
    Map<String, _NodePos> baseByPath,
    Map<String, _NodePos> currentByPath,
  ) {
    final dragged = currentByPath[draggingPath];
    if (dragged == null) return;

    const double minGapX = _nodeW * 0.8;
    const double minGapY = _nodeH * 0.8;

    for (final entry in currentByPath.entries) {
      if (entry.key == draggingPath) continue;

      final node = entry.value;
      final dx = node.center.dx - dragged.center.dx;
      final dy = node.center.dy - dragged.center.dy;

      if (dx.abs() > minGapX || dy.abs() > minGapY) continue;

      final base = baseByPath[entry.key];
      if (base == null) continue;

      final pushX = (minGapX - dx.abs()).clamp(0, minGapX) * 0.25;
      final pushY = (minGapY - dy.abs()).clamp(0, minGapY) * 0.25;
      if (pushX == 0 && pushY == 0) continue;

      final dirX = dx == 0 ? (math.Random().nextBool() ? 1.0 : -1.0) : dx.sign;
      final dirY = dy == 0 ? (math.Random().nextBool() ? 1.0 : -1.0) : dy.sign;

      final desiredCenter = _clampCenter(
        node.center + Offset(dirX * pushX, dirY * pushY),
      );
      _manualNodeOffsets[entry.key] = desiredCenter - base.center;
    }
  }

  _MiniMapTransform _miniMapTransform() {
    const double padding = 10;
    final usableW = _miniMapSize.width - (padding * 2);
    final usableH = _miniMapSize.height - (padding * 2);
    final scale = math.min(usableW / _canvasSize, usableH / _canvasSize);
    final dx = (_miniMapSize.width - (_canvasSize * scale)) / 2;
    final dy = (_miniMapSize.height - (_canvasSize * scale)) / 2;
    return _MiniMapTransform(scale: scale, origin: Offset(dx, dy));
  }

  Offset _sceneToMini(Offset scenePoint, _MiniMapTransform tx) {
    return Offset(
      tx.origin.dx + (scenePoint.dx * tx.scale),
      tx.origin.dy + (scenePoint.dy * tx.scale),
    );
  }

  Offset _miniToScene(Offset miniPoint, _MiniMapTransform tx) {
    return Offset(
      (miniPoint.dx - tx.origin.dx) / tx.scale,
      (miniPoint.dy - tx.origin.dy) / tx.scale,
    );
  }

  Rect _miniViewportRect(_MiniMapTransform tx) {
    final sceneRect = _viewportInScene();
    final topLeft = _sceneToMini(sceneRect.topLeft, tx);
    final bottomRight = _sceneToMini(sceneRect.bottomRight, tx);
    return Rect.fromPoints(topLeft, bottomRight);
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
    final viewport = _viewportInScene().inflate(300);
    print('🖼️ [Build] Viewport: $viewport');
    final visibleNodes = nodes.where((node) {
      final rect = Rect.fromCenter(
        center: node.center,
        width: _nodeW,
        height: _nodeH,
      );
      return rect.overlaps(viewport);
    }).toList();
    print(
      '👁️ [Build] Visible nodes: ${visibleNodes.length} / ${nodes.length}',
    );
    if (visibleNodes.isEmpty && nodes.isNotEmpty) {
      print(
        '⚠️ [Build] WARNING: No visible nodes! First node center: ${nodes.first.center}',
      );
    }

    final byPath = {for (final n in nodes) n.path: n};
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text((_structure['title'] ?? widget.topic).toString()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [],
      ),
      body: Column(
        children: [
          Expanded(
            child: SizedBox.expand(
              key: _viewerKey,
              child: Stack(
                children: [
                  Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        final zoomFactor = event.scrollDelta.dy > 0
                            ? 0.92
                            : 1.08;
                        _zoomAt(event.localPosition, zoomFactor);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      constrained: false,
                      panEnabled: _draggingPath == null,
                      scaleEnabled: _draggingPath == null,
                      child: RepaintBoundary(
                        child: Container(
                          width: _canvasSize,
                          height: _canvasSize,
                          color: const Color(0xFF0D0D12),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _ConnPainter(
                                      nodes: visibleNodes,
                                      byPath: byPath,
                                    ),
                                  ),
                                ),
                              ),
                              ...visibleNodes.map((n) {
                                final hasChildren =
                                    ((n.node['children'] as List?) ?? [])
                                        .isNotEmpty;
                                final isExpanded = _expanded.contains(n.path);
                                final nodeTitle = (n.node['title'] ?? 'Node')
                                    .toString();
                                final isDragging = _draggingPath == n.path;

                                final color = n.level == 0
                                    ? const Color(0xFF4775FF)
                                    : n.level == 1
                                    ? const Color(0xFF2DBF73)
                                    : const Color(0xFF8E5BFF);

                                return AnimatedPositioned(
                                  duration: isDragging
                                      ? Duration.zero
                                      : const Duration(milliseconds: 90),
                                  curve: Curves.easeOut,
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
                                    onDoubleTap: () => _editNode(n),
                                    onPanStart: (_) {
                                      setState(() => _draggingPath = n.path);
                                    },
                                    onPanUpdate: (details) =>
                                        _dragNode(n, details),
                                    onPanEnd: (_) {
                                      setState(() => _draggingPath = null);
                                    },
                                    onPanCancel: () {
                                      setState(() => _draggingPath = null);
                                    },
                                    child: AnimatedScale(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      scale: isDragging ? 1.05 : 1,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        width: _nodeW,
                                        height: _nodeH,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: isDragging
                                              ? Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.8),
                                                  width: 1.2,
                                                )
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: isDragging ? 0.45 : 0.2,
                                              ),
                                              blurRadius: isDragging ? 16 : 8,
                                              offset: Offset(
                                                0,
                                                isDragging ? 9 : 4,
                                              ),
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
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 16,
                    child: _FloatingControls(
                      onZoomIn: () => _zoomBy(0.12),
                      onZoomOut: () => _zoomBy(-0.12),
                      onReset: _center,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: AnimatedBuilder(
                      animation: _transformController,
                      builder: (_, __) {
                        final miniTx = _miniMapTransform();
                        return _MiniMapPanel(
                          size: _miniMapSize,
                          nodes: nodes,
                          viewportRect: _miniViewportRect(miniTx),
                          mapTransform: miniTx,
                          onNavigate: (miniPoint) {
                            final scene = _miniToScene(miniPoint, miniTx);
                            _moveViewportCenterToScene(_clampCenter(scene));
                          },
                        );
                      },
                    ),
                  ),
                ],
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
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    for (final node in nodes) {
      if (node.parentPath == null) continue;
      final parent = byPath[node.parentPath!];
      if (parent == null) continue;

      const halfNodeWidth = 83.0;
      final start = Offset(
        parent.center.dx + halfNodeWidth - 4,
        parent.center.dy,
      );
      final end = Offset(node.center.dx - halfNodeWidth + 4, node.center.dy);
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
    return oldDelegate.nodes != nodes || oldDelegate.byPath != byPath;
  }
}

class _MiniMapTransform {
  final double scale;
  final Offset origin;

  const _MiniMapTransform({required this.scale, required this.origin});
}

class _MiniMapPanel extends StatelessWidget {
  final Size size;
  final List<_NodePos> nodes;
  final Rect viewportRect;
  final _MiniMapTransform mapTransform;
  final ValueChanged<Offset> onNavigate;

  const _MiniMapPanel({
    required this.size,
    required this.nodes,
    required this.viewportRect,
    required this.mapTransform,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => onNavigate(details.localPosition),
      onPanUpdate: (details) {
        final nextCenter = viewportRect.center + details.delta;
        onNavigate(nextCenter);
      },
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: const Color(0xBB0E0F16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: CustomPaint(
          painter: _MiniMapPainter(
            nodes: nodes,
            viewportRect: viewportRect,
            mapTransform: mapTransform,
          ),
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  final List<_NodePos> nodes;
  final Rect viewportRect;
  final _MiniMapTransform mapTransform;

  const _MiniMapPainter({
    required this.nodes,
    required this.viewportRect,
    required this.mapTransform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()
      ..color = const Color(0xAA7B8FFF)
      ..style = PaintingStyle.fill;
    final rootPaint = Paint()
      ..color = const Color(0xFF6FA0FF)
      ..style = PaintingStyle.fill;
    final viewportPaint = Paint()
      ..color = Colors.transparent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final viewportFill = Paint()
      ..color = const Color(0x448AA5FF)
      ..style = PaintingStyle.fill;

    for (final node in nodes) {
      final p = Offset(
        mapTransform.origin.dx + (node.center.dx * mapTransform.scale),
        mapTransform.origin.dy + (node.center.dy * mapTransform.scale),
      );
      final paint = node.level == 0 ? rootPaint : nodePaint;
      final r = node.level == 0 ? 2.4 : 1.7;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: p, width: r * 2.4, height: r * 1.9),
          const Radius.circular(2),
        ),
        paint,
      );
    }

    final clampedViewport = Rect.fromLTWH(
      viewportRect.left.clamp(0, size.width),
      viewportRect.top.clamp(0, size.height),
      viewportRect.width.clamp(8, size.width),
      viewportRect.height.clamp(8, size.height),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(clampedViewport, const Radius.circular(4)),
      viewportFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(clampedViewport, const Radius.circular(4)),
      viewportPaint..color = const Color(0xFFE1E9FF),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.mapTransform != mapTransform;
  }
}

class _FloatingControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _FloatingControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xCC1A1B25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
            color: Colors.white,
          ),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
            color: Colors.white,
          ),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.center_focus_strong),
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}
