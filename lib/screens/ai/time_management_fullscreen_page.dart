import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimeManagementFullScreenPage extends StatefulWidget {
  final String? userId;
  const TimeManagementFullScreenPage({super.key, this.userId});

  @override
  State<TimeManagementFullScreenPage> createState() =>
      _TimeManagementFullScreenPageState();
}

class _TimeManagementFullScreenPageState
    extends State<TimeManagementFullScreenPage>
    with TickerProviderStateMixin {
  // Pomodoro
  static const int pomodoroTotalSeconds = 25 * 60; // 25 minutes
  int pomodoroRemaining = pomodoroTotalSeconds;
  Timer? pomodoroTimer;
  bool pomodoroRunning = false;
  int completedPomodoros = 0;
  int sessionCount = 0;

  // Study Timer
  int studyDurationMinutes = 30;
  int studyRemainingSeconds = 0;
  Timer? studyTimer;
  bool studyRunning = false;

  // Break Reminder
  bool breakReminderEnabled = false;
  int breakIntervalMinutes = 30;
  Timer? breakReminderTimer;
  DateTime? nextBreakTime;
  int breakRemainingSeconds = 0; // countdown to next break

  late final AnimationController _headerController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _headerFade = CurvedAnimation(
    parent: _headerController,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _headerSlide =
      Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(
        CurvedAnimation(parent: _headerController, curve: Curves.easeOutCubic),
      );

  @override
  void initState() {
    super.initState();
    _headerController.forward();
    _loadPersistedState();
  }

  @override
  void dispose() {
    pomodoroTimer?.cancel();
    studyTimer?.cancel();
    breakReminderTimer?.cancel();
    _headerController.dispose();
    super.dispose();
  }

  void _togglePomodoro() {
    if (pomodoroRunning) {
      pomodoroTimer?.cancel();
      setState(() => pomodoroRunning = false);
      return;
    }
    setState(() => pomodoroRunning = true);
    pomodoroTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (pomodoroRemaining <= 1) {
        t.cancel();
        setState(() {
          pomodoroRunning = false;
          pomodoroRemaining = pomodoroTotalSeconds;
          completedPomodoros += 1;
          sessionCount += 1;
          _persistPomodoroStats();
        });
      } else {
        setState(() => pomodoroRemaining -= 1);
      }
    });
  }

  void _resetPomodoro() {
    pomodoroTimer?.cancel();
    setState(() {
      pomodoroRunning = false;
      pomodoroRemaining = pomodoroTotalSeconds;
    });
  }

  void _startStudyTimer() {
    if (studyRunning) return;
    studyRemainingSeconds = studyDurationMinutes * 60;
    setState(() => studyRunning = true);
    _persistStudySettings();
    studyTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (studyRemainingSeconds <= 1) {
        t.cancel();
        setState(() => studyRunning = false);
        _persistStudySettings();
      } else {
        setState(() => studyRemainingSeconds -= 1);
      }
    });
  }

  void _stopStudyTimer() {
    studyTimer?.cancel();
    setState(() => studyRunning = false);
    _persistStudySettings();
  }

  void _toggleBreakReminder(bool value) {
    setState(() => breakReminderEnabled = value);
    breakReminderTimer?.cancel();
    if (value) {
      nextBreakTime = DateTime.now().add(
        Duration(minutes: breakIntervalMinutes),
      );
      breakRemainingSeconds = breakIntervalMinutes * 60;
      breakReminderTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (nextBreakTime != null) {
          final diff = nextBreakTime!.difference(DateTime.now()).inSeconds;
          if (diff <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Time for a break!'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
            nextBreakTime = DateTime.now().add(
              Duration(minutes: breakIntervalMinutes),
            );
            breakRemainingSeconds = breakIntervalMinutes * 60;
          } else {
            breakRemainingSeconds = diff;
          }
          setState(() {});
        }
      });
      _persistBreakSettings();
    } else {
      nextBreakTime = null;
      breakRemainingSeconds = 0;
      _persistBreakSettings();
    }
  }

  String _formatMinutesSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final uidPart = widget.userId ?? 'local';
    final today = DateTime.now().toIso8601String().split('T')[0];
    completedPomodoros =
        prefs.getInt('pomodoro_completed_${uidPart}_$today') ??
        completedPomodoros;
    sessionCount =
        prefs.getInt('pomodoro_sessions_${uidPart}_$today') ?? sessionCount;
    studyDurationMinutes =
        prefs.getInt('study_duration_$uidPart') ?? studyDurationMinutes;
    breakIntervalMinutes =
        prefs.getInt('break_interval_$uidPart') ?? breakIntervalMinutes;
    final breakEnabled = prefs.getBool('break_enabled_$uidPart') ?? false;
    if (breakEnabled) {
      _toggleBreakReminder(true);
    }
    setState(() {});
  }

  Future<void> _persistPomodoroStats() async {
    final prefs = await SharedPreferences.getInstance();
    final uidPart = widget.userId ?? 'local';
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setInt(
      'pomodoro_completed_${uidPart}_$today',
      completedPomodoros,
    );
    await prefs.setInt('pomodoro_sessions_${uidPart}_$today', sessionCount);
  }

  Future<void> _persistStudySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final uidPart = widget.userId ?? 'local';
    await prefs.setInt('study_duration_$uidPart', studyDurationMinutes);
  }

  Future<void> _persistBreakSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final uidPart = widget.userId ?? 'local';
    await prefs.setInt('break_interval_$uidPart', breakIntervalMinutes);
    await prefs.setBool('break_enabled_$uidPart', breakReminderEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Time Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 42),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SlideTransition(
              position: _headerSlide,
              child: FadeTransition(
                opacity: _headerFade,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.bolt, color: Color(0xFFFFB26B)),
                        SizedBox(width: 8),
                        Text(
                          'Stay focused. Stay disciplined.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            _PomodoroCard(
              remaining: pomodoroRemaining,
              total: pomodoroTotalSeconds,
              running: pomodoroRunning,
              sessionCount: sessionCount,
              completed: completedPomodoros,
              onToggle: _togglePomodoro,
              onReset: _resetPomodoro,
              formatTime: _formatMinutesSeconds,
            ),
            const SizedBox(height: 18),
            _StudyTimerCard(
              running: studyRunning,
              remainingSeconds: studyRemainingSeconds,
              durationMinutes: studyDurationMinutes,
              formatTime: _formatMinutesSeconds,
              onSelectDuration: (m) => setState(() => studyDurationMinutes = m),
              onStart: _startStudyTimer,
              onStop: _stopStudyTimer,
            ),
            const SizedBox(height: 18),
            _BreakReminderCard(
              enabled: breakReminderEnabled,
              interval: breakIntervalMinutes,
              nextBreak: nextBreakTime,
              onToggle: _toggleBreakReminder,
              onIntervalChanged: (m) =>
                  setState(() => breakIntervalMinutes = m),
            ),
          ],
        ),
      ),
    );
  }
}

