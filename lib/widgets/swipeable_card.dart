import 'package:flutter/material.dart';
import 'dart:math' as math;

class SwipeableCard extends StatefulWidget {
  final String category;
  final String text;
  final String author;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final bool isTopCard;

  const SwipeableCard({
    super.key,
    required this.category,
    required this.text,
    required this.author,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.isTopCard = false,
  });

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard>
    with SingleTickerProviderStateMixin {
  Offset _dragPosition = Offset.zero;
  bool _isDragging = false;
  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entranceAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    if (widget.isTopCard) {
      _entranceController.forward();
    }
  }

  @override
  void didUpdateWidget(SwipeableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isTopCard && widget.isTopCard) {
      _entranceController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.category.toLowerCase()) {
      case 'motivation':
        return const Color(0xFFFFB26B);
      case 'fact':
      case 'facts':
        return const Color(0xFF69D1C5);
      case 'history':
        return const Color(0xFFB59FFF);
      default:
        return const Color(0xFFFFB26B);
    }
  }

  void _onPanStart(DragStartDetails details) {
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragPosition += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth * 0.3;

    if (_dragPosition.dx.abs() > threshold) {
      // Trigger swipe action
      if (_dragPosition.dx > 0) {
        widget.onSwipeRight?.call();
      } else {
        widget.onSwipeLeft?.call();
      }
    } else {
      // Reset position
      setState(() {
        _dragPosition = Offset.zero;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final rotationAngle = (_dragPosition.dx / screenWidth) * 0.15;
    final opacity = (1.0 - (_dragPosition.dx.abs() / screenWidth * 0.6)).clamp(
      0.0,
      1.0,
    );
    final scale = _isDragging ? 1.02 : 1.0;

    // Swipe indicator
    Widget? swipeIndicator;
    if (_isDragging && _dragPosition.dx.abs() > 30) {
      if (_dragPosition.dx > 0) {
        swipeIndicator = Positioned(
          top: 60,
          right: 40,
          child: Opacity(
            opacity: math.min(0.22, _dragPosition.dx / screenWidth * 0.5),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Icon(Icons.favorite, color: Colors.green, size: 32),
            ),
          ),
        );
      } else {
        swipeIndicator = Positioned(
          top: 60,
          left: 40,
          child: Opacity(
            opacity: math.min(0.22, _dragPosition.dx.abs() / screenWidth * 0.5),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 32),
            ),
          ),
        );
      }
    }

    return AnimatedBuilder(
      animation: _entranceAnimation,
      builder: (context, child) {
        final entranceOffset = (1 - _entranceAnimation.value) * 20;
        final entranceOpacity = _entranceAnimation.value;

        return Transform.translate(
          offset: Offset(_dragPosition.dx, _dragPosition.dy + entranceOffset),
          child: Transform.rotate(
            angle: rotationAngle,
            child: Transform.scale(
              scale: scale,
              child: Opacity(opacity: opacity * entranceOpacity, child: child),
            ),
          ),
        );
      },
      child: GestureDetector(
        onPanStart: widget.isTopCard ? _onPanStart : null,
        onPanUpdate: widget.isTopCard ? _onPanUpdate : null,
        onPanEnd: widget.isTopCard ? _onPanEnd : null,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withOpacity(0.07),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 16,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                  children: [
                    // Base background
                    Container(color: const Color(0xFF1C1C1E).withOpacity(0.92)),
                    // Gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _accentColor.withOpacity(0.14),
                            Colors.transparent,
                            _accentColor.withOpacity(0.08),
                          ],
                        ),
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _accentColor.withOpacity(0.23),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _accentColor.withOpacity(0.35),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              widget.category.toUpperCase(),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          // Main text
                          Expanded(
                            child: Center(
                              child: Text(
                                widget.text,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontSize: 19,
                                  height: 1.4,
                                  fontStyle:
                                      widget.category.toLowerCase() ==
                                          'motivation'
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  fontWeight: FontWeight.w400,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Author/source
                          Center(
                            child: Text(
                              widget.author,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.60),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (swipeIndicator != null) swipeIndicator,
          ],
        ),
      ),
    );
  }
}
