import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/performance_model.dart';
import '../../services/firestore_service.dart';

class StudentPerformanceScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentClass;
  final String imageUrl;
  final int averageScore; // fallback if no performance yet

  const StudentPerformanceScreen({
    Key? key,
    required this.studentId,
    required this.studentName,
    required this.studentClass,
    required this.imageUrl,
    required this.averageScore,
  }) : super(key: key);

  @override
  State<StudentPerformanceScreen> createState() => _StudentPerformanceScreenState();
}

class _StudentPerformanceScreenState extends State<StudentPerformanceScreen> {
  final _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: StreamBuilder<PerformanceModel?>(
              stream: _firestoreService.getPerformanceStream(widget.studentId),
              builder: (context, snapshot) {
                final perf = snapshot.data;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildPerformanceTrend(perf),
                      const SizedBox(height: 24),
                      _buildRecentTests(perf),
                      const SizedBox(height: 24),
                      _buildAreasForImprovement(perf),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F8).withOpacity(0.8),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                    color: const Color(0xFF1F2937),
                  ),
                  const Expanded(
                    child: Text(
                      'Student Performance',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.network(
                      widget.imageUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person,
                            size: 32,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.studentName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.studentClass,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceTrend(PerformanceModel? perf) {
    final submissions = (perf?.submissions ?? [])
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final lastSix = submissions.length <= 6
        ? submissions
        : submissions.sublist(submissions.length - 6);
    final avg = perf?.averageScore ?? widget.averageScore.toDouble();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Performance Trend',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Average Score',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${avg.round()}%',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(width: 12),
              _buildDeltaPill(lastSix),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            lastSix.isEmpty ? 'No trend yet' : 'vs. last ${lastSix.length} tests',
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 24),
          _buildChart(lastSix),
          const SizedBox(height: 8),
          if (lastSix.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: lastSix
                  .map((e) => Text(
                        _shortDate(e.submittedAt),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      ))
                  .toList(),
            ),
          if (lastSix.isEmpty)
            const Center(
              child: Text('No chart data yet', style: TextStyle(color: Color(0xFF6B7280))),
            ),
        ],
      ),
    );
  }

  Widget _buildChart(List<TestSubmission> points) {
    if (points.isEmpty) return const SizedBox(height: 160);
    final spots = points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.percentage))
        .toList();
    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: const Color(0xFF6366F1),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.2),
                    const Color(0xFF6366F1).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTests(PerformanceModel? perf) {
    final submissions = List<TestSubmission>.from(perf?.submissions ?? []);
    submissions.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Recent Tests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          if (submissions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'No tests yet',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            )
          else ...[
            for (int i = 0; i < submissions.length && i < 5; i++) ...[
              _buildTestItem(
                submissions[i].testTitle,
                _longDate(submissions[i].submittedAt),
                submissions[i].percentage.round(),
              ),
              if (i < submissions.length - 1 && i < 4)
                Divider(height: 1, color: Colors.grey[100]),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTestItem(
    String title,
    String date,
    int score,
  ) {
    Color badgeBgColor;
    Color badgeTextColor;

    if (score >= 85) {
      badgeBgColor = const Color(0xFFD1FAE5);
      badgeTextColor = const Color(0xFF065F46);
    } else if (score >= 70) {
      badgeBgColor = const Color(0xFF6366F1).withOpacity(0.2);
      badgeTextColor = const Color(0xFF6366F1);
    } else {
      badgeBgColor = const Color(0xFFFEE2E2);
      badgeTextColor = const Color(0xFF991B1B);
    }

    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$score%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: badgeTextColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.grey[400]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAreasForImprovement(PerformanceModel? perf) {
    final hasData = (perf?.submissions ?? []).isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Areas for Improvement',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Text('No insights yet', style: TextStyle(color: Colors.grey[600]))
          else
            Text('Insights coming soon', style: TextStyle(color: Colors.grey[600]))
        ],
      ),
    );
  }

  // Helpers
  String _shortDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _longDate(DateTime dt) {
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _buildDeltaPill(List<TestSubmission> lastSix) {
    if (lastSix.length < 2) return const SizedBox.shrink();
    final first = lastSix.first.percentage;
    final last = lastSix.last.percentage;
    final delta = last - first;
    final isUp = delta >= 0;
    final color = isUp ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = isUp ? '+' : '';
    return Row(
      children: [
        Icon(isUp ? Icons.trending_up : Icons.trending_down, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$sign${delta.toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: color),
        ),
      ],
    );
  }
}
