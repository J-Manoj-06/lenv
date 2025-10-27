import 'dart:math' as math;
import 'package:flutter/material.dart';
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

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
          final pct = (result.percentage).clamp(0, 100).toDouble();

          return Stack(
            children: [
              Column(
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
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.black87,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Text(
                            'Test Results',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
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
                          const Text(
                            'Question Breakdown',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...result.questions
                              .map((q) => _buildQuestionTile(q))
                              .toList(),
                          const SizedBox(height: 24),
                          const Text(
                            'Badges Earned',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: result.badges
                                .map((b) => _badgeChip(b))
                                .toList(),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'SWOT Summary',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSwotGrid(result.swot),
                          const SizedBox(height: 24),
                          // Share and Review buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Share feature coming soon!',
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.share, size: 20),
                                  label: const Text(
                                    'Share',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF97316),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Review feature coming soon!',
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.rate_review, size: 20),
                                  label: const Text(
                                    'Review',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade300,
                                    foregroundColor: Colors.black87,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Bottom Navigation
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomNav(),
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
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
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
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: Colors.black54,
            collapsedIconColor: Colors.black54,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.grey.shade200,
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
    return Align(
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(color: Colors.black54),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
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
            style: const TextStyle(
              color: Colors.black87,
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

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home,
                label: 'Home',
                selected: false,
                onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/student-dashboard',
                  (route) => false,
                ),
              ),
              _NavItem(
                icon: Icons.description,
                label: 'Tests',
                selected: true,
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.emoji_events,
                label: 'Rewards',
                selected: false,
                onTap: () => Navigator.pushNamed(context, '/student-rewards'),
              ),
              _NavItem(
                icon: Icons.leaderboard,
                label: 'Leaderboard',
                selected: false,
                onTap: () =>
                    Navigator.pushNamed(context, '/student-leaderboard'),
              ),
              _NavItem(
                icon: Icons.person,
                label: 'Profile',
                selected: false,
                onTap: () => Navigator.pushNamed(context, '/student-profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFF97316) : Colors.grey.shade600;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
