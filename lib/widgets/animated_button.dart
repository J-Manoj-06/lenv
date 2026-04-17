import 'package:flutter/material.dart';

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
  late final AnimationController _breathController;
  late final AnimationController _entryController;
  late final AnimationController _tapController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
    )..forward();

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _breathController.dispose();
    _entryController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  Future<void> _onTapDown(TapDownDetails details) async {
    await _tapController.animateTo(0.96, curve: Curves.easeOut);
  }

  Future<void> _onTapUp(TapUpDetails details) async {
    await _tapController.animateTo(1.0, curve: Curves.easeOut);
    if (mounted) {
      widget.onPressed();
    }
  }

  Future<void> _onTapCancel() async {
    await _tapController.animateTo(1.0, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _breathController,
          _entryController,
          _tapController,
        ]),
        builder: (context, _) {
          final breath = 0.95 + (_breathController.value * 0.05);
          final entry = CurvedAnimation(
            parent: _entryController,
            curve: Curves.elasticOut,
          ).value;
          final entryScale = 0.92 + (entry * 0.08);
          final scale = breath * entryScale * _tapController.value;

          return Transform.scale(
            scale: scale,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              child: Semantics(
                button: true,
                label: widget.label,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF2800D), Color(0xFFE26600)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF2800D).withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _ShimmerSweep(
                            progress: _breathController.value,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(widget.icon, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
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
      offset: Offset((progress * 220) - 110, 0),
      child: Transform.rotate(
        angle: -0.35,
        child: Container(
          width: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.16),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
