import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/test_result_model.dart';
import '../../services/student_service.dart';

class StudentTestResultScreen extends StatefulWidget {
  final String resultId;
  const StudentTestResultScreen({super.key, required this.resultId});

  @override
  State<StudentTestResultScreen> createState() => _StudentTestResultScreenState();
}

class _StudentTestResultScreenState extends State<StudentTestResultScreen> with SingleTickerProviderStateMixin {
  final StudentService _service = StudentService();
  late Future<TestResultModel?> _future;
  late AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _future = _service.getTestResultById(widget.resultId);
    _ringController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Test Results'),
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
      ),
      backgroundColor: isDark ? Colors.black : Colors.white,
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
          final dateStr = DateFormat.yMMMd().format(result.completedAt);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildScoreRing(isDark, pct),
                const SizedBox(height: 16),
                _buildTrophyBanner(pct),
                const SizedBox(height: 16),
                Text('${result.testTitle} • ${result.subject} • $dateStr',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                const SizedBox(height: 24),
                Text('Question Breakdown',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 8),
                ...result.questions.map((q) => _buildQuestionTile(isDark, q)),
                const SizedBox(height: 24),
                Text('Badges Earned',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: result.badges
                      .map((b) => _badgeChip(b))
                      .toList(),
                ),
                const SizedBox(height: 24),
                Text('SWOT Summary',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                const SizedBox(height: 12),
                _buildSwotGrid(isDark, result.swot),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(isDark),
    );
  }

  Widget _buildScoreRing(bool isDark, double percentage) {
    return Center(
      child: SizedBox(
        width: 180,
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: 1,
              valueColor: AlwaysStoppedAnimation(Colors.grey.shade300),
              backgroundColor: Colors.transparent,
              strokeWidth: 10,
            ),
            AnimatedBuilder(
              animation: _ringController,
              builder: (context, _) {
                return CircularProgressIndicator(
                  value: _ringController.value * (percentage / 100),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                  backgroundColor: Colors.transparent,
                  strokeWidth: 10,
                );
              },
            ),
            Center(
              child: Text(
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTrophyBanner(double percentage) {
    if (percentage < 75) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDD5),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: Color(0xFFFFF3C4), blurRadius: 20, spreadRadius: 5),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF2800D)]),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(12),
            child: const Icon(Icons.emoji_events, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(width: 12),
        const Text('Top Scorer!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF97316))),
      ],
    );
  }

  Widget _buildQuestionTile(bool isDark, QuestionResult q) {
    final icon = q.isCorrect ? Icons.check_circle : Icons.cancel;
    final iconColor = q.isCorrect ? Colors.green : Colors.red;
    return Card(
      color: isDark ? Colors.grey.shade900 : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200)),
      child: ExpansionTile(
        initiallyExpanded: q.index == 1,
        leading: Icon(icon, color: iconColor),
        title: Text(q.questionTitle, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _kvRow(isDark, 'Your Answer', q.yourAnswer),
          _kvRow(isDark, 'Correct Answer', q.correctAnswer),
          _kvRow(isDark, 'Teacher Notes', q.notes),
        ],
      ),
    );
  }

  Widget _kvRow(bool isDark, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$k: ', style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black)),
            TextSpan(text: v, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _badgeChip(String label) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF2800D)]),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x33F59E0B), blurRadius: 8, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSwotGrid(bool isDark, SwotSummary swot) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.8),
      children: [
        _swotCell(isDark, 'Strengths', swot.strengths, Colors.green),
        _swotCell(isDark, 'Weaknesses', swot.weaknesses, Colors.red),
        _swotCell(isDark, 'Opportunities', swot.opportunities, Colors.blue),
        _swotCell(isDark, 'Threats', swot.threats, Colors.amber.shade700),
      ],
    );
  }

  Widget _swotCell(bool isDark, String title, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: const [
          _NavItem(icon: Icons.home, label: 'Home', selected: false),
          _NavItem(icon: Icons.description, label: 'Tests', selected: true),
          _NavItem(icon: Icons.emoji_events, label: 'Rewards', selected: false),
          _NavItem(icon: Icons.leaderboard, label: 'Leaderboard', selected: false),
          _NavItem(icon: Icons.person, label: 'Profile', selected: false),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  const _NavItem({required this.icon, required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFF97316) : Colors.grey;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
