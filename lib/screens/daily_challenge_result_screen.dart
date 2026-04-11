import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class DailyChallengeResultScreen extends StatefulWidget {
  final bool isWinner;
  final int score;
  final int passingScore;
  final VoidCallback onContinue;
  final int streakDays;

  const DailyChallengeResultScreen({
    super.key,
    required this.isWinner,
    required this.score,
    this.passingScore = 50,
    required this.onContinue,
    this.streakDays = 1,
  });

  @override
  State<DailyChallengeResultScreen> createState() =>
      _DailyChallengeResultScreenState();
}

class _DailyChallengeResultScreenState extends State<DailyChallengeResultScreen>
    with TickerProviderStateMixin {
  static const List<Color> _confettiColors = <Color>[
    Color(0xFF4CAF50),
    Color(0xFFFFD700),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
  ];

  late final AnimationController _overlayController;
  late final AnimationController _badgeController;
  late final AnimationController _titleController;
  late final AnimationController _scoreController;
  late final AnimationController _streakController;
  late final AnimationController _ctaController;
  late final AnimationController _shakeController;
  late final AnimationController _borderPulseController;
  late final AnimationController _loserTitleController;
  late final AnimationController _subtextController;
  late final ConfettiController _confettiController;

  late final Animation<double> _overlayFade;
  late final Animation<double> _badgeScale;
  late final Animation<Offset> _winnerTitleOffset;
  late final Animation<double> _winnerTitleFade;
  late final Animation<double> _scoreAnimation;
  late final Animation<double> _streakScale;
  late final Animation<double> _ctaFade;
  late final Animation<double> _shakeOffset;
  late final Animation<double> _borderPulseOpacity;
  late final Animation<Offset> _loserTitleOffset;
  late final Animation<double> _loserTitleFade;
  late final Animation<double> _subtextFade;

  Timer? _autoDismissTimer;
  Timer? _ctaTimer;
  bool _isDismissing = false;

  int get _clampedScore => widget.score.clamp(0, 100);

  @override
  void initState() {
    super.initState();

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _streakController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _ctaController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _borderPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _loserTitleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _subtextController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    _overlayFade = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeIn,
    );

    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.1,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.1,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_badgeController);

    _winnerTitleOffset =
        Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero).animate(
          CurvedAnimation(parent: _titleController, curve: Curves.easeOutCubic),
        );

    _winnerTitleFade = CurvedAnimation(
      parent: _titleController,
      curve: Curves.easeIn,
    );

    _scoreAnimation = Tween<double>(begin: 0, end: _clampedScore.toDouble())
        .animate(
          CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic),
        );

    _streakScale = CurvedAnimation(
      parent: _streakController,
      curve: Curves.elasticOut,
    );

    _ctaFade = CurvedAnimation(parent: _ctaController, curve: Curves.easeIn);

    _shakeOffset = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.linear));

    _borderPulseOpacity =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            weight: 50,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 1.0, end: 0.0),
            weight: 50,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _borderPulseController,
            curve: Curves.easeInOut,
          ),
        );

    _loserTitleOffset =
        Tween<Offset>(begin: const Offset(0, -0.14), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _loserTitleController,
            curve: Curves.easeOutCubic,
          ),
        );

    _loserTitleFade = CurvedAnimation(
      parent: _loserTitleController,
      curve: Curves.easeIn,
    );

    _subtextFade = CurvedAnimation(
      parent: _subtextController,
      curve: Curves.easeIn,
    );

    if (widget.isWinner) {
      _confettiController.play();
      _badgeController.forward();
      _titleController.forward();
      _scoreController.forward();
      _streakController.forward();
      _ctaTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          _ctaController.forward();
        }
      });
    } else {
      _shakeController.forward();
      _borderPulseController.forward();
      _loserTitleController.forward();
      _subtextController.forward();
      _ctaTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          _ctaController.forward();
        }
      });
    }

    _autoDismissTimer = Timer(const Duration(seconds: 6), _dismiss);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _ctaTimer?.cancel();
    _overlayController.dispose();
    _badgeController.dispose();
    _titleController.dispose();
    _scoreController.dispose();
    _streakController.dispose();
    _ctaController.dispose();
    _shakeController.dispose();
    _borderPulseController.dispose();
    _loserTitleController.dispose();
    _subtextController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    widget.onContinue();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildOverlay(BuildContext context) {
    return FadeTransition(
      opacity: _overlayFade,
      child: Container(
        color: Colors.black.withOpacity(widget.isWinner ? 0.6 : 0.7),
      ),
    );
  }

  Widget _buildWinnerContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaceColor = colorScheme.surface.withOpacity(
      theme.brightness == Brightness.dark ? 0.96 : 0.98,
    );

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 28,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _badgeScale,
                    child: Container(
                      width: 126,
                      height: 126,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFD86B), Color(0xFFFFB300)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.35),
                            blurRadius: 26,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFFFD700),
                        size: 64,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SlideTransition(
                    position: _winnerTitleOffset,
                    child: FadeTransition(
                      opacity: _winnerTitleFade,
                      child: const Text(
                        'Challenge Complete!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _scoreAnimation,
                    builder: (context, child) {
                      return Text(
                        'Score: ${_scoreAnimation.value.round()}/100',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ScaleTransition(
                    scale: _streakScale,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB300),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '🔥 ${widget.streakDays} day streak!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeTransition(
                    opacity: _ctaFade,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _dismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'Keep Going →',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoserContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surfaceColor = colorScheme.surface.withOpacity(
      theme.brightness == Brightness.dark ? 0.96 : 0.98,
    );

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AnimatedBuilder(
              animation: _borderPulseOpacity,
              builder: (context, child) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.red.withOpacity(_borderPulseOpacity.value),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.32),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _shakeOffset,
                    builder: (context, child) {
                      final oscillation = math.sin(
                        _shakeOffset.value * math.pi * 8,
                      );
                      final offsetX = oscillation * 8;
                      return Transform.translate(
                        offset: Offset(offsetX, 0),
                        child: child,
                      );
                    },
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.1),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFFEF5350),
                        size: 66,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SlideTransition(
                    position: _loserTitleOffset,
                    child: FadeTransition(
                      opacity: _loserTitleFade,
                      child: const Text(
                        'Not Quite!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Score: $_clampedScore/100',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FadeTransition(
                    opacity: _subtextFade,
                    child: Text(
                      'Review your mistakes and try again tomorrow.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        color: colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FadeTransition(
                    opacity: _ctaFade,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _dismiss,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(
                            color: Colors.white,
                            width: 1.6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text(
                          'Try Again Tomorrow',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _dismiss();
        }
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: _buildOverlay(context),
              ),
            ),
            if (widget.isWinner)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: ConfettiWidget(
                        confettiController: _confettiController,
                        blastDirectionality: BlastDirectionality.explosive,
                        blastDirection: math.pi / 2,
                        numberOfParticles: 60,
                        emissionFrequency: 0.08,
                        shouldLoop: false,
                        gravity: 0.18,
                        maxBlastForce: 24,
                        minBlastForce: 8,
                        colors: _confettiColors,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.isWinner) const SideFlowerBurst(),
            SafeArea(
              child: widget.isWinner
                  ? _buildWinnerContent(context)
                  : _buildLoserContent(context),
            ),
          ],
        ),
      ),
    );
  }
}

class SideFlowerBurst extends StatefulWidget {
  const SideFlowerBurst({super.key});

  @override
  State<SideFlowerBurst> createState() => _SideFlowerBurstState();
}

class _SideFlowerBurstState extends State<SideFlowerBurst>
    with TickerProviderStateMixin {
  static const List<Color> _flowerColors = <Color>[
    Color(0xFFFFC1CC),
    Color(0xFFFFE082),
    Color(0xFFA5D6A7),
    Color(0xFFCE93D8),
  ];

  static const int _flowersPerSide = 8;

  late final AnimationController _controller;
  late final List<_FlowerSpec> _leftFlowers;
  late final List<_FlowerSpec> _rightFlowers;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();

    _leftFlowers = List<_FlowerSpec>.generate(_flowersPerSide, (index) {
      return _buildSpec(index, true);
    });
    _rightFlowers = List<_FlowerSpec>.generate(_flowersPerSide, (index) {
      return _buildSpec(index, false);
    });
  }

  _FlowerSpec _buildSpec(int index, bool isLeft) {
    final random = math.Random(1000 + index + (isLeft ? 0 : 100));
    return _FlowerSpec(
      side: isLeft ? _FlowerSide.left : _FlowerSide.right,
      size: 16 + random.nextDouble() * 12,
      top: 64 + random.nextDouble() * 320,
      delay: Duration(milliseconds: index * 150 + (isLeft ? 0 : 90)),
      swaySeed: random.nextDouble() * math.pi * 2,
      rotationSeed: random.nextDouble() * math.pi * 2,
      color: _flowerColors[random.nextInt(_flowerColors.length)],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              ..._leftFlowers.map(
                (flower) => _buildFlower(context, flower, width),
              ),
              ..._rightFlowers.map(
                (flower) => _buildFlower(context, flower, width),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFlower(
    BuildContext context,
    _FlowerSpec flower,
    double screenWidth,
  ) {
    final t = _controller.value;
    final delayT = flower.delay.inMilliseconds / 3200.0;
    final localT = ((t - delayT) / 0.88).clamp(0.0, 1.0);

    final entryT = ((t - delayT) / (600 / 3200.0)).clamp(0.0, 1.0);
    final driftT = ((t - delayT) / (2800 / 3200.0)).clamp(0.0, 1.0);
    final fadeT = ((t - delayT - (2000 / 3200.0)) / (600 / 3200.0)).clamp(
      0.0,
      1.0,
    );

    final entryCurve = Curves.easeOutCubic.transform(entryT);
    final driftCurve = Curves.easeInOut.transform(driftT);

    final isLeft = flower.side == _FlowerSide.left;
    final startX = isLeft ? -40.0 : screenWidth + 40.0;
    final endX = isLeft ? 20.0 : screenWidth - 20.0;
    final x = startX + ((endX - startX) * entryCurve);
    final y = flower.top - (120.0 * driftCurve);

    final sway = math.sin((t * math.pi * 3.0) + flower.swaySeed) * 10.0;
    final rotation =
        (-0.2 + (0.4 * Curves.easeInOut.transform(localT))) +
        (math.sin((t * math.pi * 2.0) + flower.rotationSeed) * 0.06);
    final opacity = (1.0 - fadeT) * 0.85 + 0.05;

    return Positioned(
      left: x,
      top: y,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(sway, 0),
          child: Transform.rotate(
            angle: rotation,
            child: Icon(
              Icons.local_florist_rounded,
              size: flower.size,
              color: flower.color.withOpacity(0.88),
            ),
          ),
        ),
      ),
    );
  }
}

enum _FlowerSide { left, right }

class _FlowerSpec {
  final _FlowerSide side;
  final double size;
  final double top;
  final Duration delay;
  final double swaySeed;
  final double rotationSeed;
  final Color color;

  const _FlowerSpec({
    required this.side,
    required this.size,
    required this.top,
    required this.delay,
    required this.swaySeed,
    required this.rotationSeed,
    required this.color,
  });
}
