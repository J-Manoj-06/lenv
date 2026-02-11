import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Minimal orange-themed offline animation screen
/// Displayed when:
/// 1. No internet connection
/// 2. Slow internet (API timeout)
/// 3. No cached data available
class OfflineAnimationScreen extends StatelessWidget {
  const OfflineAnimationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5E6), // Very light orange tint
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
          child: Lottie.asset(
            'assets/animations/academic_loading.json',
            fit: BoxFit.contain,
            frameRate: FrameRate.max,
            repeat: true,
            // Fallback widget if animation fails to load
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackAnimation();
            },
          ),
        ),
      ),
    );
  }

  /// Fallback animation using Flutter widgets if Lottie fails
  Widget _buildFallbackAnimation() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 2),
      builder: (context, value, child) {
        return Opacity(
          opacity: (value * 2) % 1,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6F00).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.school, size: 50, color: Color(0xFFFF6F00)),
          ),
        );
      },
      onEnd: () {
        // Loop animation
      },
    );
  }
}

/// Alternative offline screen with custom animated book icon
class OfflineAnimationScreenAlt extends StatefulWidget {
  const OfflineAnimationScreenAlt({super.key});

  @override
  State<OfflineAnimationScreenAlt> createState() =>
      _OfflineAnimationScreenAltState();
}

class _OfflineAnimationScreenAltState extends State<OfflineAnimationScreenAlt>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacityAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0), // Very subtle orange
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFF6F00).withOpacity(0.1),
                        const Color(0xFFFF6F00).withOpacity(0.05),
                        Colors.transparent,
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 60,
                    color: Color(0xFFFF6F00),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
