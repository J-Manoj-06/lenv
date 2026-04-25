import 'dart:math' as math;

import 'package:flutter/material.dart';

class AnimatedPointsCardShell extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    double cardScale,
    double floatOffset,
    double glowOpacity,
  )
  builder;

  const AnimatedPointsCardShell({super.key, required this.builder});

  @override
  State<AnimatedPointsCardShell> createState() =>
      _AnimatedPointsCardShellState();
}

class _AnimatedPointsCardShellState extends State<AnimatedPointsCardShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final wave = 0.5 - 0.5 * math.cos(2 * math.pi * t);
          final cardScale = 1.0 + (0.02 * wave);
          final floatOffset = -math.sin(2 * math.pi * t) * 6.0;
          final glowOpacity = 0.4 + (0.6 * wave);

          return widget.builder(context, cardScale, floatOffset, glowOpacity);
        },
      ),
    );
  }
}
