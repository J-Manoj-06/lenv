import 'package:flutter/material.dart';
import 'dart:math' as math;

typedef CardResetCallback = void Function();

class HistoryCard extends StatefulWidget {
  final String title;
  final String description;
  final String year;
  final String imageUrl;
  final String category;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final bool isTopCard;
  final CardResetCallback? onReset;

  const HistoryCard({
    super.key,
    required this.title,
    required this.description,
    required this.year,
    required this.imageUrl,
    required this.category,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.isTopCard = false,
    this.onReset,
  });

  @override
  State<HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<HistoryCard>
    with SingleTickerProviderStateMixin {
  Offset _dragPosition = Offset.zero;
  bool _isDragging = false;
  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;
  bool _imageLoaded = false;

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
  void didUpdateWidget(HistoryCard oldWidget) {
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

  LinearGradient get _categoryGradient {
    switch (widget.category.toLowerCase()) {
      case 'event':
      case 'events':
      case 'selected':
        return LinearGradient(
          colors: [
            const Color(0xFFFF9500).withOpacity(0.4),
            const Color(0xFFFFCC00).withOpacity(0.4),
          ],
        );
      case 'birth':
      case 'births':
        return LinearGradient(
          colors: [
            const Color(0xFF007AFF).withOpacity(0.4),
            const Color(0xFF5E5CE6).withOpacity(0.4),
          ],
        );
      case 'death':
      case 'deaths':
        return LinearGradient(
          colors: [
            const Color(0xFFFF3B30).withOpacity(0.4),
            const Color(0xFFFF2D55).withOpacity(0.4),
          ],
        );
      case 'holiday':
      case 'holidays':
        return LinearGradient(
          colors: [
            const Color(0xFF34C759).withOpacity(0.4),
            const Color(0xFF30D5C8).withOpacity(0.4),
          ],
        );
      default:
        return LinearGradient(
          colors: [
            const Color(0xFFFF9500).withOpacity(0.4),
            const Color(0xFFFFCC00).withOpacity(0.4),
          ],
        );
    }
  }

  Color get _categoryColor {
    switch (widget.category.toLowerCase()) {
      case 'event':
      case 'events':
      case 'selected':
        return const Color(0xFFFF9500);
      case 'birth':
      case 'births':
        return const Color(0xFF007AFF);
      case 'death':
      case 'deaths':
        return const Color(0xFFFF3B30);
      case 'holiday':
      case 'holidays':
        return const Color(0xFF34C759);
      default:
        return const Color(0xFFFF9500);
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
    final threshold = screenWidth * 0.25;

    if (_dragPosition.dx.abs() > threshold) {
      if (_dragPosition.dx > 0) {
        widget.onSwipeRight?.call();
      } else {
        widget.onSwipeLeft?.call();
      }
      // Don't reset drag position here; let parent handle after animation
    } else {
      setState(() {
        _dragPosition = Offset.zero;
        _isDragging = false;
      });
    }
  }

  // Allow parent to reset drag state when card is no longer top
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
                    color: const Color(0xFF1E1E22),
                    border: Border.all(width: 2, color: Colors.transparent),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _categoryColor.withOpacity(0.15),
                        Colors.transparent,
                        _categoryColor.withOpacity(0.08),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Gradient border effect
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(width: 2),
                          gradient: _categoryGradient,
                        ),
                      ),
                      // Content
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Image section
                          if (widget.imageUrl.isNotEmpty)
                            Stack(
                              children: [
                                AnimatedOpacity(
                                  opacity: _imageLoaded ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(28),
                                      topRight: Radius.circular(28),
                                    ),
                                    child: Image.network(
                                      widget.imageUrl,
                                      height: 220,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      frameBuilder:
                                          (
                                            context,
                                            child,
                                            frame,
                                            wasSynchronouslyLoaded,
                                          ) {
                                            if (frame != null) {
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    if (mounted) {
                                                      setState(
                                                        () =>
                                                            _imageLoaded = true,
                                                      );
                                                    }
                                                  });
                                            }
                                            return child;
                                          },
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              height: 220,
                                              color: Colors.grey.shade800,
                                              child: const Center(
                                                child: Icon(
                                                  Icons.history_edu,
                                                  size: 60,
                                                  color: Colors.white38,
                                                ),
                                              ),
                                            );
                                          },
                                    ),
                                  ),
                                ),
                                // Dark overlay gradient
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 80,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withOpacity(0.3),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          // Add top padding when no image
                          if (widget.imageUrl.isEmpty)
                            const SizedBox(height: 40),
                          // Text content
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  24,
                                  24,
                                  32,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Year badge with gradient
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: _categoryGradient,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: _categoryColor.withOpacity(
                                            0.6,
                                          ),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        widget.year,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // Title with accent underline
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.title,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.92,
                                            ),
                                            fontSize: 21,
                                            fontWeight: FontWeight.bold,
                                            height: 1.3,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          height: 3,
                                          width: 60,
                                          decoration: BoxDecoration(
                                            gradient: _categoryGradient,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    // Description
                                    Text(
                                      widget.description,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 16,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Category badge
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _categoryColor.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _categoryColor.withOpacity(0.5),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _categoryColor.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ?swipeOverlay,
          ],
        ),
      ),
    );
  }
}
