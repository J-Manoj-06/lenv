import 'package:flutter/material.dart';
import 'history_card.dart';

class HistoryCardData {
  final String title;
  final String description;
  final String year;
  final String imageUrl;
  final String category;

  HistoryCardData({
    required this.title,
    required this.description,
    required this.year,
    required this.imageUrl,
    required this.category,
  });
}

class HistoryCardDeck extends StatefulWidget {
  final List<HistoryCardData> cards;
  final VoidCallback? onDeckComplete;

  const HistoryCardDeck({super.key, required this.cards, this.onDeckComplete});

  @override
  State<HistoryCardDeck> createState() => _HistoryCardDeckState();
}

class _HistoryCardDeckState extends State<HistoryCardDeck>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late List<AnimationController> _exitControllers;
  late List<Animation<double>> _exitAnimations;
  bool _lastSwipeRight = true;
  final Map<int, GlobalKey<State<HistoryCard>>> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _exitControllers = List.generate(
      widget.cards.length,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      ),
    );
    _exitAnimations = _exitControllers
        .map(
          (controller) =>
              CurvedAnimation(parent: controller, curve: Curves.easeInOut),
        )
        .toList();
  }

  @override
  void dispose() {
    for (var controller in _exitControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleSwipe(bool isRight) {
    _lastSwipeRight = isRight;
    if (_currentIndex >= widget.cards.length) return;

    _exitControllers[_currentIndex].forward().then((_) {
      // Reset drag state of the card that just exited
      final key = _cardKeys[_currentIndex];
      if (key?.currentState != null) {
        try {
          (key!.currentState as dynamic).resetDrag();
        } catch (_) {}
      }
      setState(() {
        _currentIndex++;
        if (_currentIndex >= widget.cards.length) {
          widget.onDeckComplete?.call();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentIndex >= widget.cards.length) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1C),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF34C759).withOpacity(0.3),
                      const Color(0xFF30D5C8).withOpacity(0.3),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF34C759).withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  size: 64,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'All Caught Up!',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You\'ve explored all events for today',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Come back tomorrow for more history',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: Stack(
            children: [
              // Show up to 3 cards for depth effect.
              // IMPORTANT: Render background cards first and the TOP card last
              // so it sits on top and receives gestures.
              for (
                int i = ([
                  _currentIndex + 2,
                  widget.cards.length - 1,
                ].reduce((a, b) => a < b ? a : b));
                i >= _currentIndex;
                i--
              )
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _exitAnimations[i],
                    builder: (context, child) {
                      final isTopCard = i == _currentIndex;
                      double scale = 1.0;
                      double yOffset = 0.0;
                      double opacity = 1.0;
                      double xOffset = 0.0;
                      double rotation = 0.0;

                      if (!isTopCard) {
                        final diff = i - _currentIndex;
                        // Cards behind scale down and shift
                        scale = 1.0 - (diff * 0.06);
                        yOffset = diff * 12.0;
                        opacity = 1.0 - (diff * 0.35);
                      }

                      // Exit animation for current card
                      if (isTopCard && _exitControllers[i].isAnimating) {
                        final v = _exitAnimations[i].value;
                        opacity = 1.0 - v;
                        scale = 1.0 - (v * 0.1);
                        xOffset =
                            (_lastSwipeRight ? 1 : -1) *
                            v *
                            constraints.maxWidth *
                            1.2;
                        rotation =
                            (_lastSwipeRight ? 1 : -1) *
                            v *
                            0.25; // ~14 degrees
                      }

                      return Transform.scale(
                        scale: scale,
                        child: Transform.translate(
                          offset: Offset(xOffset, yOffset),
                          child: Transform.rotate(
                            angle: rotation,
                            child: Opacity(opacity: opacity, child: child),
                          ),
                        ),
                      );
                    },
                    child: HistoryCard(
                      key: _cardKeys[i] ??= GlobalKey<State<HistoryCard>>(),
                      title: widget.cards[i].title,
                      description: widget.cards[i].description,
                      year: widget.cards[i].year,
                      imageUrl: widget.cards[i].imageUrl,
                      category: widget.cards[i].category,
                      isTopCard: i == _currentIndex,
                      onSwipeLeft: () => _handleSwipe(false),
                      onSwipeRight: () => _handleSwipe(true),
                      onReset: () =>
                          (_cardKeys[i]?.currentState as dynamic)?.resetDrag(),
                    ),
                  ),
                ),
              // Card counter
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.cards.length}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
