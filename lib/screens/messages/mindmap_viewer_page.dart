import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/mindmap_model.dart';
import '../../services/mindmap_service.dart';

class MindmapViewerPage extends StatefulWidget {
  final String mindmapId;
  final String fallbackTopic;

  const MindmapViewerPage({
    super.key,
    required this.mindmapId,
    required this.fallbackTopic,
  });

  @override
  State<MindmapViewerPage> createState() => _MindmapViewerPageState();
}

class _MindmapViewerPageState extends State<MindmapViewerPage> {
  final MindmapService _mindmapService = MindmapService();
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  MindmapModel? _mindmap;
  bool _loading = true;

  final Set<String> _expanded = <String>{'root'};
  final Map<String, Offset> _manualNodeOffsets = <String, Offset>{};
  String? _draggingPath;

  static const double _canvasSize = 5000;
  static const double _nodeW = 176;
  static const double _nodeH = 64;
  static const double _minScale = 0.5;
  static const double _maxScale = 2.5;
  static const Size _miniMapSize = Size(140, 100);

  @override
  void initState() {
    super.initState();
    _loadMindmap();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadMindmap() async {
    print('📥 [ViewerPage] Loading mindmap ID: ${widget.mindmapId}');
    final model = await _mindmapService.getMindmapById(widget.mindmapId);
    print(
      '📥 [ViewerPage] Retrieved model: ${model != null ? "SUCCESS" : "NULL"}',
    );

    if (!mounted) {
      print('⚠️ [ViewerPage] Widget not mounted, aborting');
      return;
    }

    // Only expand root node initially - users can expand others by tapping
    if (model != null) {
      print('📥 [ViewerPage] Model topic: ${model.topic}');
      print('📥 [ViewerPage] Root node title: ${model.root.title}');
      // Only root is expanded by default (already in _expanded set)
      print('✅ [ViewerPage] Initial expanded: $_expanded');
    } else {
      print('❌ [ViewerPage] Model is null');
    }

    setState(() {
      _mindmap = model;
      _loading = false;
    });
    print(
      '📥 [ViewerPage] setState completed, _loading = $_loading, _mindmap = ${_mindmap != null}',
    );

    // Center the viewport after loading and layout
    if (model != null) {
      print('📥 [ViewerPage] Scheduling _centerMindmap in postFrameCallback');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print('🎯 [ViewerPage] PostFrameCallback executing _centerMindmap');
        _centerMindmap();
      });
    }
  }

  void _collapseNodeAndChildren(MindmapNode node, String path) {
    // Remove this node from expanded set
    _expanded.remove(path);

    // Recursively collapse all children
    for (int i = 0; i < node.children.length; i++) {
      final childPath = '$path/$i';
      _collapseNodeAndChildren(node.children[i], childPath);
    }
  }

  MindmapNode? _getNodeAtPath(MindmapNode root, String path) {
    if (path == 'root') return root;

    final parts = path.split('/').skip(1); // Skip 'root'
    MindmapNode current = root;

    for (final indexStr in parts) {
      final index = int.tryParse(indexStr);
      if (index == null || index >= current.children.length) return null;
      current = current.children[index];
    }

    return current;
  }

  void _centerMindmap() {
    print('🎯 [ViewerPage] _centerMindmap called');
    if (!mounted) return;

    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box?.hasSize != true) {
      print('⚠️ [ViewerPage] Box not ready, skipping center');
      return;
    }

    final size = box!.size;
    print('🎯 [ViewerPage] Screen size: $size');

    // Root node is at canvas center
    final rootX = _canvasSize / 2;
    final rootY = _canvasSize / 2;

    // Calculate where we want the root to appear on screen (20% from left, 50% from top)
    final targetScreenX = size.width * 0.20;
    final targetScreenY = size.height * 0.5;

    print('🎯 [ViewerPage] Root at: ($rootX, $rootY)');
    print(
      '🎯 [ViewerPage] Target screen pos: ($targetScreenX, $targetScreenY)',
    );

    // Create transformation that moves root to target position
    final matrix = Matrix4.identity()
      ..translate(targetScreenX - rootX, targetScreenY - rootY);

    _transformController.value = matrix;
    print('✅ [ViewerPage] Viewport centered');

    // Force a rebuild to show the centered view
    if (mounted) {
      setState(() {});
    }
  }

  double _currentScale() => _transformController.value.getMaxScaleOnAxis();

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
    const pad = 20.0;
    return Offset(
      center.dx.clamp(_nodeW / 2 + pad, _canvasSize - (_nodeW / 2 + pad)),
      center.dy.clamp(_nodeH / 2 + pad, _canvasSize - (_nodeH / 2 + pad)),
    );
  }

  List<_NodePosition> _computeLayout(
    MindmapNode root, {
    bool applyManualOffsets = true,
  }) {
    final nodes = <_NodePosition>[];
    final rootCenter = Offset(_canvasSize / 2, _canvasSize / 2);

    void walk(
      MindmapNode node,
      String path,
      int level,
      Offset center,
      String? parentPath,
      double spread,
    ) {
      nodes.add(
        _NodePosition(
          node: node,
          path: path,
          parentPath: parentPath,
          level: level,
          center: applyManualOffsets
              ? center + (_manualNodeOffsets[path] ?? Offset.zero)
              : center,
        ),
      );

      if (!_expanded.contains(path) || node.children.isEmpty) return;

      final count = node.children.length;
      // Horizontal layout: children stack vertically to the right
      final x = center.dx + 320; // Fixed horizontal distance to the right
      final totalHeight = (count - 1) * spread;
      final startY = center.dy - (totalHeight / 2);
      final nextSpread = math.max(170, spread * 0.8).toDouble();

      for (int i = 0; i < count; i++) {
        final child = node.children[i];
        final childPath = '$path/$i';
        walk(
          child,
          childPath,
          level + 1,
          Offset(x, startY + i * spread),
          path,
          nextSpread,
        );
      }
    }

    walk(root, 'root', 0, rootCenter, null, 320);
    return nodes;
  }

  void _dragNode(_NodePosition nodePos, DragUpdateDetails details) {
    final model = _mindmap;
    if (model == null) return;

    final scale = _currentScale();
    if (scale <= 0) return;

    final sceneDelta = details.delta / scale;
    if (sceneDelta == Offset.zero) return;

    final baseNodes = _computeLayout(model.root, applyManualOffsets: false);
    final baseByPath = {for (final n in baseNodes) n.path: n};

    final currentNodes = _computeLayout(model.root);
    final currentByPath = {for (final n in currentNodes) n.path: n};

    final base = baseByPath[nodePos.path];
    final current = currentByPath[nodePos.path];
    if (base == null || current == null) return;

    final clamped = _clampCenter(current.center + sceneDelta);
    _manualNodeOffsets[nodePos.path] = clamped - base.center;
    setState(() {});
  }

  _MiniMapTransform _miniMapTransform() {
    const padding = 10.0;
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
    return Rect.fromPoints(
      _sceneToMini(sceneRect.topLeft, tx),
      _sceneToMini(sceneRect.bottomRight, tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    print(
      '🎨 [ViewerPage Build] _loading=$_loading, _mindmap=${_mindmap != null}',
    );
    final topic = _mindmap?.topic ?? widget.fallbackTopic;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 1,
        title: Text(topic, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mindmap == null
          ? const Center(child: Text('Mindmap not found'))
          : _buildCanvas(_mindmap!.root),
    );
  }

  Widget _buildCanvas(MindmapNode root) {
    print('🎨 [ViewerPage Canvas] Building canvas for root: ${root.title}');
    print('🎨 [ViewerPage Canvas] Expanded nodes count: ${_expanded.length}');

    final nodes = _computeLayout(root);
    print('🎨 [ViewerPage Canvas] Total nodes after layout: ${nodes.length}');

    final byPath = {for (final n in nodes) n.path: n};
    final viewport = _viewportInScene().inflate(260);
    print('🎨 [ViewerPage Canvas] Viewport: $viewport');

    final visibleNodes = nodes.where((node) {
      final rect = Rect.fromCenter(
        center: node.center,
        width: _nodeW,
        height: _nodeH,
      );
      return rect.overlaps(viewport);
    }).toList();

    print(
      '🎨 [ViewerPage Canvas] Visible nodes: ${visibleNodes.length} / ${nodes.length}',
    );
    if (visibleNodes.isEmpty && nodes.isNotEmpty) {
      print(
        '⚠️ [ViewerPage Canvas] NO VISIBLE NODES! First node center: ${nodes.first.center}',
      );
    }
    return SizedBox.expand(
      key: _viewerKey,
      child: Stack(
        children: [
          Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final factor = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
                _zoomAt(event.localPosition, factor);
              }
            },
            child: InteractiveViewer(
              transformationController: _transformController,
              constrained: false,
              minScale: _minScale,
              maxScale: _maxScale,
              panEnabled: _draggingPath == null,
              scaleEnabled: _draggingPath == null,
              child: Container(
                width: _canvasSize,
                height: _canvasSize,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [Color(0xFF252525), Color(0xFF1A1A1A)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _MindmapConnectionPainter(
                            visibleNodes: visibleNodes,
                            byPath: byPath,
                          ),
                        ),
                      ),
                    ),
                    ...visibleNodes.map(_buildNode),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: _Toolbar(
              onZoomIn: () => _zoomBy(0.12),
              onZoomOut: () => _zoomBy(-0.12),
              onReset: _centerMindmap,
              onCenter: _centerMindmap,
            ),
          ),
          Positioned(
            right: 16,
            bottom: 20,
            child: AnimatedBuilder(
              animation: _transformController,
              builder: (_, __) {
                final tx = _miniMapTransform();
                return _MiniMapPanel(
                  size: _miniMapSize,
                  nodes: nodes,
                  viewportRect: _miniViewportRect(tx),
                  mapTransform: tx,
                  onNavigate: (miniPoint) {
                    final scene = _miniToScene(miniPoint, tx);
                    _moveViewportCenterToScene(_clampCenter(scene));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNode(_NodePosition node) {
    final hasChildren = node.node.children.isNotEmpty;
    final isExpanded = _expanded.contains(node.path);
    final isDragging = _draggingPath == node.path;

    final color = node.level == 0
        ? const Color(0xFF2E6BFF)
        : node.level == 1
        ? const Color(0xFF2DBF73)
        : const Color(0xFF8F5FE8);

    return Positioned(
      left: node.center.dx - (_nodeW / 2),
      top: node.center.dy - (_nodeH / 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: hasChildren
              ? () {
                  setState(() {
                    if (isExpanded) {
                      // Collapse this node and all its children
                      final nodeData = _getNodeAtPath(
                        _mindmap!.root,
                        node.path,
                      );
                      if (nodeData != null) {
                        _collapseNodeAndChildren(nodeData, node.path);
                      }
                    } else {
                      // Expand only this node
                      _expanded.add(node.path);
                    }
                  });
                }
              : null,
          onPanStart: (_) => setState(() => _draggingPath = node.path),
          onPanUpdate: (details) => _dragNode(node, details),
          onPanEnd: (_) => setState(() => _draggingPath = null),
          onPanCancel: () => setState(() => _draggingPath = null),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: isDragging ? 1.05 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _nodeW,
              height: _nodeH,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                border: isDragging
                    ? Border.all(color: Colors.white, width: 1.2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDragging ? 0.35 : 0.2,
                    ),
                    blurRadius: isDragging ? 16 : 10,
                    offset: Offset(0, isDragging ? 9 : 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      node.node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (hasChildren)
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 220),
                      turns: isExpanded ? 0.25 : 0,
                      child: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodePosition {
  final MindmapNode node;
  final String path;
  final String? parentPath;
  final int level;
  final Offset center;

  const _NodePosition({
    required this.node,
    required this.path,
    required this.parentPath,
    required this.level,
    required this.center,
  });
}

class _MindmapConnectionPainter extends CustomPainter {
  final List<_NodePosition> visibleNodes;
  final Map<String, _NodePosition> byPath;

  const _MindmapConnectionPainter({
    required this.visibleNodes,
    required this.byPath,
  });

  static const double _halfW = 88;
  static const double _halfH = 32;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xAA6B8CFF)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    for (final node in visibleNodes) {
      if (node.parentPath == null) continue;
      final parent = byPath[node.parentPath!];
      if (parent == null) continue;

      final start = _edgePoint(parent.center, node.center, _halfW, _halfH);
      final end = _edgePoint(node.center, parent.center, _halfW, _halfH);

      final cp1 = Offset(start.dx + ((end.dx - start.dx) * 0.25), start.dy);
      final cp2 = Offset(end.dx - ((end.dx - start.dx) * 0.25), end.dy);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

      canvas.drawPath(path, paint);
    }
  }

  Offset _edgePoint(Offset from, Offset to, double halfW, double halfH) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    if (dx == 0 && dy == 0) return from;

    final tx = dx.abs() / halfW;
    final ty = dy.abs() / halfH;
    if (tx > ty) {
      return Offset(from.dx + halfW * dx.sign, from.dy + (dy / tx));
    }
    return Offset(from.dx + (dx / ty), from.dy + halfH * dy.sign);
  }

  @override
  bool shouldRepaint(covariant _MindmapConnectionPainter oldDelegate) {
    return oldDelegate.visibleNodes != visibleNodes ||
        oldDelegate.byPath != byPath;
  }
}

class _MiniMapTransform {
  final double scale;
  final Offset origin;

  const _MiniMapTransform({required this.scale, required this.origin});
}

class _MiniMapPanel extends StatelessWidget {
  final Size size;
  final List<_NodePosition> nodes;
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
      onPanUpdate: (details) => onNavigate(viewportRect.center + details.delta),
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
  final List<_NodePosition> nodes;
  final Rect viewportRect;
  final _MiniMapTransform mapTransform;

  const _MiniMapPainter({
    required this.nodes,
    required this.viewportRect,
    required this.mapTransform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()..color = const Color(0xAA8B95FF);
    final rootPaint = Paint()..color = const Color(0xFF6EA4FF);
    final vpFill = Paint()..color = const Color(0x448DA3FF);
    final vpStroke = Paint()
      ..color = const Color(0xFFE7EDFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (final node in nodes) {
      final p = Offset(
        mapTransform.origin.dx + (node.center.dx * mapTransform.scale),
        mapTransform.origin.dy + (node.center.dy * mapTransform.scale),
      );
      canvas.drawCircle(
        p,
        node.level == 0 ? 2.4 : 1.6,
        node.level == 0 ? rootPaint : nodePaint,
      );
    }

    final rect = Rect.fromLTWH(
      viewportRect.left.clamp(0, size.width),
      viewportRect.top.clamp(0, size.height),
      viewportRect.width.clamp(8, size.width),
      viewportRect.height.clamp(8, size.height),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      vpFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      vpStroke,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.mapTransform != mapTransform;
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onCenter;

  const _Toolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF404040), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onZoomIn,
            icon: const Icon(Icons.add, color: Colors.white),
          ),
          IconButton(
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove, color: Colors.white),
          ),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            onPressed: onCenter,
            icon: const Icon(Icons.center_focus_strong, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/*

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/mindmap_model.dart';
import '../../services/mindmap_service.dart';

class MindmapViewerPage extends StatefulWidget {
  final String mindmapId;
  final String fallbackTopic;

  const MindmapViewerPage({
    super.key,
    required this.mindmapId,
    required this.fallbackTopic,
  });

  @override
  State<MindmapViewerPage> createState() => _MindmapViewerPageState();
}

class _MindmapViewerPageState extends State<MindmapViewerPage> {
  final MindmapService _mindmapService = MindmapService();
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  MindmapModel? _mindmap;
  bool _loading = true;
  final Set<String> _expanded = <String>{'root'};
  final Map<String, Offset> _manualNodeOffsets = <String, Offset>{};
  String? _draggingPath;

  static const double _canvasSize = 5000;
  static const double _nodeW = 176;
  static const double _nodeH = 64;
  static const double _minScale = 0.5;
  static const double _maxScale = 2.5;
  static const Size _miniMapSize = Size(200, 140);

  @override
  void initState() {
    super.initState();
    _loadMindmap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMindmap();
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadMindmap() async {
    final model = await _mindmapService.getMindmapById(widget.mindmapId);
    if (!mounted) return;
    setState(() {
      _mindmap = model;
      _loading = false;
    });
  }

  void _centerMindmap() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.of(context).size;
    final dx = (size.width / 2) - (_canvasSize / 2);
    final dy = (size.height / 2) - (_canvasSize / 2);
    _transformController.value = Matrix4.identity()..translate(dx, dy);
  }

  double _currentScale() => _transformController.value.getMaxScaleOnAxis();

  Rect _viewportInScene() {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.of(context).size;
    final topLeft = _transformController.toScene(Offset.zero);
    final bottomRight = _transformController.toScene(
      Offset(size.width, size.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _zoomBy(double delta) {
    final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.of(context).size;
    _zoomAt(Offset(size.width / 2, size.height / 2), 1 + delta);
  }

  void _zoomAt(Offset viewportFocal, double factor) {
    final oldScale = _currentScale();
    final nextScale = (oldScale * factor).clamp(_minScale, _maxScale);
    if ((nextScale - oldScale).abs() < 0.0001) return;

    final scene = _transformController.toScene(viewportFocal);
    final next = Matrix4.identity()
      ..translate(viewportFocal.dx, viewportFocal.dy)
      ..scale(nextScale)
      ..translate(-scene.dx, -scene.dy);
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

  List<_NodePosition> _computeLayout(MindmapNode root, {bool applyManualOffsets = true}) {
    final nodes = <_NodePosition>[];
    final rootCenter = Offset(_canvasSize / 2, _canvasSize / 2);

    void walk(
      MindmapNode node,
      String path,
      int level,
      Offset center,
      String? parentPath,
      double spread,
    ) {
      nodes.add(
        _NodePosition(
          node: node,
          path: path,
          parentPath: parentPath,
          level: level,
          center: applyManualOffsets
              ? center + (_manualNodeOffsets[path] ?? Offset.zero)
              : center,
        ),
      );

      if (!_expanded.contains(path) || node.children.isEmpty) return;

      final count = node.children.length;
      // Horizontal layout: children stack vertically to the right
      final x = center.dx + 320; // Fixed horizontal distance to the right
      final totalHeight = (count - 1) * spread;
      final startY = center.dy - (totalHeight / 2);
      final nextSpread = math.max(170, spread * 0.8).toDouble();

      for (int i = 0; i < count; i++) {
        final child = node.children[i];
        final childPath = '$path/$i';
        walk(
          child,
          childPath,
          level + 1,
          Offset(x, startY + i * spread),
          path,
          nextSpread,
        );
      }
    }

    walk(root, 'root', 0, rootCenter, null, 320);
    return nodes;
  }

  void _dragNode(_NodePosition nodePos, DragUpdateDetails details) {
    final scale = _currentScale();
    if (scale <= 0) return;

    final sceneDelta = details.delta / scale;
    if (sceneDelta == Offset.zero) return;

    final base = _computeLayout(_mindmap!.root, applyManualOffsets: false);
    final baseByPath = {for (final n in base) n.path: n};
    final current = _computeLayout(_mindmap!.root);
    final currentByPath = {for (final n in current) n.path: n};

    final baseNode = baseByPath[nodePos.path];
    final currentNode = currentByPath[nodePos.path];
    if (baseNode == null || currentNode == null) return;

    final nextCenter = _clampCenter(currentNode.center + sceneDelta);
    _manualNodeOffsets[nodePos.path] = nextCenter - baseNode.center;
    setState(() {});
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
    return Rect.fromPoints(
      _sceneToMini(sceneRect.topLeft, tx),
      _sceneToMini(sceneRect.bottomRight, tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topic = _mindmap?.topic ?? widget.fallbackTopic;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FC),
      appBar: AppBar(
        title: Text(topic),
        actions: [
          IconButton(
            tooltip: 'Center Mindmap',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: _centerMindmap,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mindmap == null
          ? const Center(child: Text('Mindmap not found'))
          : _buildCanvas(_mindmap!.root),
    );
  }

  Widget _buildCanvas(MindmapNode root) {
    final nodes = _computeLayout(root);
    final byPath = {for (final n in nodes) n.path: n};
    final viewport = _viewportInScene().inflate(260);

    final visibleNodes = nodes.where((node) {
      final rect = Rect.fromCenter(
        center: node.center,
        width: _nodeW,
            SizedBox.expand(
              key: _viewerKey,
              child: Stack(
                children: [
                  Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        final factor = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
                        _zoomAt(event.localPosition, factor);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      constrained: false,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      panEnabled: _draggingPath == null,
                      scaleEnabled: _draggingPath == null,
                      child: Container(
                        width: _canvasSize,
                        height: _canvasSize,
                        decoration: const BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 1.2,
                            colors: [Color(0xFFF8FBFF), Color(0xFFEAF2FF)],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _MindmapConnectionPainter(
                                  visibleNodes: visibleNodes,
                                  byPath: byPath,
                                ),
                              ),
                            ),
                            ...visibleNodes.map((n) => _buildNode(n)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 16,
                    child: _Toolbar(
                      onZoomIn: () => _zoomBy(0.12),
                      onZoomOut: () => _zoomBy(-0.12),
                      onReset: _centerMindmap,
                      onCenter: _centerMindmap,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 20,
                    child: AnimatedBuilder(
                      animation: _transformController,
                      builder: (_, __) {
                        final tx = _miniMapTransform();
                        return _MiniMapPanel(
                          size: _miniMapSize,
                          nodes: nodes,
                          viewportRect: _miniViewportRect(tx),
                          mapTransform: tx,
                          onNavigate: (miniPoint) {
                            final scene = _miniToScene(miniPoint, tx);
                            _moveViewportCenterToScene(_clampCenter(scene));
                          },
                        );
                      },
                    ),
                  ),
                      visibleNodes: visibleNodes,
                      byPath: byPath,
                    ),
            onZoomOut: () => _zoomBy(-0.2),
            onReset: () {
              _transformController.value = Matrix4.identity();
            },
            onCenter: _centerMindmap,
          ),
        ),
      ],
    );
  }

  Widget _buildNode(_NodePosition node) {
    final hasChildren = node.node.children.isNotEmpty;
    final isExpanded = _expanded.contains(node.path);

    Color color;
    if (node.level == 0) {
      color = const Color(0xFF2E6BFF);
    } else if (node.level == 1) {
      color = const Color(0xFF2DBF73);
    } else {
      color = const Color(0xFF8F5FE8);
    }

    return Positioned(
      left: node.center.dx - (_nodeW / 2),
      top: node.center.dy - (_nodeH / 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onPanStart: (_) => setState(() => _draggingPath = node.path),
          onPanUpdate: (details) => _dragNode(node, details),
          onPanEnd: (_) => setState(() => _draggingPath = null),
          onPanCancel: () => setState(() => _draggingPath = null),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _draggingPath == node.path ? 1.05 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _nodeW,
              height: _nodeH,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                border: _draggingPath == node.path
                    ? Border.all(color: Colors.white, width: 1.2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _draggingPath == node.path ? 0.35 : 0.2,
                    ),
                    blurRadius: _draggingPath == node.path ? 18 : 10,
                    offset: Offset(0, _draggingPath == node.path ? 10 : 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      node.node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (hasChildren)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() {
                          if (isExpanded) {
                            _expanded.remove(node.path);
                          } else {
                            _expanded.add(node.path);
                          }
                        });
                      },
                      child: AnimatedRotation(
                        duration: const Duration(milliseconds: 220),
                        turns: isExpanded ? 0.25 : 0,
                        child: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodePosition {
  final MindmapNode node;
  final String path;
  final String? parentPath;
  final int level;
  final Offset center;

  const _NodePosition({
    required this.node,
    required this.path,
    required this.parentPath,
    required this.level,
    required this.center,
  });
}

class _MindmapConnectionPainter extends CustomPainter {
  final List<_NodePosition> visibleNodes;
  final Map<String, _NodePosition> byPath;

  const _MindmapConnectionPainter({
    required this.visibleNodes,
    required this.byPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x664A6AA6)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (final node in visibleNodes) {
      if (node.parentPath == null) continue;
      final parent = byPath[node.parentPath!];
      if (parent == null) continue;

      final start = _edgePoint(parent.center, node.center, _halfW, _halfH);
      final end = _edgePoint(node.center, parent.center, _halfW, _halfH);

      final cp1 = Offset(start.dx + ((end.dx - start.dx) * 0.25), start.dy);
      final cp2 = Offset(end.dx - ((end.dx - start.dx) * 0.25), end.dy);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindmapConnectionPainter oldDelegate) {
    return oldDelegate.visibleNodes != visibleNodes;
  }

  static const double _halfW = 88;
  static const double _halfH = 32;

  Offset _edgePoint(Offset from, Offset to, double halfW, double halfH) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    if (dx == 0 && dy == 0) return from;

    final absDx = dx.abs();
    final absDy = dy.abs();
    final tx = absDx / halfW;
    final ty = absDy / halfH;

    if (tx > ty) {
      return Offset(from.dx + halfW * dx.sign, from.dy + (dy / tx));
    }
    return Offset(from.dx + (dx / ty), from.dy + halfH * dy.sign);
  }
}

class _MiniMapTransform {
  final double scale;
  final Offset origin;

  const _MiniMapTransform({required this.scale, required this.origin});
}

class _MiniMapPanel extends StatelessWidget {
  final Size size;
  final List<_NodePosition> nodes;
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
      onPanUpdate: (details) => onNavigate(viewportRect.center + details.delta),
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
  final List<_NodePosition> nodes;
  final Rect viewportRect;
  final _MiniMapTransform mapTransform;

  const _MiniMapPainter({
    required this.nodes,
    required this.viewportRect,
    required this.mapTransform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()..color = const Color(0xAA8B95FF);
    final rootPaint = Paint()..color = const Color(0xFF6EA4FF);
    final vpFill = Paint()..color = const Color(0x448DA3FF);
    final vpStroke = Paint()
      ..color = const Color(0xFFE7EDFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (final node in nodes) {
      final p = Offset(
        mapTransform.origin.dx + (node.center.dx * mapTransform.scale),
        mapTransform.origin.dy + (node.center.dy * mapTransform.scale),
      );
      canvas.drawCircle(p, node.level == 0 ? 2.4 : 1.6, node.level == 0 ? rootPaint : nodePaint);
    }

    final rect = Rect.fromLTWH(
      viewportRect.left.clamp(0, size.width),
      viewportRect.top.clamp(0, size.height),
      viewportRect.width.clamp(8, size.width),
      viewportRect.height.clamp(8, size.height),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), vpFill);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), vpStroke);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.mapTransform != mapTransform;
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onCenter;

  const _Toolbar({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(onPressed: onZoomIn, icon: const Icon(Icons.add)),
          IconButton(onPressed: onZoomOut, icon: const Icon(Icons.remove)),
          IconButton(onPressed: onReset, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: onCenter,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
    );
  }
}
*/
