import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnimatedChallengeButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  const AnimatedChallengeButton({
    super.key,
    required this.onPressed,
    this.label = 'Take Challenge',
    this.icon = Icons.play_arrow,
  });

  @override
  State<AnimatedChallengeButton> createState() =>
      _AnimatedChallengeButtonState();
}

class _AnimatedChallengeButtonState extends State<AnimatedChallengeButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _tapController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _tapController.animateTo(0.95, curve: Curves.easeOut);
    if (!mounted) return;
    await HapticFeedback.lightImpact();
    await _tapController.animateTo(1.0, curve: Curves.easeOutBack);
    if (mounted) {
      widget.onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _tapController]),
        builder: (context, child) {
          final pulse =
              0.5 - 0.5 * math.cos(2 * math.pi * _pulseController.value);
          final scale = (1.0 + (pulse * 0.03)) * _tapController.value;
          final glowOpacity = 0.4 + (pulse * 0.6);
          final glowBlur = 10.0 + (pulse * 10.0);
          final glowSpread = 0.5 + (pulse * 0.8);

          return Transform.scale(
            scale: scale,
            child: Semantics(
              button: true,
              label: widget.label,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _handleTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFF2800D,
                          ).withOpacity(0.16 * glowOpacity),
                          blurRadius: glowBlur,
                          spreadRadius: glowSpread,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFF2800D),
                                    Color(0xFFE26600),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _ShimmerSweep(
                                progress: _pulseController.value,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.icon,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShimmerSweep extends StatelessWidget {
  final double progress;

  const _ShimmerSweep({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset((progress * 240) - 120, 0),
      child: Transform.rotate(
        angle: -0.28,
        child: Container(
          width: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0),
                Colors.white.withOpacity(0.16),
                Colors.white.withOpacity(0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
