import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/performance_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/teacher_bottom_nav.dart';

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
  State<StudentPerformanceScreen> createState() =>
      _StudentPerformanceScreenState();
}

class _StudentPerformanceScreenState extends State<StudentPerformanceScreen> {
  final _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          _buildHeader(context, theme),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: StreamBuilder<PerformanceModel?>(
                  stream: _firestoreService.getPerformanceStream(
                    widget.studentId,
                  ),
                  builder: (context, snapshot) {
                    final perf = snapshot.data;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildPerformanceTrend(theme, perf),
                          const SizedBox(height: 24),
                          _buildRecentTests(theme, perf),
                          const SizedBox(height: 24),
                          _buildAreasForImprovement(theme, perf),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const TeacherBottomNav(selectedIndex: 1),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.8),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                        color: theme.iconTheme.color,
                      ),
                      Expanded(
                        child: Text(
                          'Student Performance',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
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
                                color: theme.colorScheme.surfaceVariant,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person,
                                size: 32,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
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
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.studentClass,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 16,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
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
        ),
      ),
    );
  }

  Widget _buildPerformanceTrend(ThemeData theme, PerformanceModel? perf) {
    final submissions = (perf?.submissions ?? [])
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final lastSix = submissions.length <= 6
        ? submissions
        : submissions.sublist(submissions.length - 6);
    final avg = perf?.averageScore ?? widget.averageScore.toDouble();
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
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
          Text(
            'Performance Trend',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Average Score',
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${avg.round()}%',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              _buildDeltaPill(lastSix),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            lastSix.isEmpty
                ? 'No trend yet'
                : 'vs. last ${lastSix.length} tests',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          _buildChart(theme, lastSix),
          const SizedBox(height: 8),
          if (lastSix.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: lastSix
                  .map(
                    (e) => Text(
                      _shortDate(e.submittedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (lastSix.isEmpty)
            Center(
              child: Text(
                'No chart data yet',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChart(ThemeData theme, List<TestSubmission> points) {
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
              color: theme.colorScheme.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.2),
                    theme.colorScheme.primary.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTests(ThemeData theme, PerformanceModel? perf) {
    final submissions = List<TestSubmission>.from(perf?.submissions ?? []);
    submissions.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Recent Tests',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (submissions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'No tests yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            )
          else ...[
            for (int i = 0; i < submissions.length && i < 5; i++) ...[
              _buildTestItem(
                theme,
                submissions[i].testTitle,
                _longDate(submissions[i].submittedAt),
                submissions[i].percentage.round(),
              ),
              if (i < submissions.length - 1 && i < 4)
                Divider(height: 1, color: theme.dividerColor),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTestItem(ThemeData theme, String title, String date, int score) {
    Color badgeBgColor;
    Color badgeTextColor;

    if (score >= 85) {
      badgeBgColor = const Color(0xFFD1FAE5);
      badgeTextColor = const Color(0xFF065F46);
    } else if (score >= 70) {
      badgeBgColor = theme.colorScheme.primary.withOpacity(0.2);
      badgeTextColor = theme.colorScheme.primary;
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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
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
                Icon(
                  Icons.chevron_right,
                  color: theme.iconTheme.color?.withOpacity(0.4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAreasForImprovement(ThemeData theme, PerformanceModel? perf) {
    final hasData = (perf?.submissions ?? []).isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
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
          Text(
            'Areas for Improvement',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Text(
              'No insights yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            )
          else
            Text(
              'Insights coming soon',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
        ],
      ),
    );
  }

  // Helpers
  String _shortDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _longDate(DateTime dt) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
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
        Icon(
          isUp ? Icons.trending_up : Icons.trending_down,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$sign${delta.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
