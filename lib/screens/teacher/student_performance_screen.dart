import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/performance_model.dart';
import '../../services/firestore_service.dart';
import '../../services/messaging_service.dart';
import '../../providers/auth_provider.dart';
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
  // Extras
  double? _attendancePct;
  int _totalPoints = 0;
  int _badgesCount = 0;
  List<String> _badges = [];
  Map<String, dynamic>? _studentDetails;
  bool _loadingExtras = true;
  bool _parentChatLoading = false;
  String? _resolvedAuthUid; // Store resolved auth UID for reuse

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      // First resolve the auth UID
      await _resolveAuthUid();

      await Future.wait([
        _fetchStudentDetails(),
        _fetchAttendancePercentage(),
        _fetchBadgesAndPoints(),
      ]);
    } catch (e) {
      debugPrint('⚠️ extras load error: $e');
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
        debugPrint(
          '📊 Resolved auth UID: $_resolvedAuthUid from doc: ${widget.studentId}',
        );
      } else {
        _resolvedAuthUid = widget.studentId;
      }
    } catch (e) {
      debugPrint('⚠️ Auth UID resolution failed: $e');
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
    } catch (e) {
      debugPrint('⚠️ student details error: $e');
    }
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
      debugPrint(
        '📊 Found ${q.docs.length} attendance docs for grade $grade section $section',
      );
      int total = 0;
      int present = 0;
      for (final doc in q.docs) {
        final students = doc.data()['students'] as Map<String, dynamic>?;
        if (students == null) continue;
        // Direct lookup by auth UID (new schema)
        final info = students[authUid] as Map<String, dynamic>?;
        if (info == null) {
          debugPrint(
            '⚠️ Student $authUid not found in attendance doc ${doc.id}. Keys: ${students.keys.take(3).join(", ")}',
          );
          continue;
        }
        total++;
        if ((info['status']?.toString().toLowerCase() ?? 'present') ==
            'present') {
          present++;
        }
      }
      debugPrint('📊 Attendance: $present/$total present');
      if (total > 0) _attendancePct = (present / total * 100).clamp(0, 100);
    } catch (e) {
      debugPrint('⚠️ attendance error: $e');
    }
  }

  Future<void> _fetchBadgesAndPoints() async {
    try {
      final authUid = _resolvedAuthUid ?? widget.studentId;
      final q = await FirebaseFirestore.instance
          .collection('testResults')
          .where('studentId', isEqualTo: authUid)
          .limit(60)
          .get();
      final Set<String> badgeSet = {};
      int pts = 0;
      for (final doc in q.docs) {
        final data = doc.data();
        pts += (data['totalPoints'] as num?)?.toInt() ?? 0;
        final badges = data['badges'];
        if (badges is List) {
          for (final b in badges) {
            if (b != null) badgeSet.add(b.toString());
          }
        }
      }
      _badges = badgeSet.toList()..sort();
      _badgesCount = _badges.length;
      _totalPoints = pts;
      debugPrint(
        '📊 Badges/Points: $_badgesCount badges, $_totalPoints points',
      );
    } catch (e) {
      debugPrint('⚠️ badges/points error: $e');
    }
  }

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
                    _resolvedAuthUid ?? widget.studentId,
                  ),
                  builder: (context, snapshot) {
                    final perf = snapshot.data;

                    // Compute real-time stats from performance data
                    final avgScore = perf?.averageScore ?? 0.0;
                    final testsTaken = perf?.submissions.length ?? 0;
                    final totalPoints =
                        perf?.submissions.fold<int>(
                          0,
                          (sum, s) => sum + s.totalPoints,
                        ) ??
                        _totalPoints;
                    final latestScore = perf?.submissions.isNotEmpty == true
                        ? perf!.submissions.last.score.toDouble()
                        : 0.0;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
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
                          const SizedBox(height: 24),
                          _buildBadgesSection(theme),
                          const SizedBox(height: 24),
                          _buildPersonalDetails(theme),
                          const SizedBox(height: 24),
                          _buildMessageParent(theme),
                          const SizedBox(height: 48),
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
            'Quick Stats',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statCard(theme, 'Avg Score', '${avg.round()}%'),
              const SizedBox(width: 12),
              _statCard(theme, 'Attendance', attendanceStr),
              const SizedBox(width: 12),
              _statCard(theme, 'Total Points', totalPoints.toString()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCard(theme, 'Badges', _badgesCount.toString()),
              const SizedBox(width: 12),
              _statCard(theme, 'Tests', testsTaken.toString()),
              const SizedBox(width: 12),
              Expanded(child: _statCard(theme, 'Latest', latestScoreDisplay)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(ThemeData theme, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgesSection(ThemeData theme) {
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
            'Badges Earned',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingExtras)
            Text(
              'Loading badges…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            )
          else if (_badges.isEmpty)
            Text(
              'No badges yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _badges.map((b) => _badgeChip(theme, b)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _badgeChip(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPersonalDetails(ThemeData theme) {
    final d = _studentDetails;
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
            'Personal Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingExtras)
            Text('Loading…', style: theme.textTheme.bodyMedium)
          else if (d == null)
            Text(
              'Student record not found',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else ...[
            _detailRow(theme, 'Email', (d['email'] ?? '—').toString()),
            _detailRow(
              theme,
              'Phone',
              (d['phoneNumber'] ?? d['phone'] ?? '—').toString(),
            ),
            _detailRow(theme, 'Roll No', (d['rollNo'] ?? '—').toString()),
            _detailRow(
              theme,
              'Parent Phone',
              (d['parentPhone'] ?? '—').toString(),
            ),
            _detailRow(theme, 'Section', (d['section'] ?? '—').toString()),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageParent(ThemeData theme) {
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
            'Message Parent',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Open a conversation with the parent to share progress or concerns.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _parentChatLoading ? null : _startParentChat,
              icon: const Icon(Icons.chat),
              label: Text(_parentChatLoading ? 'Opening...' : 'Message Parent'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
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
      if (teacherId == null) return;
      final parentPhone = _studentDetails?['parentPhone']?.toString();
      final messaging = MessagingService();
      final parentData = await messaging.fetchParentForStudent(
        widget.studentId,
        parentPhone: parentPhone,
      );
      if (parentData == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Parent not found')));
        return;
      }
      final conversationId = await messaging.getOrCreateConversation(
        teacherId: teacherId,
        parentId: parentData['parentId'],
        studentId: widget.studentId,
        studentName: widget.studentName,
        parentName: parentData['parentName'],
        parentPhotoUrl: parentData['parentPhotoUrl'],
      );
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/chat',
        arguments: {
          'conversationId': conversationId,
          'parentName': parentData['parentName'],
        },
      );
    } catch (e) {
      debugPrint('⚠️ parent chat error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error opening chat')));
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
