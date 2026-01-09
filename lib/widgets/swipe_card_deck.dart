import 'package:flutter/material.dart';
import 'swipeable_card.dart';

class CardData {
  final String category;
  final String text;
  final String author;

  CardData({required this.category, required this.text, required this.author});
}

class SwipeCardDeck extends StatefulWidget {
  final List<CardData> cards;
  final VoidCallback? onDeckComplete;

  const SwipeCardDeck({super.key, required this.cards, this.onDeckComplete});

  @override
  State<SwipeCardDeck> createState() => _SwipeCardDeckState();
}

class _SwipeCardDeckState extends State<SwipeCardDeck>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late List<AnimationController> _exitControllers;
  late List<Animation<double>> _exitAnimations;

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
        duration: const Duration(milliseconds: 350),
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
    if (_currentIndex >= widget.cards.length) return;

    _exitControllers[_currentIndex].forward().then((_) {
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
          borderRadius: BorderRadius.circular(26),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: Colors.white.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'All Done!',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Come back tomorrow for more',
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

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.65,
      child: Stack(
        children: [
          // Show up to 3 cards for depth effect
          for (
            int i = _currentIndex;
            i < _currentIndex + 3 && i < widget.cards.length;
            i++
          )
            Positioned.fill(
              child: AnimatedBuilder(
                animation: i > _currentIndex
                    ? _exitAnimations[i - 1]
                    : _exitAnimations[i],
                builder: (context, child) {
                  final isTopCard = i == _currentIndex;
                  double scale = 1.0;
                  double yOffset = 0.0;
                  double opacity = 1.0;

                  if (!isTopCard) {
                    final diff = i - _currentIndex;
                    // Cards behind scale down and shift slightly
                    scale = 1.0 - (diff * 0.04);
                    yOffset = diff * 8.0;
                    opacity = 1.0 - (diff * 0.3);
                  }

                  // Exit animation for current card
                  if (isTopCard && _exitControllers[i].isAnimating) {
                    opacity = 1.0 - _exitAnimations[i].value;
                  }

                  return Transform.scale(
                    scale: scale,
                    child: Transform.translate(
                      offset: Offset(0, yOffset),
                      child: Opacity(opacity: opacity, child: child),
                    ),
                  );
                },
                child: SwipeableCard(
                  category: widget.cards[i].category,
                  text: widget.cards[i].text,
                  author: widget.cards[i].author,
                  isTopCard: i == _currentIndex,
                  onSwipeLeft: () => _handleSwipe(false),
                  onSwipeRight: () => _handleSwipe(true),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
