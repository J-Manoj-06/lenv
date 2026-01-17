import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../services/insights/insights_repository.dart';
import '../../../../models/insights/teacher_stats_model.dart';

class TeacherInsightsDetailsPage extends StatefulWidget {
  const TeacherInsightsDetailsPage({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.schoolCode,
    required this.range,
  });

  final String teacherId;
  final String teacherName;
  final String schoolCode;
  final String range;

  @override
  State<TeacherInsightsDetailsPage> createState() =>
      _TeacherInsightsDetailsPageState();
}

class _TeacherInsightsDetailsPageState
    extends State<TeacherInsightsDetailsPage> {
  final InsightsRepository _repository = InsightsRepository();

  TeacherTestsDetail? _testsDetail;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final detail = await _repository.getTeacherTestsDetail(
        schoolCode: widget.schoolCode,
        range: widget.range,
        teacherId: widget.teacherId,
      );

      if (mounted) {
        setState(() {
          _testsDetail = detail;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading teacher details: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.teacherName,
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Test Details',
              style: TextStyle(
                color: subtitleColor,
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: const Color(0xFF146D7A)),
            )
          : _testsDetail == null
          ? _buildEmptyState(subtitleColor)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stats Summary Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF146D7A), Color(0xFF0E5A66)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF146D7A).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Tests Conducted',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_testsDetail!.recentTests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'in ${widget.range}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Recent Tests Header
                Text(
                  'Recent Tests',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),

                // Test Cards
                if (_testsDetail!.recentTests.isEmpty)
                  _buildNoTestsState(subtitleColor)
                else
                  ..._testsDetail!.recentTests.map((test) {
                    return _buildTestCard(
                      test,
                      cardColor,
                      textColor,
                      subtitleColor,
                      isDark,
                    );
                  }),
              ],
            ),
    );
  }

  Widget _buildTestCard(
    TestSummary test,
    Color cardColor,
    Color textColor,
    Color subtitleColor,
    bool isDark,
  ) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final scoreColor = test.avgScore >= 75
        ? const Color(0xFF10B981)
        : test.avgScore >= 50
        ? const Color(0xFFF59E0B)
        : const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  test.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${test.avgScore.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Icon(Icons.class_, size: 16, color: subtitleColor),
              const SizedBox(width: 6),
              Text(
                'Standard ${test.standard}-${test.section}',
                style: TextStyle(color: subtitleColor, fontSize: 13),
              ),
              const Spacer(),
              Icon(Icons.calendar_today, size: 16, color: subtitleColor),
              const SizedBox(width: 6),
              Text(
                dateFormat.format(test.date),
                style: TextStyle(color: subtitleColor, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color subtitleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: subtitleColor),
          const SizedBox(height: 16),
          Text(
            'No test details available',
            style: TextStyle(color: subtitleColor, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTestsState(Color subtitleColor) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.assignment_outlined, size: 48, color: subtitleColor),
            const SizedBox(height: 12),
            Text(
              'No tests conducted in this period',
              style: TextStyle(color: subtitleColor, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
