import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class AnimatedStreakIcon extends StatefulWidget {
  final int streakCount;

  const AnimatedStreakIcon({super.key, required this.streakCount});

  @override
  State<AnimatedStreakIcon> createState() => _AnimatedStreakIconState();
}

class _AnimatedStreakIconState extends State<AnimatedStreakIcon>
    with TickerProviderStateMixin {
  static const Color _orange = Color(0xFFF2800D);
  static const Color _deepOrange = Color(0xFFE26900);

  late final AnimationController _tiltController;
  late final Animation<double> _tiltAnimation;
  late final AnimationController _burstSpinController;
  late final Animation<double> _burstSpinAnimation;

  Timer? _burstTimer;
  Timer? _burstResetTimer;

  bool _glowForward = true;
  bool _burstActive = false;

  @override
  void initState() {
    super.initState();

    _tiltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _tiltAnimation =
        Tween<double>(
          begin: -5 * (math.pi / 180),
          end: 5 * (math.pi / 180),
        ).animate(
          CurvedAnimation(parent: _tiltController, curve: Curves.easeInOut),
        );

    _burstSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _burstSpinAnimation = Tween<double>(begin: 0.0, end: math.pi * 2.0).animate(
      CurvedAnimation(parent: _burstSpinController, curve: Curves.easeOutCubic),
    );

    _burstSpinController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _burstSpinController.reset();
      }
    });

    _burstTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted || _burstActive) return;
      setState(() => _burstActive = true);
      _burstSpinController.forward(from: 0);
      _burstResetTimer?.cancel();
      _burstResetTimer = Timer(const Duration(milliseconds: 520), () {
        if (!mounted) return;
        setState(() => _burstActive = false);
      });
    });
  }

  @override
  void dispose() {
    _burstTimer?.cancel();
    _burstResetTimer?.cancel();
    _burstSpinController.dispose();
    _tiltController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Tooltip(
        message: 'Keep your streak alive!',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _orange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 1.0,
                  end: _burstActive ? 1.15 : 1.0,
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, scale, _) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0.4,
                      end: _glowForward ? 1.0 : 0.4,
                    ),
                    duration: const Duration(milliseconds: 750),
                    curve: Curves.easeInOut,
                    onEnd: () {
                      if (!mounted) return;
                      setState(() => _glowForward = !_glowForward);
                    },
                    builder: (context, glowValue, _) {
                      final burstBoost = _burstActive ? 0.25 : 0.0;
                      final opacity = (glowValue + burstBoost).clamp(0.0, 1.0);
                      final blur = 8.0 + (opacity * 8.0);

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _orange.withOpacity(opacity),
                                  blurRadius: blur,
                                  spreadRadius:
                                      0.6 + (_burstActive ? 0.8 : 0.0),
                                ),
                              ],
                            ),
                          ),
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _tiltController,
                              _burstSpinController,
                            ]),
                            builder: (context, child) {
                              final color =
                                  Color.lerp(
                                    _orange,
                                    _deepOrange,
                                    opacity * 0.25,
                                  ) ??
                                  _orange;
                              return Transform.rotate(
                                angle:
                                    _tiltAnimation.value +
                                    _burstSpinAnimation.value,
                                child: Transform.scale(
                                  scale: scale,
                                  child: Icon(
                                    Icons.local_fire_department,
                                    color: color,
                                    size: 24,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(width: 6),
              Text(
                '${widget.streakCount}',
                style: const TextStyle(
                  color: _orange,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
