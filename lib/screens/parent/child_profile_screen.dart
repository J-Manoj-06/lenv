import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/parent_provider.dart';
import '../../models/student_model.dart';

class ChildProfileScreen extends StatelessWidget {
  const ChildProfileScreen({super.key});

  // Parent green theme colors
  static const Color parentGreen = Color(0xFF14A670);
  static const Color parentGreenLight = Color(0xFF0F8A5A);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parentProvider = Provider.of<ParentProvider>(context);
    final child = parentProvider.selectedChild;

    if (child == null) {
      return Scaffold(
        backgroundColor: isDark ? backgroundDark : backgroundLight,
        appBar: AppBar(
          backgroundColor: isDark ? backgroundDark : backgroundLight,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.chevron_left,
              size: 28,
              color: isDark ? Colors.white : textPrimary,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Child Profile',
            style: TextStyle(
              color: isDark ? Colors.white : textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(child: Text('No child selected')),
      );
    }

    final performanceStats = parentProvider.performanceStats;
    final attendance = parentProvider.attendance;
    final testsAttended =
        (performanceStats['completedTests'] as int?) ??
        (performanceStats['totalTests'] as int?) ??
        parentProvider.testResults.length;

    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      appBar: AppBar(
        backgroundColor: isDark ? backgroundDark : backgroundLight,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            size: 28,
            color: isDark ? Colors.white : textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Child Profile',
          style: TextStyle(
            color: isDark ? Colors.white : textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header Card
            _buildProfileHeader(isDark, child),
            const SizedBox(height: 16),

            // Quick Stats
            _buildQuickStats(
              isDark: isDark,
              rewardPoints: child.rewardPoints,
              testsAttended: testsAttended,
            ),
            const SizedBox(height: 16),

            // Academic Overview Card
            _buildAcademicOverview(
              isDark,
              performanceStats,
              parentProvider.testResults,
            ),
            const SizedBox(height: 16),

            // Attendance Overview Card
            _buildAttendanceOverview(
              isDark,
              attendance,
              parentProvider.attendanceBreakdown,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(bool isDark, StudentModel child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Picture and Name
          Row(
            children: [
              // Avatar
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: parentGreen.withOpacity(0.1),
                ),
                child: child.photoUrl != null
                    ? ClipOval(
                        child: Image.network(
                          child.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.person,
                              size: 40,
                              color: parentGreen,
                            );
                          },
                        ),
                      )
                    : Icon(Icons.person, size: 40, color: parentGreen),
              ),
              const SizedBox(width: 16),

              // Name and Class
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${child.className ?? "N/A"}${child.section != null ? ", Section ${child.section}" : ""}',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required bool isDark,
    required String label1,
    required String value1,
    required String label2,
    required String value2,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label1,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (label2.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label2,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickStats({
    required bool isDark,
    required int rewardPoints,
    required int testsAttended,
  }) {
    final cardBackground = isDark ? const Color(0xFF1F1F1F) : cardBg;

    return Row(
      children: [
        Expanded(
          child: _buildQuickStatCard(
            isDark: isDark,
            title: 'Reward Points',
            value: rewardPoints.toString(),
            icon: Icons.stars_rounded,
            glowColor: const Color(0xFFFFB703),
            iconBackground: const Color(0xFFFFB703),
            backgroundColor: cardBackground,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickStatCard(
            isDark: isDark,
            title: 'Tests Attended',
            value: testsAttended.toString(),
            icon: Icons.fact_check_rounded,
            glowColor: parentGreen,
            iconBackground: parentGreen,
            backgroundColor: cardBackground,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatCard({
    required bool isDark,
    required String title,
    required String value,
    required IconData icon,
    required Color glowColor,
    required Color iconBackground,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : glowColor.withOpacity(0.16),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(isDark ? 0.10 : 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconBackground.withOpacity(0.18),
            ),
            child: Icon(icon, size: 20, color: iconBackground),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : textPrimary,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicOverview(
    bool isDark,
    Map<String, dynamic> performanceStats,
    List<dynamic> testResults,
  ) {
    final averageScore =
        (performanceStats['averageScore'] as num?)?.toDouble() ?? 0.0;
    final highestScore =
        (performanceStats['highestScore'] as num?)?.toDouble() ?? 0.0;
    final totalTests = (performanceStats['totalTests'] as int?) ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Academic Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: parentGreen,
            ),
          ),
          const SizedBox(height: 16),

          // Stats Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall Marks',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${averageScore.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Latest Test',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${highestScore.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Academic Progress Chart
          if (testResults.isNotEmpty)
            Container(
              height: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test Scores',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (int i = 0; i < testResults.length && i < 10; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: _buildTestBar(
                                isDark,
                                testResults[i].score,
                                testResults[i].testTitle,
                                i,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalTests ${totalTests == 1 ? 'test' : 'tests'} completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDark
                    ? Colors.grey[800]!.withOpacity(0.3)
                    : Colors.grey[100],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bar_chart,
                      size: 40,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No test data available',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttendanceOverview(
    bool isDark,
    double attendance,
    Map<String, int> breakdown,
  ) {
    // Use actual breakdown from Firestore
    final presentDays = breakdown['present'] ?? 0;
    final absentDays = breakdown['absent'] ?? 0;
    final totalDays = breakdown['total'] ?? (presentDays + absentDays);
    final attendancePercent = attendance > 0
        ? attendance
        : (totalDays > 0 ? (presentDays / totalDays * 100) : 0.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: parentGreen,
            ),
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Donut Chart
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    startAngle: 0,
                    endAngle: 3.14 * 2,
                    colors: [Colors.green, Colors.green, Colors.red],
                    stops: [0, attendancePercent / 100, 1.0],
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1F1F1F) : cardBg,
                    ),
                    child: Center(
                      child: Text(
                        '${attendancePercent.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),

              // Legend
              Expanded(
                child: Column(
                  children: [
                    _buildAttendanceLegendItem(
                      isDark: isDark,
                      color: Colors.green,
                      label: 'Present',
                      value: '$presentDays Days',
                    ),
                    const SizedBox(height: 12),
                    _buildAttendanceLegendItem(
                      isDark: isDark,
                      color: Colors.red,
                      label: 'Absent',
                      value: '$absentDays Days',
                    ),
                    const SizedBox(height: 12),
                    _buildAttendanceLegendItem(
                      isDark: isDark,
                      color: Colors.blue,
                      label: 'Yearly',
                      value: '${attendancePercent.toStringAsFixed(0)}%',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTestBar(bool isDark, double score, String testTitle, int index) {
    final barHeight = (score / 100) * 120; // Max height 120
    final barColor = score >= 75
        ? Colors.green
        : score >= 50
        ? Colors.orange
        : Colors.red;

    return Tooltip(
      message: '$testTitle: ${score.toStringAsFixed(1)}%',
      child: Container(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          height: barHeight,
          decoration: BoxDecoration(
            color: barColor.withOpacity(0.7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [barColor, barColor.withOpacity(0.6)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceLegendItem({
    required bool isDark,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
