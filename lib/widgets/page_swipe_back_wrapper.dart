import 'package:flutter/material.dart';

class PageSwipeBackWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const PageSwipeBackWrapper({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<PageSwipeBackWrapper> createState() => _PageSwipeBackWrapperState();
}

class _PageSwipeBackWrapperState extends State<PageSwipeBackWrapper>
    with SingleTickerProviderStateMixin {
  static const double _dismissVelocity = 300.0;
  static const double _dismissFraction = 0.28;

  late final AnimationController _controller;
  Animation<double>? _animation;
  double _dragOffsetX = 0.0;
  double? _startDragOffsetX;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final animation = _animation;
          if (animation != null) {
            setState(() => _dragOffsetX = animation.value);
          }
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double targetX, {VoidCallback? onComplete}) {
    final begin = _dragOffsetX;
    _animation = Tween<double>(
      begin: begin,
      end: targetX,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller
      ..stop()
      ..reset();
    _controller.forward().whenComplete(() {
      if (!mounted) return;
      onComplete?.call();
    });
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _isDragging = true;
    _startDragOffsetX = _dragOffsetX;
    _controller.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || !_isDragging) return;

    final start = _startDragOffsetX ?? 0.0;
    final nextOffset = (start + details.delta.dx).clamp(0.0, double.infinity);
    setState(() => _dragOffsetX = nextOffset);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.enabled || !_isDragging) return;
    _isDragging = false;

    final width = MediaQuery.of(context).size.width;
    final velocity = details.primaryVelocity ?? 0.0;
    final shouldDismiss =
        velocity > _dismissVelocity || _dragOffsetX > width * _dismissFraction;

    if (shouldDismiss) {
      _animateTo(
        width,
        onComplete: () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).maybePop();
          }
        },
      );
    } else {
      _animateTo(0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: Transform.translate(
        offset: Offset(_dragOffsetX, 0),
        child: widget.child,
      ),
    );
  }
}
