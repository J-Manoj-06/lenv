import 'dart:math' as math;
import 'package:flutter/material.dart';

class AttendanceSpeedometerGauge extends StatefulWidget {
  final double attendancePercent;
  final int? presentCount;
  final int? totalCount;
  final Color? cardColor;
  final Color? textColor;
  final Color? subtitleColor;
  final String? title;

  const AttendanceSpeedometerGauge({
    super.key,
    required this.attendancePercent,
    this.presentCount,
    this.totalCount,
    this.cardColor,
    this.textColor,
    this.subtitleColor,
    this.title,
  });

  @override
  State<AttendanceSpeedometerGauge> createState() =>
      _AttendanceSpeedometerGaugeState();
}

class _AttendanceSpeedometerGaugeState extends State<AttendanceSpeedometerGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        widget.cardColor ?? (isDark ? const Color(0xFF1E293B) : Colors.white);
    final textColor =
        widget.textColor ?? (isDark ? Colors.white : const Color(0xFF0F172A));
    final subtitleColor =
        widget.subtitleColor ??
        (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B));
    final borderColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

    // Determine status based on percentage
    String status;
    Color statusColor;
    IconData statusIcon;

    if (widget.attendancePercent >= 90) {
      status = 'Excellent';
      statusColor = const Color(0xFF34D399);
      statusIcon = Icons.check_circle_outline;
    } else if (widget.attendancePercent >= 75) {
      status = 'Average';
      statusColor = const Color(0xFFFFA726);
      statusIcon = Icons.info_outline;
    } else {
      status = 'Low';
      statusColor = const Color(0xFFFB7185);
      statusIcon = Icons.warning_amber_outlined;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            children: [
              // Title
              Text(
                widget.title ?? "Today's Attendance",
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              // Speedometer Gauge
              SizedBox(
                height: 160,
                child: CustomPaint(
                  size: const Size(double.infinity, 160),
                  painter: _SpeedometerPainter(
                    percentage: widget.attendancePercent * _animation.value,
                    textColor: textColor,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Percentage Display
              Text(
                '${widget.attendancePercent.toInt()}%',
                style: TextStyle(
                  color: textColor,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),

              if (widget.presentCount != null && widget.totalCount != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${widget.presentCount} / ${widget.totalCount}',
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Status Chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Custom Painter for Speedometer Gauge
class _SpeedometerPainter extends CustomPainter {
  final double percentage;
  final Color textColor;

  _SpeedometerPainter({required this.percentage, required this.textColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.75);
    final radius = size.width * 0.35;
    const startAngle = math.pi; // 180°
    const sweepAngle = math.pi; // 180°

    // Background arc with subtle glow
    final bgGlowPaint = Paint()
      ..color = textColor.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgGlowPaint,
    );

    final bgPaint = Paint()
      ..color = textColor.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Premium gradient arc with glow effect
    const segmentCount = 180;
    final colors = [
      const Color(0xFFEF4444), // Red
      const Color(0xFFF97316), // Orange
      const Color(0xFFFBBF24), // Amber
      const Color(0xFFA3E635), // Lime
      const Color(0xFF10B981), // Emerald
    ];

    for (int i = 0; i < segmentCount; i++) {
      final progress = i / segmentCount;
      final angle = startAngle + (progress * sweepAngle);
      final segmentSweep = sweepAngle / segmentCount * 1.01; // Slight overlap

      // Smooth color interpolation
      Color color;
      final colorProgress = progress * (colors.length - 1);
      final colorIndex = colorProgress.floor();
      final colorT = colorProgress - colorIndex;

      if (colorIndex >= colors.length - 1) {
        color = colors.last;
      } else {
        color = Color.lerp(colors[colorIndex], colors[colorIndex + 1], colorT)!;
      }

      // Outer glow
      final glowPaint = Paint()
        ..color = color.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        segmentSweep,
        false,
        glowPaint,
      );

      // Main gradient segment
      final segmentPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        segmentSweep,
        false,
        segmentPaint,
      );
    }

    // Add rounded caps at the ends
    final startCapPosition = Offset(
      center.dx + radius * math.cos(startAngle),
      center.dy + radius * math.sin(startAngle),
    );
    final endCapPosition = Offset(
      center.dx + radius * math.cos(startAngle + sweepAngle),
      center.dy + radius * math.sin(startAngle + sweepAngle),
    );

    canvas.drawCircle(startCapPosition, 9, Paint()..color = colors.first);
    canvas.drawCircle(endCapPosition, 9, Paint()..color = colors.last);

    // Tick marks
    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + (i / 10) * sweepAngle;
      final tickStart = Offset(
        center.dx + (radius - 25) * math.cos(angle),
        center.dy + (radius - 25) * math.sin(angle),
      );
      final tickEnd = Offset(
        center.dx + (radius - 15) * math.cos(angle),
        center.dy + (radius - 15) * math.sin(angle),
      );

      final tickPaint = Paint()
        ..color = textColor.withOpacity(0.25)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(tickStart, tickEnd, tickPaint);
    }

    // Needle with shadow effect
    final needleAngle = startAngle + (percentage / 100) * sweepAngle;
    final needleEnd = Offset(
      center.dx + (radius - 10) * math.cos(needleAngle),
      center.dy + (radius - 10) * math.sin(needleAngle),
    );

    // Needle shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawLine(
      Offset(center.dx + 2, center.dy + 2),
      Offset(needleEnd.dx + 2, needleEnd.dy + 2),
      shadowPaint,
    );

    // Needle gradient
    final needlePaint = Paint()
      ..shader = LinearGradient(
        colors: [textColor, textColor.withOpacity(0.7)],
      ).createShader(Rect.fromPoints(center, needleEnd))
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, needleEnd, needlePaint);

    // Center dot with glow
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = textColor.withOpacity(0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    canvas.drawCircle(center, 8, Paint()..color = textColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
