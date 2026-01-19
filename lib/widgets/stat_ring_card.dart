import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Reusable modern stat card with ring chart
class StatRingCard extends StatefulWidget {
  final double percentage;
  final String primaryLabel;
  final String primaryValue;
  final List<StatDetail> details;
  final Color accentColor;
  final double ringSize;

  const StatRingCard({
    Key? key,
    required this.percentage,
    required this.primaryLabel,
    required this.primaryValue,
    required this.details,
    this.accentColor = const Color(0xFFF2800D),
    this.ringSize = 110,
  }) : super(key: key);

  @override
  State<StatRingCard> createState() => _StatRingCardState();
}

class _StatRingCardState extends State<StatRingCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF2A2A2A), const Color(0xFF1F1F1F)]
                  : [Colors.white, Colors.grey.shade50],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.3)
                    : Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Ring Chart
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: widget.ringSize,
                        height: widget.ringSize,
                        child: CustomPaint(
                          painter: AnimatedRingPainter(
                            progress:
                                widget.percentage / 100 * _animation.value,
                            strokeWidth: 14,
                            color: widget.accentColor,
                            backgroundColor: isDark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.grey.shade200,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.primaryValue,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black87,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.primaryLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(width: 60),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: widget.details.asMap().entries.map((entry) {
                    final index = entry.key;
                    final detail = entry.value;
                    final isLast = index == widget.details.length - 1;

                    return Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 32),
                      child: Row(
                        children: [
                          if (detail.icon != null) ...[
                            Icon(
                              detail.icon,
                              size: 16,
                              color: detail.iconColor ?? widget.accentColor,
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (detail.dotColor != null) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: detail.dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detail.value,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    height: 1.2,
                                  ),
                                ),
                                Text(
                                  detail.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail item for stat card
class StatDetail {
  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Color? dotColor;

  const StatDetail({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.dotColor,
  });
}

/// Animated ring painter with smooth progress
class AnimatedRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;

  AnimatedRingPainter({
    required this.progress,
    this.strokeWidth = 10,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc with gradient effect
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [color, color.withOpacity(0.7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top (12 o'clock)
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(AnimatedRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
