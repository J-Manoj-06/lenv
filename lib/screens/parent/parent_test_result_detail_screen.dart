import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/test_result_model.dart';
import '../../services/parent_service.dart';

class ParentTestResultDetailScreen extends StatefulWidget {
  final TestResultModel test;
  const ParentTestResultDetailScreen({super.key, required this.test});

  @override
  State<ParentTestResultDetailScreen> createState() =>
      _ParentTestResultDetailScreenState();
}

class _ParentTestResultDetailScreenState
    extends State<ParentTestResultDetailScreen>
    with SingleTickerProviderStateMixin {
  static const Color parentGreen = Color(0xFF14A670);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  late final AnimationController _ringController;
  final ParentService _service = ParentService();
  double? _classAverage;
  double? _highestScore;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _loadClassAverage();
    _loadHighestScore();
  }

  Future<void> _loadClassAverage() async {
    final avg = await _service.getClassAverageForTest(widget.test.testId);
    if (mounted) setState(() => _classAverage = avg);
  }

  Future<void> _loadHighestScore() async {
    final highest = await _service.getHighestScoreForTest(widget.test.testId);
    if (mounted) setState(() => _highestScore = highest);
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = widget.test;
    final pct = t.totalQuestions > 0
        ? (t.correctAnswers / t.totalQuestions * 100).clamp(0, 100)
        : t.score.clamp(0, 100);
    final dateStr = DateFormat('MMM dd, yyyy').format(t.completedAt);
    final passed = pct >= 40; // simple threshold, adjust if you have passMark

    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      appBar: AppBar(
        backgroundColor: isDark ? backgroundDark : backgroundLight,
        foregroundColor: isDark ? Colors.white : textPrimary,
        elevation: 0,
        title: Text(
          '${t.subject} - ${t.testTitle}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          80,
        ), // Added bottom padding for navigation bar
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Performance Overview Section
            _buildPerformanceOverview(isDark, pct.toDouble(), dateStr, passed),

            const SizedBox(height: 16),

            // Tabs (only Question Analysis for now)
            Text(
              'Question Analysis',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            _buildQuestionAccordion(isDark, widget.test),

            const SizedBox(height: 16),
            Text(
              'Comparison',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            _buildComparison(isDark, pct.toDouble(), _classAverage),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionAccordion(bool isDark, TestResultModel t) {
    final List<QuestionResult> questions = _buildQuestionResults(t);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A2F) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(
            'Detailed Question Analysis',
            style: TextStyle(
              color: isDark ? Colors.white : textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          iconColor: isDark ? Colors.white : textPrimary,
          collapsedIconColor: isDark ? Colors.white70 : Colors.black54,
          children: [
            const SizedBox(height: 8),
            for (final q in questions) ...[
              _questionCard(isDark, q),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  List<QuestionResult> _buildQuestionResults(TestResultModel t) {
    if (t.questions != null && t.questions!.isNotEmpty) return t.questions!;
    final List<QuestionResult> out = [];
    for (int i = 0; i < t.answers.length; i++) {
      final a = t.answers[i];
      out.add(
        QuestionResult(
          index: i + 1,
          questionTitle: (a['questionText'] ?? 'Question ${i + 1}').toString(),
          yourAnswer: (a['userAnswer'] ?? '').toString(),
          correctAnswer: (a['correctAnswer'] ?? '').toString(),
          notes: (a['notes'] ?? '').toString(),
          isCorrect: (a['isCorrect'] ?? false) == true,
        ),
      );
    }
    return out;
  }

  Widget _questionCard(bool isDark, QuestionResult q) {
    final icon = q.isCorrect ? Icons.check : Icons.close;
    final color = q.isCorrect ? Colors.green : Colors.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23253A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (q.isCorrect ? Colors.green : Colors.red).withOpacity(
                    0.12,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${q.index}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: q.isCorrect ? Colors.green : Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q.questionTitle,
                  style: TextStyle(
                    color: isDark ? Colors.white : textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 4),
                  Text(
                    q.isCorrect ? '+2' : '0',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _kv(
            isDark,
            'Your Answer',
            q.yourAnswer,
            color: q.isCorrect ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 4),
          _kv(isDark, 'Correct Answer', q.correctAnswer, color: Colors.green),
        ],
      ),
    );
  }

  Widget _kv(bool isDark, String k, String v, {Color? color}) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$k: ',
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: v,
            style: TextStyle(
              color: color ?? (isDark ? Colors.white : textPrimary),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparison(bool isDark, double yourPct, double? classAvg) {
    // If classAvg is null, show loading or default to 0
    final avg = (classAvg ?? 0.0).clamp(0, 100).toDouble();
    final yourH = 120.0 * (yourPct / 100);
    final avgH = 120.0 * (avg / 100);
    final isLoading = classAvg == null;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A2F) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${yourPct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: isDark ? Colors.white : textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: yourH,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: parentGreen,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your Score',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  isLoading ? '--' : '${avg.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: isDark ? Colors.white : textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: avgH,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : const Color(0xFF324667),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Class Average',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceOverview(
    bool isDark,
    double percentage,
    String dateStr,
    bool passed,
  ) {
    final cardColor = isDark ? const Color(0xFF1E1A2F) : cardBg;
    final titleColor = isDark ? Colors.white : textPrimary;
    final subColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final t = widget.test;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Overview',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 180,
              width: 180,
              child: CustomPaint(
                painter: _GaugePainter(percentage: percentage),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Your Score',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Student info and stats
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.subject,
                      style: TextStyle(color: subColor, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.testTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Passed status and date
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (passed ? Colors.green : Colors.red).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      passed ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: passed ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      passed ? 'Passed' : 'Failed',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: passed ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              _iconText(isDark, Icons.calendar_today, dateStr),
            ],
          ),
          const SizedBox(height: 16),
          // Highest score info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: parentGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: parentGreen.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.emoji_events,
                    size: 20,
                    color: parentGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Highest Score',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _highestScore != null
                            ? '${_highestScore!.toStringAsFixed(0)}%'
                            : 'Loading...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  t.studentName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: parentGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconText(bool isDark, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: isDark ? Colors.grey[300] : textPrimary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage; // 0..100

  _GaugePainter({required this.percentage});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 14.0;

    // Background arc (semi-donut ~270°)
    final bgPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );
    const startAngle = math.pi * 0.75; // bottom-left
    const totalSweep = math.pi * 1.5; // 270 degrees

    canvas.drawArc(rect, startAngle, totalSweep, false, bgPaint);

    // Progress arc with gradient red->green
    final progressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.red,
          Colors.orange,
          Colors.yellow,
          Colors.lightGreen,
          Colors.green,
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(rect)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final clamped = percentage.clamp(0.0, 100.0);
    final sweep = (clamped / 100) * totalSweep;
    canvas.drawArc(rect, startAngle, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