class _PomodoroCard extends StatelessWidget {
  final int remaining;
  final int total;
  final bool running;
  final int sessionCount;
  final int completed;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final String Function(int) formatTime;
  const _PomodoroCard({
    required this.remaining,
    required this.total,
    required this.running,
    required this.sessionCount,
    required this.completed,
    required this.onToggle,
    required this.onReset,
    required this.formatTime,
  });

  @override
  Widget build(BuildContext context) {
    final progress = 1 - (remaining / total);
    return StitchedCard(
      accentColor: const Color(0xFF7AB8FF).withOpacity(0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Pomodoro Session',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 170,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(170, 170),
                  painter: _RingPainter(progress: progress, active: running),
                ),
                Text(
                  formatTime(remaining),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PillButton(
                label: running ? 'Pause' : 'Start',
                onTap: onToggle,
                color: const Color(0xFF7EE8A9),
              ),
              const SizedBox(width: 12),
              _PillButton(
                label: 'Reset',
                onTap: onReset,
                color: const Color(0xFFFFB26B),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatBadge(label: 'Sessions', value: sessionCount.toString()),
              _StatBadge(label: 'Completed', value: completed.toString()),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudyTimerCard extends StatelessWidget {
  final bool running;
  final int remainingSeconds;
  final int durationMinutes;
  final String Function(int) formatTime;
  final ValueChanged<int> onSelectDuration;
  final VoidCallback onStart;
  final VoidCallback onStop;
  const _StudyTimerCard({
    required this.running,
    required this.remainingSeconds,
    required this.durationMinutes,
    required this.formatTime,
    required this.onSelectDuration,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure progress is a double for LinearProgressIndicator
    final double progress = running
        ? 1 - (remainingSeconds / (durationMinutes * 60))
        : 0.0;
    return StitchedCard(
      accentColor: const Color(0xFFFFB26B).withOpacity(0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.book, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text(
                'Custom Study Timer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [15, 30, 45, 60].map((m) {
              final selected = m == durationMinutes;
              return GestureDetector(
                onTap: running ? null : () => onSelectDuration(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF7AB8FF)
                        : const Color(0xFF2A2A2D),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    '${m}m',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFF2A2A2D),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF7EE8A9)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            running ? 'Remaining: ${formatTime(remainingSeconds)}' : 'Ready',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _PillButton(
                label: running ? 'Stop' : 'Start',
                onTap: running ? onStop : onStart,
                color: const Color(0xFF7EE8A9),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakReminderCard extends StatelessWidget {
  final bool enabled;
  final int interval;
  final DateTime? nextBreak;
  final Function(bool) onToggle;
  final ValueChanged<int> onIntervalChanged;
  const _BreakReminderCard({
    required this.enabled,
    required this.interval,
    required this.nextBreak,
    required this.onToggle,
    required this.onIntervalChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StitchedCard(
      accentColor: const Color(0xFF7EE8A9).withOpacity(0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.self_improvement, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text(
                'Break Reminder',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Get notified when it\'s time to rest.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(
                value: enabled,
                onChanged: onToggle,
                activeThumbColor: const Color(0xFF7EE8A9),
                inactiveThumbColor: const Color(0xFF444446),
              ),
              const SizedBox(width: 10),
              if (enabled)
                Text(
                  'Every $interval min',
                  style: const TextStyle(color: Colors.white70),
                ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [30, 45].map((m) {
                final selected = m == interval;
                return GestureDetector(
                  onTap: () => onIntervalChanged(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF7EE8A9)
                          : const Color(0xFF2A2A2D),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      '${m}m',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _BreathingPulse(enabled: enabled),
            const SizedBox(height: 8),
            Text(
              nextBreak != null
                  ? 'Next break at: ${nextBreak!.hour.toString().padLeft(2, '0')}:${nextBreak!.minute.toString().padLeft(2, '0')}'
                  : '',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class StitchedCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  const StitchedCard({
    super.key,
    required this.child,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF222224),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: accentColor, width: 1.2),
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final bool active;
  _RingPainter({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - 6;

    final basePaint = Paint()
      ..color = const Color(0xFF2A2A2D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, basePaint);

    final progressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF7AB8FF), Color(0xFF7EE8A9)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    final sweep = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweep,
      false,
      progressPaint,
    );

    if (active) {
      final glowPaint = Paint()
        ..color = const Color(0xFF7AB8FF).withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18;
      canvas.drawCircle(center, radius - 3, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active;
}

class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _PillButton({
    required this.label,
    required this.onTap,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.85),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  const _StatBadge({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

class _BreathingPulse extends StatefulWidget {
  final bool enabled;
  const _BreathingPulse({required this.enabled});
  @override
  State<_BreathingPulse> createState() => _BreathingPulseState();
}

class _BreathingPulseState extends State<_BreathingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 0.85 + (_controller.value * 0.25);
        final opacity = 0.3 + (_controller.value * 0.4);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7EE8A9).withOpacity(opacity),
            ),
          ),
        );
      },
    );
  }
}
