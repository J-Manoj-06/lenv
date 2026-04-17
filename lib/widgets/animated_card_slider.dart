import 'dart:async';

import 'package:flutter/material.dart';

class AnimatedCardSlider extends StatefulWidget {
  final List<Widget> cards;
  final Duration autoSlideInterval;
  final EdgeInsetsGeometry? padding;

  const AnimatedCardSlider({
    super.key,
    required this.cards,
    this.autoSlideInterval = const Duration(seconds: 4),
    this.padding,
  });

  @override
  State<AnimatedCardSlider> createState() => _AnimatedCardSliderState();
}

class _AnimatedCardSliderState extends State<AnimatedCardSlider> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;
  bool _isInteracting = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
    _startAutoSlide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _timer?.cancel();
    if (widget.cards.length <= 1) return;

    _timer = Timer.periodic(widget.autoSlideInterval, (_) {
      if (!mounted || _isInteracting) return;
      final next = (_currentPage + 1) % widget.cards.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _onInteractionChanged(bool interacting) {
    _isInteracting = interacting;
    if (!interacting) {
      _startAutoSlide();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: Column(
        children: [
          Listener(
            onPointerDown: (_) => _onInteractionChanged(true),
            onPointerUp: (_) => _onInteractionChanged(false),
            onPointerCancel: (_) => _onInteractionChanged(false),
            child: SizedBox(
              height: 320,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.cards.length,
                onPageChanged: (index) {
                  if (!mounted) return;
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final isActive = index == _currentPage;
                  return AnimatedScale(
                    scale: isActive ? 1.0 : 0.9,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: Padding(
                      padding:
                          widget.padding ??
                          const EdgeInsets.symmetric(horizontal: 4),
                      child: widget.cards[index],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.cards.length, (index) {
              final active = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: active ? 22 : 8,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFF2800D)
                      : Theme.of(context).dividerColor.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
