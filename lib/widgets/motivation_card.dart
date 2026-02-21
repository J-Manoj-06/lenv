import 'package:flutter/material.dart';
import 'dart:math' as math;

typedef CardResetCallback = void Function();

class MotivationCard extends StatefulWidget {
  final String text;
  final String author;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final bool isTopCard;
  final CardResetCallback? onReset;

  const MotivationCard({
    super.key,
    required this.text,
    required this.author,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.isTopCard = false,
    this.onReset,
  });

  @override
  State<MotivationCard> createState() => _MotivationCardState();
}

class _MotivationCardState extends State<MotivationCard>
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
      duration: const Duration(milliseconds: 250),
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
  void didUpdateWidget(MotivationCard oldWidget) {
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
    final threshold = screenWidth * 0.25;

    if (_dragPosition.dx.abs() > threshold) {
      if (_dragPosition.dx > 0) {
        widget.onSwipeRight?.call();
      } else {
        widget.onSwipeLeft?.call();
      }
    } else {
      setState(() {
        _dragPosition = Offset.zero;
        _isDragging = false;
      });
    }
  }

  void resetDrag() {
    if (_dragPosition != Offset.zero || _isDragging) {
      setState(() {
        _dragPosition = Offset.zero;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final rotationAngle = (_dragPosition.dx / screenWidth) * 0.20;
    final opacity = (1.0 - (_dragPosition.dx.abs() / screenWidth * 0.6)).clamp(
      0.0,
      1.0,
    );
    final scale = _isDragging ? 1.03 : 1.0;

    Widget? swipeOverlay;
    if (_isDragging && _dragPosition.dx.abs() > 50) {
      if (_dragPosition.dx > 0) {
        swipeOverlay = Positioned(
          top: 80,
          right: 40,
          child: Opacity(
            opacity: math.min(0.25, _dragPosition.dx / screenWidth * 0.6),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.favorite, color: Colors.green, size: 40),
            ),
          ),
        );
      } else {
        swipeOverlay = Positioned(
          top: 80,
          left: 40,
          child: Opacity(
            opacity: math.min(0.25, _dragPosition.dx.abs() / screenWidth * 0.6),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 40),
            ),
          ),
        );
      }
    }

    return AnimatedBuilder(
      animation: _entranceAnimation,
      builder: (context, child) {
        final entranceScale = 0.92 + (_entranceAnimation.value * 0.08);
        final entranceOpacity = _entranceAnimation.value;

        return Transform.translate(
          offset: _dragPosition,
          child: Transform.rotate(
            angle: rotationAngle,
            child: Transform.scale(
              scale: scale * entranceScale,
              child: Opacity(opacity: opacity * entranceOpacity, child: child),
            ),
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: widget.isTopCard ? _onPanStart : null,
        onPanUpdate: widget.isTopCard ? _onPanUpdate : null,
        onPanEnd: widget.isTopCard ? _onPanEnd : null,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(width: 2, color: Colors.transparent),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFFFF9E6),
                        const Color(0xFFFFECC0),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Motivation badge
                      Positioned(
                        top: 24,
                        left: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB26B).withOpacity(0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFF9500).withOpacity(0.7),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFF9500,
                                ).withOpacity(0.25),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Text(
                            'MOTIVATION',
                            style: TextStyle(
                              color: Color(0xFF8B4513),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                      // Quote text
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 60,
                          ),
                          child: Text(
                            widget.text,
                            style: const TextStyle(
                              color: Color(0xFF2C1810),
                              fontSize: 20,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w400,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      // Author
                      Positioned(
                        bottom: 32,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Text(
                            widget.author,
                            style: const TextStyle(
                              color: Color(0xFF5D3A1A),
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (swipeOverlay != null) swipeOverlay,
          ],
        ),
      ),
    );
  }
}
