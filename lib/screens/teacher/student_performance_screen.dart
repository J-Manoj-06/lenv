import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/performance_model.dart';
import '../../services/firestore_service.dart';
import '../../services/messaging_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/whatsapp_chat_service.dart';

class StudentPerformanceScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentClass;
  final String imageUrl;
  final int averageScore; // fallback if no performance yet

  const StudentPerformanceScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.studentClass,
    required this.imageUrl,
    required this.averageScore,
  });

  @override
  State<StudentPerformanceScreen> createState() =>
      _StudentPerformanceScreenState();
}

class _StudentPerformanceScreenState extends State<StudentPerformanceScreen>
    with SingleTickerProviderStateMixin {
  // Brand + dark style (from provided HTML UI)
  static const Color brandPrimary = Color(0xFF355872);
  static const Color brandPrimaryLight = Color(0xFF4A7A99);

  final _firestoreService = FirestoreService();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Extras
  double? _attendancePct;
  int _totalPoints = 0;
  Map<String, dynamic>? _studentDetails;
  bool _loadingExtras = true;
  bool _parentChatLoading = false;
  String? _resolvedAuthUid; // Store resolved auth UID for reuse

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1),
    );
    _fadeAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
    _slideAnimation = Tween<Offset>(begin: Offset.zero, end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animationController, curve: Curves.linear),
        );
    _animationController.forward();
    _loadExtras();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadExtras() async {
    try {
      // First resolve the auth UID
      await _resolveAuthUid();

      await Future.wait([
        _fetchStudentDetails(),
        _fetchAttendancePercentage(),
        _fetchPoints(),
      ]);
    } finally {
      if (mounted) setState(() => _loadingExtras = false);
    }
  }

  Future<void> _resolveAuthUid() async {
    try {
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      if (studentDoc.exists) {
        _resolvedAuthUid =
            studentDoc.data()?['uid'] as String? ?? widget.studentId;
      } else {
        _resolvedAuthUid = widget.studentId;
      }
    } catch (e) {
      _resolvedAuthUid = widget.studentId;
    }
  }

  Future<void> _fetchStudentDetails() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      if (doc.exists) _studentDetails = doc.data();
    } catch (e) {}
  }

  Future<void> _fetchAttendancePercentage() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final schoolCode = auth.currentUser?.instituteId ?? '';
      if (schoolCode.isEmpty) return;
      final gradeMatch = RegExp(
        r'Grade\s+(\d+)',
      ).firstMatch(widget.studentClass);
      final sectionMatch = RegExp(
        r'-\s*([A-Za-z])',
      ).firstMatch(widget.studentClass);
      final grade = gradeMatch?.group(1);
      final section = sectionMatch?.group(1);
      if (grade == null || section == null) return;

      final authUid = _resolvedAuthUid ?? widget.studentId;

      final q = await FirebaseFirestore.instance
          .collection('attendance')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('standard', isEqualTo: grade)
          .where('section', isEqualTo: section)
          .limit(120)
          .get();
      int total = 0;
      int present = 0;
      for (final doc in q.docs) {
        final students = doc.data()['students'] as Map<String, dynamic>?;
        if (students == null) continue;
        // Direct lookup by auth UID (new schema)
        final info = students[authUid] as Map<String, dynamic>?;
        if (info == null) {
          continue;
        }
        total++;
        if ((info['status']?.toString().toLowerCase() ?? 'present') ==
            'present') {
          present++;
        }
      }
      if (total > 0) _attendancePct = (present / total * 100).clamp(0, 100);
    } catch (e) {}
  }

  Future<void> _fetchPoints() async {
    try {
      final authUid = _resolvedAuthUid ?? widget.studentId;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(authUid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          _totalPoints =
              (userData?['totalPoints'] ?? userData?['rewardPoints'] ?? 0)
                  as int;
        }
      } catch (e) {}
      if (_totalPoints == 0) {
        try {
          final studentDoc = await FirebaseFirestore.instance
              .collection('students')
              .doc(widget.studentId)
              .get();
          if (studentDoc.exists) {
            final studentData = studentDoc.data();
            _totalPoints =
                (studentData?['totalPoints'] ??
                        studentData?['rewardPoints'] ??
                        0)
                    as int;
          }
        } catch (e) {}
      }
      if (mounted) setState(() {});
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          _buildHeader(context, theme),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: StreamBuilder<PerformanceModel?>(
                  stream: _firestoreService.getPerformanceStream(
                    _resolvedAuthUid ?? widget.studentId,
                  ),
                  builder: (context, snapshot) {
                    final perf = snapshot.data;

                    // Debug logging
                    if (perf != null) {
                      if (perf.submissions.isNotEmpty) {}
                    } else {}

                    // Compute real-time stats from performance data
                    final avgScore = perf?.averageScore ?? 0.0;
                    final testsTaken = perf?.submissions.length ?? 0;

                    // Use totalPoints from users collection (_totalPoints) as primary source
                    // Fall back to calculated points only if _totalPoints is 0
                    int calculatedPoints =
                        perf?.submissions.fold<int>(
                          0,
                          (sum, s) => sum + s.totalPoints,
                        ) ??
                        0;

                    final totalPoints = _totalPoints > 0
                        ? _totalPoints
                        : calculatedPoints;

                    final latestScore = perf?.submissions.isNotEmpty == true
                        ? perf!.submissions.last.percentage
                        : 0.0;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Column(
                            children: [
                              _buildMessageParent(theme),
                              const SizedBox(height: 24),
                              _buildQuickStats(
                                theme,
                                perf,
                                avgScore,
                                testsTaken,
                                totalPoints,
                                latestScore,
                              ),
                              const SizedBox(height: 24),
                              _buildPerformanceTrend(theme, perf),
                              const SizedBox(height: 24),
                              _buildRecentTests(theme, perf),
                              const SizedBox(height: 24),
                              _buildPersonalDetails(theme),
                              const SizedBox(height: 48),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.black
            : theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        onPressed: () => Navigator.pop(context),
                        color: theme.iconTheme.color,
                      ),
                      Expanded(
                        child: Text(
                          'Student Performance',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Row(
                    children: [
                      _buildIdentityBlock(theme),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.studentName,
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.studentClass,
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 14,
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
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;
    final borderColor = isDark ? const Color(0xFF2A2D3A) : theme.dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.5), width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Trend',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Average Score',
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              fontSize: 14,
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
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
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
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
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
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
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
              color: brandPrimary,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    brandPrimary.withOpacity(0.2),
                    brandPrimary.withOpacity(0.0),
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
    final submissions = (perf?.submissions ?? [])
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    final recent = submissions.take(5).toList();

    if (recent.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;
    final borderColor = isDark ? const Color(0xFF2A2D3A) : theme.dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(0.5), width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history,
                color: theme.iconTheme.color?.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Recent Test History',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...recent.map(
            (submission) => _buildTestHistoryItem(theme, submission),
          ),
        ],
      ),
    );
  }

  Widget _buildTestHistoryItem(ThemeData theme, TestSubmission submission) {
    final percentage = submission.percentage;
    final color = _getScoreColor(percentage);
    final isDark = theme.brightness == Brightness.dark;
    final itemBg = isDark ? theme.cardColor.withOpacity(0.3) : theme.cardColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Center(
              child: Text(
                '${percentage.round()}%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  submission.testTitle,
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 12,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(submission.submittedAt),
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.stars,
                      size: 12,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${submission.totalPoints} pts',
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            percentage >= 75
                ? Icons.thumb_up
                : percentage >= 60
                ? Icons.thumbs_up_down
                : Icons.thumb_down,
            color: color,
            size: 24,
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 90) return const Color(0xFF10B981);
    if (percentage >= 75) return const Color(0xFF84CC16);
    if (percentage >= 60) return const Color(0xFFF59E0B);
    if (percentage >= 35) return const Color(0xFFF97316);
    return const Color(0xFFEF4444);
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  // Quick stats with requested metrics
  Widget _buildQuickStats(
    ThemeData theme,
    PerformanceModel? perf,
    double avg,
    int testsTaken,
    int totalPoints,
    double latestScore,
  ) {
    final attendanceStr = _attendancePct != null
        ? '${_attendancePct!.round()}%'
        : _loadingExtras
        ? '…'
        : '—';
    final latestScoreDisplay = latestScore > 0
        ? '${latestScore.round()}%'
        : '0%';

    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;
    final borderColor = isDark ? const Color(0xFF2A2D3A) : theme.dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.analytics,
                color: theme.iconTheme.color?.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Quick Stats',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _statCard(
                theme,
                'Avg Score',
                '${avg.round()}%',
                Icons.school,
                brandPrimary,
              ),
              const SizedBox(width: 12),
              _statCard(
                theme,
                'Attendance',
                attendanceStr,
                Icons.event_available,
                brandPrimary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCard(
                theme,
                'Points',
                totalPoints.toString(),
                Icons.stars,
                brandPrimary,
              ),
              const SizedBox(width: 12),
              _statCard(
                theme,
                'Tests',
                testsTaken.toString(),
                Icons.assignment,
                brandPrimary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCard(
                theme,
                'Latest',
                latestScoreDisplay,
                Icons.trending_up,
                brandPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? theme.cardColor.withOpacity(0.3) : theme.cardColor;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.dividerColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalDetails(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A1B24) : theme.cardColor;
    final d = _studentDetails;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2D3A) : theme.dividerColor,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [brandPrimary, brandPrimaryLight],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: brandPrimary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.person_outline,
                  color: theme.textTheme.bodyLarge?.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Personal Details',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loadingExtras)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      'Loading details…',
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (d == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 48,
                      color: Colors.redAccent.withOpacity(0.7),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Student record not found',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _detailRow(
              theme,
              Icons.email_outlined,
              'Email',
              (d['email'] ?? '—').toString(),
              brandPrimary,
            ),
            const Divider(height: 24),
            _detailRow(
              theme,
              Icons.phone_outlined,
              'Phone',
              (d['phoneNumber'] ?? d['phone'] ?? d['contactNumber'] ?? '—')
                  .toString(),
              brandPrimary,
            ),
            const Divider(height: 24),
            _detailRow(
              theme,
              Icons.badge_outlined,
              'Student ID',
              (d['studentId'] ?? '—').toString(),
              brandPrimary,
            ),
            const Divider(height: 24),
            _detailRow(
              theme,
              Icons.phone_android_outlined,
              'Parent Phone',
              (d['parentPhone'] ?? '—').toString(),
              brandPrimary,
            ),
            const Divider(height: 24),
            _detailRow(
              theme,
              Icons.class_outlined,
              'Section',
              (d['section'] ?? '—').toString(),
              brandPrimary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageParent(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A1B24) : theme.cardColor;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2A2D3A) : theme.dividerColor,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [brandPrimary, brandPrimaryLight],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: brandPrimary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: theme.textTheme.bodyLarge?.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Message Parent',
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Open a conversation with the parent to share progress, discuss concerns, or celebrate achievements.',
            style: TextStyle(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _parentChatLoading ? null : _startParentChat,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
                backgroundColor: brandPrimary,
                foregroundColor: theme.textTheme.bodyLarge?.color,
                elevation: 4,
                shadowColor: brandPrimary.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: _parentChatLoading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Opening Chat...',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Start',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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

  Future<void> _startParentChat() async {
    setState(() => _parentChatLoading = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final teacherId = auth.currentUser?.uid;

      if (teacherId == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Teacher ID not found')));
        }
        return;
      }

      // Extract student information with null safety
      final studentId = _resolvedAuthUid ?? widget.studentId;
      final parentPhone = _studentDetails?['parentPhone']?.toString().trim();
      final studentEmail = _studentDetails?['email']?.toString().trim();

      final messaging = MessagingService();
      final parentData = await messaging.fetchParentForStudent(
        studentId,
        parentPhone: parentPhone?.isEmpty == true ? null : parentPhone,
        studentEmail: studentEmail?.isEmpty == true ? null : studentEmail,
      );

      if (!mounted) return;

      if (parentData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No parent found for ${widget.studentName}'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Details',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Parent Not Found'),
                    content: Text(
                      'Could not locate parent for:\n\n'
                      'Student: ${widget.studentName}\n'
                      'ID: $studentId\n\n'
                      'Please ensure the parent account is created and linked to this student in Firebase.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        return;
      }

      // Get parent phone number
      final parentPhoneNumber = parentData['phoneNumber'] as String?;

      if (parentPhoneNumber == null || parentPhoneNumber.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Parent phone number not available'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Directly open WhatsApp
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening WhatsApp...'),
          duration: Duration(seconds: 1),
        ),
      );

      final whatsappService = WhatsAppChatService();
      final success = await whatsappService.startParentWhatsAppChat(
        studentName: widget.studentName,
        parentPhoneNumber: parentPhoneNumber,
      );

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open WhatsApp. Please make sure WhatsApp is installed.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening WhatsApp: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _parentChatLoading = false);
    }
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

  // Build avatar/initials block matching the HTML hero
  Widget _buildIdentityBlock(ThemeData theme) {
    final name = widget.studentName.trim();
    final initials = _initials(name);
    final img = widget.imageUrl;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [brandPrimary, brandPrimaryLight],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: (img.isNotEmpty)
            ? Image.network(
                img,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initialsCenter(initials),
              )
            : _initialsCenter(initials),
      ),
    );
  }

  Widget _initialsCenter(String initials) {
    return Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r"\s+"));
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.last : '';
    final i1 = first.isNotEmpty ? first[0] : '';
    final i2 = last.isNotEmpty ? last[0] : '';
    final text = (i1 + i2).toUpperCase();
    return text.isEmpty && name.isNotEmpty ? name[0].toUpperCase() : text;
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
