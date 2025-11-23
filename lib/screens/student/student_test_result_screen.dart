import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/test_result_model.dart';
import '../../services/student_service.dart';
import '../../widgets/student_bottom_nav.dart';

class StudentTestResultScreen extends StatefulWidget {
  final String resultId;
  const StudentTestResultScreen({super.key, required this.resultId});

  @override
  State<StudentTestResultScreen> createState() =>
      _StudentTestResultScreenState();
}

class _StudentTestResultScreenState extends State<StudentTestResultScreen>
    with SingleTickerProviderStateMixin {
  final StudentService _service = StudentService();
  late Future<TestResultModel?> _future;
  late AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _future = _service.getTestResultById(widget.resultId);
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  // Build a unified list of QuestionResult from either legacy questions or new answers
  List<QuestionResult> _buildQuestionResults(TestResultModel result) {
    if (result.questions != null && result.questions!.isNotEmpty) {
      return result.questions!;
    }

    final ans = result.answers;
    final List<QuestionResult> out = [];
    for (int i = 0; i < ans.length; i++) {
      final a = ans[i];
      final questionText = (a['questionText'] ?? 'Question ${i + 1}')
          .toString();
      final userAnswer = (a['userAnswer'] ?? '').toString();
      final correctAnswer = (a['correctAnswer'] ?? '').toString();
      final isCorrect = (a['isCorrect'] ?? false) == true;
      out.add(
        QuestionResult(
          index: i + 1,
          questionTitle: questionText.isNotEmpty
              ? questionText
              : 'Question ${i + 1}',
          yourAnswer: userAnswer,
          correctAnswer: correctAnswer,
          notes: '',
          isCorrect: isCorrect,
        ),
      );
    }
    return out;
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFF7F3EF),
      bottomNavigationBar: const StudentBottomNav(currentIndex: 1),
      body: FutureBuilder<TestResultModel?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Result not found'));
          }
          final result = snapshot.data!;
          // Compute percentage safely with fallbacks to new fields
          final double pct = (() {
            if (result.percentage != null) {
              final p = result.percentage!;
              return p.clamp(0, 100).toDouble();
            }
            // Fallback: compute from correct/total if available
            final totalQ = result.totalQuestions;
            final correct = result.correctAnswers;
            if (totalQ > 0) {
              return ((correct / totalQ) * 100).clamp(0.0, 100.0);
            }
            // Last fallback: use score field (already a percentage in new model)
            return (result.score).clamp(0.0, 100.0);
          })();

          return Column(
            children: [
              // Header
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: Theme.of(context).iconTheme.color,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Test Results',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildScoreRing(pct),
                      const SizedBox(height: 24),
                      if (pct >= 75) _buildTrophyBanner(),
                      const SizedBox(height: 24),
                      // Question Breakdown (supports legacy and new formats)
                      if ((result.questions != null &&
                              result.questions!.isNotEmpty) ||
                          result.answers.isNotEmpty) ...[
                        Text(
                          'Question Breakdown',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ..._buildQuestionResults(
                          result,
                        ).map((q) => _buildQuestionTile(q)),
                      ],
                      const SizedBox(height: 24),
                      // Badges (optional)
                      if (result.badges != null &&
                          result.badges!.isNotEmpty) ...[
                        Text(
                          'Badges Earned',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: result.badges!
                              .map((b) => _badgeChip(b))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // SWOT (optional)
                      if (result.swot != null) ...[
                        Text(
                          'SWOT Summary',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildSwotGrid(result.swot!),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScoreRing(double percentage) {
    return Center(
      child: SizedBox(
        width: 192,
        height: 192,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background gray ring
            CustomPaint(
              painter: _RingPainter(
                progress: 1.0,
                color: Colors.grey.shade300,
                strokeWidth: 10,
              ),
            ),
            // Animated orange gradient ring
            AnimatedBuilder(
              animation: _ringController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _RingPainter(
                    progress: _ringController.value * (percentage / 100),
                    color: const Color(0xFFF97316),
                    strokeWidth: 10,
                  ),
                );
              },
            ),
            Center(
              child: Text(
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrophyBanner() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: Color(0xFFFBBF24),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFB923C), Color(0xFFF97316)],
                ),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.emoji_events,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Top Scorer!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF97316),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionTile(QuestionResult q) {
    final icon = q.isCorrect ? Icons.check_circle : Icons.cancel;
    final iconColor = q.isCorrect ? Colors.green : Colors.red;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF374151) : Colors.grey.shade300,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Theme(
          data: ThemeData(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: q.index == 1,
            leading: Icon(icon, color: iconColor, size: 24),
            title: Text(
              q.questionTitle,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: isDark ? Colors.white70 : Colors.black54,
            collapsedIconColor: isDark ? Colors.white70 : Colors.black54,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Container(
                width: double.infinity,
                height: 1,
                color: isDark ? const Color(0xFF374151) : Colors.grey.shade200,
              ),
              const SizedBox(height: 12),
              _kvRow('Your Answer', q.yourAnswer),
              const SizedBox(height: 8),
              _kvRow('Correct Answer', q.correctAnswer),
              const SizedBox(height: 8),
              _kvRow('Teacher Notes', q.notes),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            TextSpan(
              text: v,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeChip(String label) {
    IconData icon = Icons.workspace_premium;
    if (label.toLowerCase().contains('math')) {
      icon = Icons.star;
    } else if (label.toLowerCase().contains('solver') ||
        label.toLowerCase().contains('problem')) {
      icon = Icons.psychology;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFB923C), Color(0xFFF97316)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33F59E0B),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwotGrid(SwotSummary swot) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _swotCell('Strengths', swot.strengths, Colors.green),
        _swotCell('Weaknesses', swot.weaknesses, Colors.red),
        _swotCell('Opportunities', swot.opportunities, Colors.blue),
        _swotCell('Threats', swot.threats, Colors.amber.shade700),
      ],
    );
  }

  Widget _swotCell(String title, String value, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : Colors.grey.shade300,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // Bottom nav is centralized in StudentBottomNav widget.
}

// Custom painter for circular progress ring
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// _NavItem removed in favor of shared StudentBottomNav.
