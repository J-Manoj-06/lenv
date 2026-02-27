import 'dart:math' as math;

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

  MindmapModel? _mindmap;
  bool _loading = true;
  final Set<String> _expanded = <String>{'root'};

  static const double _canvasSize = 5000;
  static const double _nodeW = 176;
  static const double _nodeH = 64;

  @override
  void initState() {
    super.initState();
    _loadMindmap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerMindmap();
    });
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
    final size = MediaQuery.of(context).size;
    final dx = (size.width / 2) - (_canvasSize / 2);
    final dy = (size.height / 2) - (_canvasSize / 2);
    _transformController.value = Matrix4.identity()..translate(dx, dy);
  }

  void _zoomBy(double delta) {
    final current = _transformController.value.clone();
    final currentScale = current.getMaxScaleOnAxis();
    final target = (currentScale + delta).clamp(0.5, 2.6);

    final size = MediaQuery.of(context).size;
    final sceneCenter = _transformController.toScene(
      Offset(size.width / 2, size.height / 2),
    );

    final next = Matrix4.identity()
      ..translate(size.width / 2, size.height / 2)
      ..scale(target)
      ..translate(-sceneCenter.dx, -sceneCenter.dy);

    _transformController.value = next;
  }

  List<_NodePosition> _computeLayout(MindmapNode root) {
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
          center: center,
        ),
      );

      if (!_expanded.contains(path) || node.children.isEmpty) return;

      final count = node.children.length;
      final startX = center.dx - ((count - 1) * spread / 2);
      final y = center.dy + 140;
      final nextSpread = math.max(170, spread * 0.72).toDouble();

      for (int i = 0; i < count; i++) {
        final child = node.children[i];
        final childPath = '$path/$i';
        walk(
          child,
          childPath,
          level + 1,
          Offset(startX + i * spread, y),
          path,
          nextSpread,
        );
      }
    }

    walk(root, 'root', 0, rootCenter, null, 320);
    return nodes;
  }

  Rect _viewportInScene() {
    final size = MediaQuery.of(context).size;
    final topLeft = _transformController.toScene(Offset.zero);
    final bottomRight = _transformController.toScene(
      Offset(size.width, size.height),
    );
    return Rect.fromPoints(topLeft, bottomRight).inflate(240);
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
    final viewport = _viewportInScene();

    final visibleNodes = nodes.where((node) {
      final rect = Rect.fromCenter(
        center: node.center,
        width: _nodeW,
        height: _nodeH,
      );
      return rect.overlaps(viewport);
    }).toList();

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _transformController,
          constrained: false,
          minScale: 0.5,
          maxScale: 2.6,
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
        Positioned(
          right: 16,
          bottom: 20,
          child: _Toolbar(
            onZoomIn: () => _zoomBy(0.2),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: _nodeW,
          height: _nodeH,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 4),
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

      final start = Offset(parent.center.dx, parent.center.dy + 32);
      final end = Offset(node.center.dx, node.center.dy - 32);

      final cp1 = Offset(start.dx, start.dy + 52);
      final cp2 = Offset(end.dx, end.dy - 52);

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
