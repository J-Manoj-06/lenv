import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/test_result_model.dart';
import '../../services/student_service.dart';

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
  late Future<Map<String, dynamic>> _studentFuture;
  late AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _future = _service.getTestResultById(widget.resultId);
    _studentFuture = _fetchStudentInfo();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  Future<Map<String, dynamic>> _fetchStudentInfo() async {
    final student = await _service.getCurrentStudent();
    if (student == null) return {};

    // Parse standard and section from className (e.g., "10 - A - math")
    String standard = '';
    String section = student.section ?? '';

    if (student.className?.isNotEmpty ?? false) {
      final parts = student.className!.split(' - ');
      if (parts.isNotEmpty) {
        standard = 'Grade ${parts[0].trim()}';
        if (parts.length > 1 && section.isEmpty) {
          section = parts[1].trim();
        }
      }
    }

    return {'name': student.name, 'standard': standard, 'section': section};
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
      final userAnswer = _extractAnswer(a, forCorrect: false);
      final correctAnswer = _extractAnswer(a, forCorrect: true);
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

  // Extract an answer string from multiple possible keys and formats
  String _extractAnswer(Map<String, dynamic> a, {required bool forCorrect}) {
    final keys = forCorrect
        ? [
            'correctAnswer',
            'answer',
            'correctOption',
            'correctLabel',
            'correctIndex',
            'correct_index',
            'expected',
          ]
        : [
            'userAnswer',
            'selectedAnswer',
            'selectedOption',
            'selectedLabel',
            'selected',
            'userOption',
            'userLabel',
            'userIndex',
            'selectedIndex',
            'answer',
            'studentAnswer',
            'choice',
            'response',
            'value',
          ];

    dynamic val;
    for (final k in keys) {
      if (a.containsKey(k) && a[k] != null) {
        val = a[k];
        break;
      }
    }
    if (val == null) {
    }

    // Resolve single-letter answers against options list when available
    if (forCorrect && val is String && val.trim().length == 1) {
      final opts = a['options'];
      if (opts is List && opts.isNotEmpty) {
        final letter = val.trim().toUpperCase();
        final idx = letter.codeUnitAt(0) - 65; // A -> 0
        if (idx >= 0 && idx < opts.length) {
          val = opts[idx];
        }
      }
    }

    return _stringifyAnswer(val);
  }

  String _stringifyAnswer(dynamic v) {
    if (v == null) return '—';
    if (v is List) {
      return v.map((e) => _stringifyAnswer(e)).join(', ');
    }
    if (v is Map) {
      return v.values.map((e) => _stringifyAnswer(e)).join(', ');
    }
    final s = v.toString().trim();
    return s.isEmpty ? 'No answer' : s;
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
      body: FutureBuilder<TestResultModel?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Result not found'),
                  const SizedBox(height: 16),
                  Text(
                    'Result ID: ${widget.resultId}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          final result = snapshot.data!;
          // Compute percentage safely with fallbacks to new fields
          final derivedTotal = result.totalQuestions > 0
              ? result.totalQuestions
              : (result.answers.isNotEmpty ? result.answers.length : 0);
          final derivedCorrect = (result.correctAnswers > 0 ||
                  result.answers.isEmpty)
              ? result.correctAnswers
              : result.answers
                  .where((a) => (a['isCorrect'] ?? false) == true)
                  .length;

          final double pct = (() {
            if (result.percentage != null) {
              final p = result.percentage!;
              return p.clamp(0, 100).toDouble();
            }
            // Fallback: compute from correct/total if available
            final totalQ = derivedTotal;
            final correct = derivedCorrect;
            if (totalQ > 0) {
              final computed = ((correct / totalQ) * 100).clamp(0.0, 100.0);
              return computed;
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
                          Icons.arrow_back_ios_new,
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
                      const SizedBox(height: 16),
                      _buildStudentInfo(),
                      const SizedBox(height: 24),
                      if (pct >= 75) _buildTrophyBanner(),
                      const SizedBox(height: 24),
                      // Gate detailed answers until results are published or after due time
                      FutureBuilder<_PublishGate>(
                        future: _fetchPublishGate(result.testId),
                        builder: (context, gateSnap) {
                          final gate = gateSnap.data;
                          final canShow = gate?.canShow ?? true;
                          if (!canShow) {
                            return _lockedUntilCard(gate!.endDate, isDark);
                          }

                          if ((result.questions != null &&
                                  result.questions!.isNotEmpty) ||
                              result.answers.isNotEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Question Breakdown',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                ..._buildQuestionResults(result)
                                    .map((q) => _buildQuestionTile(q)),
                              ],
                            );
                          }

                          return _noDetailsCard(isDark);
                        },
                      ),
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

  // --- Result gating helpers ---
  Future<_PublishGate> _fetchPublishGate(String testId) async {
    DateTime? endDate;
    bool resultsPublished = false;

    try {
      final db = FirebaseFirestore.instance;
      // Try scheduledTests first (AI tests)
      final sched = await db.collection('scheduledTests').doc(testId).get();
      if (sched.exists) {
        final data = sched.data() as Map<String, dynamic>;
        resultsPublished = (data['resultsPublished'] as bool?) ?? false;
        if (data['endDate'] is Timestamp) {
          endDate = (data['endDate'] as Timestamp).toDate();
        } else if (data['date'] is String) {
          // Compute from date + startTime + duration (fallback)
          try {
            final dateStr = data['date'] as String;
            final startTimeStr = (data['startTime'] as String?) ?? '00:00';
            final duration = (data['duration'] as num?)?.toInt() ?? 60;
            final start = DateTime.parse('$dateStr $startTimeStr');
            endDate = start.add(Duration(minutes: duration));
          } catch (_) {}
        }
      } else {
        // Fallback to tests collection (manually created tests)
        final t = await db.collection('tests').doc(testId).get();
        if (t.exists) {
          final data = t.data() as Map<String, dynamic>;
          resultsPublished = (data['resultsPublished'] as bool?) ?? false;
          if (data['endDate'] is Timestamp) {
            endDate = (data['endDate'] as Timestamp).toDate();
          }
        }
      }
    } catch (_) {}

    final now = DateTime.now();
    final canShow = resultsPublished || (endDate != null && now.isAfter(endDate));
    return _PublishGate(canShow: canShow, endDate: endDate);
  }

  Widget _lockedUntilCard(DateTime? endDate, bool isDark) {
    final dateText = endDate != null ? DateFormat('MMM d, yyyy h:mm a').format(endDate) : 'the due time';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, color: Color(0xFFF97316)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Results locked until $dateText',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Answer details will be visible after the test due time.',
                  style:
                      TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noDetailsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.info_outline,
            size: 48,
            color: isDark ? Colors.white70 : Colors.grey,
          ),
          const SizedBox(height: 12),
          Text(
            'Question details not available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This test result does not contain detailed answer information.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.grey),
          ),
        ],
      ),
    );
  }

  

  Widget _buildStudentInfo() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _studentFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final info = snapshot.data!;
        final name = info['name'] ?? '';
        final standard = info['standard'] ?? '';
        final section = info['section'] ?? '';

        return Center(
          child: Column(
            children: [
              if (name.isNotEmpty)
                Text(
                  name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (standard.isNotEmpty) ...[
                    Text(
                      standard,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (section.isNotEmpty) ...[
                      Text(
                        ' - ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFFF97316).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'Section $section',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFFF97316),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        );
      },
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

class _PublishGate {
  final bool canShow;
  final DateTime? endDate;
  _PublishGate({required this.canShow, this.endDate});
}
