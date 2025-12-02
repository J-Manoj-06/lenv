import 'package:flutter/material.dart';
import 'fact_card.dart';

class FactCardDeck extends StatefulWidget {
  final List<String> facts; // single fact list currently
  final VoidCallback? onDeckComplete;

  const FactCardDeck({super.key, required this.facts, this.onDeckComplete});

  @override
  State<FactCardDeck> createState() => _FactCardDeckState();
}

class _FactCardDeckState extends State<FactCardDeck>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late List<AnimationController> _exitControllers;
  late List<Animation<double>> _exitAnimations;
  bool _lastSwipeRight = true;
  final Map<int, GlobalKey<State<FactCard>>> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _exitControllers = List.generate(
      widget.facts.length,
      (index) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      ),
    );
    _exitAnimations = _exitControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeInOut))
        .toList();
  }

  @override
  void dispose() {
    for (var c in _exitControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _handleSwipe(bool isRight) {
    _lastSwipeRight = isRight;
    if (_currentIndex >= widget.facts.length) return;
    _exitControllers[_currentIndex].forward().then((_) {
      final key = _cardKeys[_currentIndex];
      if (key?.currentState != null) {
        try {
          (key!.currentState as dynamic).resetDrag();
        } catch (_) {}
      }
      setState(() {
        _currentIndex++;
        if (_currentIndex >= widget.facts.length) {
          widget.onDeckComplete?.call();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentIndex >= widget.facts.length) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 64,
              color: Colors.white.withOpacity(0.9),
            ),
            const SizedBox(height: 20),
            Text(
              'Fact Viewed',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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
                  widget.facts.length - 1,
                ].reduce((a, b) => a < b ? a : b));
                i >= _currentIndex;
                i--
              )
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _exitAnimations[i],
                    builder: (context, child) {
                      final isTop = i == _currentIndex;
                      double scale = 1.0;
                      double yOffset = 0.0;
                      double opacity = 1.0;
                      double xOffset = 0.0;
                      double rotation = 0.0;

                      if (!isTop) {
                        final diff = i - _currentIndex;
                        scale = 1.0 - (diff * 0.06);
                        yOffset = diff * 12.0;
                        opacity = 1.0 - (diff * 0.35);
                      }
                      if (isTop && _exitControllers[i].isAnimating) {
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
                    child: FactCard(
                      key: _cardKeys[i] ??= GlobalKey<State<FactCard>>(),
                      text: widget.facts[i],
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
