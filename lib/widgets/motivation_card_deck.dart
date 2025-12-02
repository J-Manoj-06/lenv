import 'package:flutter/material.dart';
import 'motivation_card.dart';
import 'swipe_card_deck.dart';

class MotivationCardDeck extends StatefulWidget {
  final List<CardData> cards;
  final VoidCallback? onDeckComplete;

  const MotivationCardDeck({
    super.key,
    required this.cards,
    this.onDeckComplete,
  });

  @override
  State<MotivationCardDeck> createState() => _MotivationCardDeckState();
}

class _MotivationCardDeckState extends State<MotivationCardDeck>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late List<AnimationController> _exitControllers;
  late List<Animation<double>> _exitAnimations;
  bool _lastSwipeRight = true;
  final Map<int, GlobalKey<State<MotivationCard>>> _cardKeys = {};

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
              Icon(
                Icons.check_circle_outline_rounded,
                size: 64,
                color: Colors.white.withOpacity(0.9),
              ),
              const SizedBox(height: 24),
              Text(
                'All Done!',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
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
                        scale = 1.0 - (diff * 0.06);
                        yOffset = diff * 12.0;
                        opacity = 1.0 - (diff * 0.35);
                      }

                      if (isTopCard && _exitControllers[i].isAnimating) {
                        final v = _exitAnimations[i].value;
                        opacity = 1.0 - v;
                        scale = 1.0 - (v * 0.1);
                        xOffset =
                            (_lastSwipeRight ? 1 : -1) *
                            v *
                            constraints.maxWidth *
                            1.2;
                        rotation = (_lastSwipeRight ? 1 : -1) * v * 0.25;
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
                    child: MotivationCard(
                      key: _cardKeys[i] ??= GlobalKey<State<MotivationCard>>(),
                      text: widget.cards[i].text,
                      author: widget.cards[i].author,
                      isTopCard: i == _currentIndex,
                      onSwipeLeft: () => _handleSwipe(false),
                      onSwipeRight: () => _handleSwipe(true),
                      onReset: () =>
                          (_cardKeys[i]?.currentState as dynamic)?.resetDrag(),
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
