import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../widgets/teacher_bottom_nav.dart';

class TestResultScreen extends StatefulWidget {
  final String testId;
  final String testName;
  final String className;
  final String status; // initial status from list (may be stale)
  final String endTime; // initial text (not used after live binding)

  const TestResultScreen({
    Key? key,
    required this.testId,
    required this.testName,
    required this.className,
    required this.status,
    required this.endTime,
  }) : super(key: key);

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  TestModel? _test;
  List<TestResultModel> _results = [];
  List<Map<String, dynamic>> _allAssignedStudents =
      []; // All students (completed + pending)
  int _totalAssignedStudents = 0; // Track total students assigned
  bool _isLoading = true;
  String? _error;

  bool get _isLiveNow {
    final t = _test;
    if (t == null) return false;
    final now = DateTime.now();
    return t.startDate.isBefore(now) && t.endDate.isAfter(now);
  }

  String _formatRemaining(Duration d) {
    if (d.isNegative) return '00:00:00';
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Fetch test details from scheduledTests collection
      final testDoc = await _firestore
          .collection('scheduledTests')
          .doc(widget.testId)
          .get();
      if (!testDoc.exists) {
        setState(() {
          _error = 'Test not found';
          _isLoading = false;
        });
        return;
      }

      final test = TestModel.fromScheduledTest(testDoc.id, testDoc.data()!);

      // Fetch all testResults (both completed and assigned) for this test
      final allResultsSnapshot = await _firestore
          .collection('testResults')
          .where('testId', isEqualTo: widget.testId)
          .get();

      // Filter completed results (those with actual scores)
      // Exclude records with status='assigned' as those are pending
      final results = allResultsSnapshot.docs
          .where((doc) {
            final data = doc.data();
            final status = data['status'] as String?;
            // Only include if status is NOT 'assigned'
            // Status can be 'completed', null, or other values for actual submissions
            if (status == 'assigned') return false;
            // Include if has actual submission data
            return data['completedAt'] != null ||
                data['submittedAt'] != null ||
                data['resultId'] != null;
          })
          .map((doc) => TestResultModel.fromFirestore(doc))
          .toList();

      // Try to fetch from studentAssignments for accurate total
      int totalStudents = 0;
      List<Map<String, dynamic>> allStudents = [];
      try {
        final assignmentsSnapshot = await _firestore
            .collection('studentAssignments')
            .where('testId', isEqualTo: widget.testId)
            .get();

        if (assignmentsSnapshot.docs.isNotEmpty) {
          // Use studentAssignments as source of truth
          totalStudents = assignmentsSnapshot.docs.length;

          // Build comprehensive student list with status
          for (var assignDoc in assignmentsSnapshot.docs) {
            final assignData = assignDoc.data();
            final studentId = assignData['studentId'] as String?;
            final studentName =
                assignData['studentName'] as String? ?? 'Unknown';

            // Find matching completed result (filtered results already exclude 'assigned' status)
            final matchingResult = results.firstWhere(
              (r) => r.studentId == studentId,
              orElse: () => TestResultModel(
                id: '',
                studentId: studentId ?? '',
                studentName: studentName,
                studentEmail: '',
                testId: widget.testId,
                testTitle: '',
                subject: '',
                score: 0,
                totalQuestions: 0,
                correctAnswers: 0,
                completedAt: DateTime.now(),
                timeTaken: 0,
                answers: [],
              ),
            );

            final hasCompleted = matchingResult.id.isNotEmpty;
            final studentStatus = hasCompleted ? 'completed' : 'not_attempted';
            print(
              '📊 Student: $studentName | Status: $studentStatus | Score: ${hasCompleted ? matchingResult.score : "N/A"} | Result ID: ${matchingResult.id}',
            );

            allStudents.add({
              'studentId': studentId,
              'studentName': studentName,
              'result': hasCompleted ? matchingResult : null,
              'status': studentStatus,
            });
          }
        } else {
          // Fallback: Build unique student list from testResults
          // Group by studentId and prioritize completed over assigned
          final studentMap = <String, Map<String, dynamic>>{};

          for (var doc in allResultsSnapshot.docs) {
            final data = doc.data();
            final studentId = data['studentId'] as String?;
            final studentName = data['studentName'] as String? ?? 'Unknown';
            final status = data['status'] as String?;

            if (studentId == null || studentId.isEmpty) continue;

            // If student already exists, only replace if current record is completed
            if (studentMap.containsKey(studentId)) {
              final existingStatus =
                  studentMap[studentId]!['status'] as String?;
              // Skip if existing is already completed, or if both are assigned
              if (existingStatus != 'assigned' || status == 'assigned')
                continue;
            }

            studentMap[studentId] = {
              'studentId': studentId,
              'studentName': studentName,
              'status': status,
            };
          }

          totalStudents = studentMap.length;

          // Build list from unique students
          for (var studentInfo in studentMap.values) {
            final studentId = studentInfo['studentId'] as String;
            final studentName = studentInfo['studentName'] as String;

            // Find matching completed result (excludes status='assigned')
            final matchingResult = results.firstWhere(
              (r) => r.studentId == studentId,
              orElse: () => TestResultModel(
                id: '',
                studentId: studentId,
                studentName: studentName,
                studentEmail: '',
                testId: widget.testId,
                testTitle: '',
                subject: '',
                score: 0,
                totalQuestions: 0,
                correctAnswers: 0,
                completedAt: DateTime.now(),
                timeTaken: 0,
                answers: [],
              ),
            );

            final hasCompleted = matchingResult.id.isNotEmpty;
            allStudents.add({
              'studentId': studentId,
              'studentName': studentName,
              'result': hasCompleted ? matchingResult : null,
              'status': hasCompleted ? 'completed' : 'not_attempted',
            });
          }
        }
      } catch (e) {
        print('Error fetching student assignments: $e');
        // Fallback: Build unique student list from testResults
        final studentMap = <String, Map<String, dynamic>>{};

        for (var doc in allResultsSnapshot.docs) {
          final data = doc.data();
          final studentId = data['studentId'] as String?;
          final studentName = data['studentName'] as String? ?? 'Unknown';
          final status = data['status'] as String?;

          if (studentId == null || studentId.isEmpty) continue;

          // Prioritize completed records over assigned
          if (studentMap.containsKey(studentId)) {
            final existingStatus = studentMap[studentId]!['status'] as String?;
            if (existingStatus != 'assigned' || status == 'assigned') continue;
          }

          studentMap[studentId] = {
            'studentId': studentId,
            'studentName': studentName,
          };
        }

        totalStudents = studentMap.length;

        // Build from unique students
        for (var studentInfo in studentMap.values) {
          final studentId = studentInfo['studentId'] as String;
          final studentName = studentInfo['studentName'] as String;

          final matchingResult = results.firstWhere(
            (r) => r.studentId == studentId,
            orElse: () => TestResultModel(
              id: '',
              studentId: studentId,
              studentName: studentName,
              studentEmail: '',
              testId: widget.testId,
              testTitle: '',
              subject: '',
              score: 0,
              totalQuestions: 0,
              correctAnswers: 0,
              completedAt: DateTime.now(),
              timeTaken: 0,
              answers: [],
            ),
          );

          final hasCompleted = matchingResult.id.isNotEmpty;
          allStudents.add({
            'studentId': studentId,
            'studentName': studentName,
            'result': hasCompleted ? matchingResult : null,
            'status': hasCompleted ? 'completed' : 'not_attempted',
          });
        }
      }

      setState(() {
        _test = test;
        _results = results;
        _allAssignedStudents = allStudents;
        _totalAssignedStudents = totalStudents;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading test data: $e');
      setState(() {
        _error = 'Failed to load test data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Test Result'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF121212)
          : Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildRedesignedHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildTopTestCard(),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildPerformanceGaugeSection(),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildStudentResultsRedesigned(context),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildQuestionsRedesigned(),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_isLiveNow) _buildEndTestButton(context),
        ],
      ),
      bottomNavigationBar: const TeacherBottomNav(selectedIndex: 2),
    );
  }

  /// ---------------- Redesigned UI Components (HTML -> Flutter) ----------------
  Widget _buildRedesignedHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF121212) : Theme.of(context).cardColor)
            .withOpacity(0.9),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? const Color(0xFF2F2F2F)
                : Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: isDark ? const Color(0xFFE0E0E0) : null,
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  'Test Result',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFFE0E0E0)
                        : Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                color: isDark ? const Color(0xFFE0E0E0) : null,
                onPressed: () => _showMoreOptions(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopTestCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLive = _isLiveNow;
    final isScheduled =
        !isLive && (_test != null && DateTime.now().isBefore(_test!.startDate));
    Color chipBg;
    Color chipText;
    if (isLive) {
      chipBg = const Color(0xFF28A745).withOpacity(0.2);
      chipText = const Color(0xFF28A745);
    } else if (isScheduled) {
      chipBg = const Color(0xFF007BFF).withOpacity(0.15);
      chipText = const Color(0xFF007BFF);
    } else {
      chipBg = (isDark ? const Color(0xFF2F2F2F) : const Color(0xFFE5E7EB));
      chipText = isDark ? const Color(0xFFA0A0A0) : const Color(0xFF374151);
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2F2F2F)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.testName,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFFE0E0E0)
                        : Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: isLive
                      ? [
                          BoxShadow(
                            color: const Color(0xFF28A745).withOpacity(0.4),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLive)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF28A745),
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (isLive) const SizedBox(width: 6),
                    Text(
                      isLive ? 'Live' : (isScheduled ? 'Scheduled' : 'Past'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: chipText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: isDark
                ? const Color(0xFF2F2F2F)
                : Theme.of(context).dividerColor,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.className,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? const Color(0xFFA0A0A0)
                      : Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              if (_test != null)
                StreamBuilder<DateTime>(
                  stream: Stream<DateTime>.periodic(
                    const Duration(seconds: 1),
                    (_) => DateTime.now(),
                  ),
                  builder: (context, snap) {
                    final now = snap.data ?? DateTime.now();
                    final remaining = _test!.endDate.difference(now);
                    final label = remaining.isNegative
                        ? 'Ended'
                        : 'Ends in: ${_formatRemaining(remaining)}';
                    return Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? const Color(0xFFA0A0A0)
                            : Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceGaugeSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? const Color(0xFF2F2F2F)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.people_outline,
                size: 48,
                color: isDark ? const Color(0xFF2F2F2F) : Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No submissions yet',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFFA0A0A0) : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final scores = _results.map((r) => r.score).toList();
    final totalPoints = _test?.totalPoints ?? 100;
    final percentages = scores.map((s) => (s / totalPoints) * 100).toList();
    final avgPercentage =
        percentages.reduce((a, b) => a + b) / percentages.length;
    final highestPercentage = percentages.reduce(math.max);
    final lowestPercentage = percentages.reduce(math.min);
    final participatedCount = _results.length;
    final totalStudents = _totalAssignedStudents > 0
        ? _totalAssignedStudents
        : participatedCount;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2F2F2F)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Class Performance',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? const Color(0xFFE0E0E0)
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 150,
              width: 300,
              child: CustomPaint(
                painter: SemiGaugePainter(progress: avgPercentage / 100),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Average Score',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFFA0A0A0)
                                : Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                        ),
                        Text(
                          '${avgPercentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFFE0E0E0)
                                : Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _miniStat(
                icon: Icons.arrow_upward,
                label: 'Highest',
                value: '${highestPercentage.toStringAsFixed(0)}%',
                color: const Color(0xFF28A745),
              ),
              Container(
                width: 1,
                height: 40,
                color: isDark
                    ? const Color(0xFF2F2F2F)
                    : Theme.of(context).dividerColor,
              ),
              _miniStat(
                icon: Icons.arrow_downward,
                label: 'Lowest',
                value: '${lowestPercentage.toStringAsFixed(0)}%',
                color: const Color(0xFFDC3545),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.groups, size: 20, color: Color(0xFFA0A0A0)),
              const SizedBox(width: 6),
              Text(
                'Participated: $participatedCount / $totalStudents Students',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? const Color(0xFFA0A0A0)
                      : Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFFA0A0A0)
                      : Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFFE0E0E0)
                      : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentResultsRedesigned(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalPoints = _test?.totalPoints ?? 100;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2F2F2F)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Text(
              'Student Results',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? const Color(0xFFE0E0E0)
                    : Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          if (_allAssignedStudents.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text(
                'No students assigned',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFFA0A0A0) : Colors.grey[600],
                ),
              ),
            )
          else
            Column(
              children: _allAssignedStudents.map((studentData) {
                final status = studentData['status'] as String;
                final result = studentData['result'] as TestResultModel?;
                final studentName = studentData['studentName'] as String;

                // Determine status: not_attempted, failed (<60%), passed (≥60%)
                IconData statusIcon;
                Color statusColor;
                Color barColor;
                double pct = 0.0;

                if (status == 'not_attempted' ||
                    result == null ||
                    result.id.isEmpty) {
                  statusIcon = Icons.warning_amber_rounded;
                  statusColor = const Color(0xFFFFC107); // Yellow
                  barColor = const Color(0xFF6B7280); // Gray
                  pct = 0.0;
                } else {
                  pct = (result.score / totalPoints).clamp(0, 1);
                  final passingThreshold = 0.60;

                  if (pct >= passingThreshold) {
                    statusIcon = Icons.check_circle;
                    statusColor = const Color(0xFF28A745); // Green
                    if (pct >= 0.85) {
                      barColor = const Color(0xFF28A745);
                    } else {
                      barColor = const Color(0xFFFFC107);
                    }
                  } else {
                    statusIcon = Icons.cancel;
                    statusColor = const Color(0xFFDC3545); // Red
                    barColor = const Color(0xFFDC3545);
                  }
                }

                return InkWell(
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? const Color(0xFF2F2F2F)
                              : Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFFE0E0E0)
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct.toDouble(),
                                  minHeight: 6,
                                  backgroundColor: isDark
                                      ? const Color(0xFF2F2F2F)
                                      : const Color(0xFFE5E7EB),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    barColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Row(
                          children: [
                            Icon(statusIcon, size: 22, color: statusColor),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 64,
                              child: Text(
                                status == 'not_attempted' ||
                                        result == null ||
                                        result.id.isEmpty
                                    ? '-'
                                    : '${result.score.toStringAsFixed((result.score % 1) == 0 ? 0 : 1)} / $totalPoints',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFFA0A0A0)
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Color(0xFFA0A0A0),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionsRedesigned() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_test == null || _test!.questions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? const Color(0xFF2F2F2F)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.quiz_outlined,
                size: 48,
                color: isDark ? const Color(0xFF2F2F2F) : Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No questions found',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFFA0A0A0) : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final questions = _test!.questions;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF2F2F2F)
              : Theme.of(context).dividerColor,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.quiz_outlined,
                size: 20,
                color: Color(0xFF007BFF),
              ),
              const SizedBox(width: 8),
              Text(
                'Test Questions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color(0xFFE0E0E0)
                      : Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF007BFF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${questions.length} Questions',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF007BFF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'All questions with options and correct answers',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? const Color(0xFFA0A0A0)
                  : Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 20),
          ...questions.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final q = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: idx == questions.length ? 0 : 16,
              ),
              child: _buildQuestionCard(q, idx),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.8),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
                color: Theme.of(context).iconTheme.color,
              ),
              Expanded(
                child: Text(
                  'Test Result',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  _showMoreOptions(context);
                },
                color: Theme.of(context).iconTheme.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestInfo() {
    Color statusBgColor;
    Color statusTextColor;

    final isLive = _isLiveNow;
    final isScheduled =
        !isLive && (_test != null && DateTime.now().isBefore(_test!.startDate));

    if (isLive) {
      statusBgColor = const Color(0xFFD1FAE5);
      statusTextColor = const Color(0xFF065F46);
    } else if (isScheduled) {
      statusBgColor = const Color(0xFF6366F1).withOpacity(0.2);
      statusTextColor = const Color(0xFF6366F1);
    } else {
      statusBgColor = const Color(0xFFE5E7EB);
      statusTextColor =
          Theme.of(context).textTheme.bodyLarge?.color ??
          const Color(0xFF1F2937);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.testName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.className,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: statusBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLive)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (isLive) const SizedBox(width: 8),
                  Text(
                    isLive ? 'Live' : (isScheduled ? 'Scheduled' : 'Past'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: statusTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_test != null)
          StreamBuilder<DateTime>(
            stream: Stream<DateTime>.periodic(
              const Duration(seconds: 1),
              (_) => DateTime.now(),
            ),
            builder: (context, snap) {
              final now = snap.data ?? DateTime.now();
              final remaining = _test!.endDate.difference(now);
              final label = remaining.isNegative
                  ? 'Ended'
                  : 'Ends in: ${_formatRemaining(remaining)}';
              return Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildClassPerformance() {
    if (_results.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No submissions yet',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // Calculate real statistics
    final scores = _results.map((r) => r.score).toList();
    final totalPoints = _test?.totalPoints ?? 100;
    final percentages = scores.map((s) => (s / totalPoints) * 100).toList();

    final avgPercentage =
        percentages.reduce((a, b) => a + b) / percentages.length;
    final highestPercentage = percentages.reduce(math.max);
    final lowestPercentage = percentages.reduce(math.min);
    final participatedCount = _results.length;
    final totalStudents = _totalAssignedStudents > 0
        ? _totalAssignedStudents
        : participatedCount;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Class Performance',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCircularProgress(avgPercentage / 100),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _buildStatItem(
                          Icons.arrow_upward,
                          'Highest',
                          '${highestPercentage.toStringAsFixed(0)}%',
                          const Color(0xFF10B981),
                          const Color(0xFFD1FAE5),
                        ),
                        const SizedBox(width: 16),
                        _buildStatItem(
                          Icons.arrow_downward,
                          'Lowest',
                          '${lowestPercentage.toStringAsFixed(0)}%',
                          const Color(0xFFEF4444),
                          const Color(0xFFFEE2E2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildStatItem(
                      Icons.groups,
                      'Participated',
                      '$participatedCount / $totalStudents Students',
                      const Color(0xFF6366F1),
                      const Color(0xFF6366F1).withOpacity(0.1),
                      fullWidth: true,
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

  Widget _buildCircularProgress(double progress) {
    final percentage = (progress * 100).toStringAsFixed(0);

    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CustomPaint(
              painter: CircularProgressPainter(
                progress: progress,
                backgroundColor: const Color(0xFFE5E7EB),
                progressColor: const Color(0xFF6366F1),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$percentage%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              Text(
                'Avg. Score',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String label,
    String value,
    Color iconColor,
    Color bgColor, {
    bool fullWidth = false,
  }) {
    final content = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return fullWidth ? content : Expanded(child: content);
  }

  Widget _buildStudentResults(BuildContext context) {
    if (_results.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No results available',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final totalPoints = _test?.totalPoints ?? 100;

    // Sort results by score (highest first)
    final sortedResults = List<TestResultModel>.from(_results)
      ..sort((a, b) => b.score.compareTo(a.score));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Results',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          ...sortedResults.take(10).map((result) {
            final percentage = (result.score / totalPoints);
            Color progressColor;
            if (percentage >= 0.85) {
              progressColor = const Color(0xFF10B981);
            } else if (percentage >= 0.60) {
              progressColor = const Color(0xFFFBBF24);
            } else {
              progressColor = const Color(0xFFEF4444);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                result.studentName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${result.score.toStringAsFixed(0)} / $totalPoints',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percentage,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE5E7EB),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progressColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'View details for ${result.studentName}',
                          ),
                        ),
                      );
                    },
                    color: const Color(0xFF9CA3AF),
                  ),
                ],
              ),
            );
          }).toList(),
          if (sortedResults.length > 10)
            TextButton(
              onPressed: () {
                // Show all results
              },
              child: Text('View all ${sortedResults.length} results'),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionsList() {
    if (_test == null || _test!.questions.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.quiz_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No questions found',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    final questions = _test!.questions;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.quiz_outlined,
                size: 20,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(width: 8),
              Text(
                'Test Questions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${questions.length} Questions',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'All questions with options and correct answers',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 20),
          ...questions.asMap().entries.map((entry) {
            final index = entry.key;
            final question = entry.value;
            final isLast = index == questions.length - 1;

            return Column(
              children: [
                _buildQuestionCard(question, index + 1),
                if (!isLast) const SizedBox(height: 16),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(Question question, int questionNumber) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final questionTypeLabel =
        {
          QuestionType.multipleChoice: 'MCQ',
          QuestionType.trueFalse: 'True/False',
          QuestionType.shortAnswer: 'Short Answer',
          QuestionType.essay: 'Essay',
        }[question.type] ??
        'MCQ';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Q$questionNumber',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question.question,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${question.points} marks',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B7280).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            questionTypeLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Options (only for multiple choice and true/false)
          if (question.options != null && question.options!.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...question.options!.asMap().entries.map((entry) {
              final optionIndex = entry.key;
              final option = entry.value;
              final optionLabel = String.fromCharCode(
                65 + optionIndex,
              ); // A, B, C, D
              final rawCorrect = question.correctAnswer?.trim();

              bool isCorrect = false;
              if (rawCorrect != null && rawCorrect.isNotEmpty) {
                final normalizedOption = option.trim().toLowerCase();
                final normalizedCorrect = rawCorrect.toLowerCase();
                // Direct text match
                if (normalizedOption == normalizedCorrect) {
                  isCorrect = true;
                } else {
                  // Letter-based (A,B,C,D)
                  final upper = rawCorrect.toUpperCase();
                  if (upper.length == 1 &&
                      upper.codeUnitAt(0) >= 65 &&
                      upper.codeUnitAt(0) <= 68) {
                    if (upper == optionLabel) isCorrect = true;
                  }
                  // Numeric index based (0,1,2,3 or 1-based 1..4)
                  final asInt = int.tryParse(rawCorrect);
                  if (asInt != null) {
                    if (asInt == optionIndex || asInt - 1 == optionIndex) {
                      isCorrect = true;
                    }
                  }
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCorrect
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCorrect
                          ? const Color(0xFF10B981)
                          : Theme.of(context).dividerColor,
                      width: isCorrect ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Leading badge (letter or check)
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isCorrect
                              ? const Color(0xFF10B981)
                              : (isDark
                                    ? Colors.grey[800]
                                    : const Color(0xFFF3F4F6)),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCorrect
                                ? const Color(0xFF10B981)
                                : (isDark
                                      ? Colors.grey[700]!
                                      : const Color(0xFFD1D5DB)),
                          ),
                          boxShadow: isCorrect
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withOpacity(0.4),
                                    blurRadius: 6,
                                    spreadRadius: 0.5,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: isCorrect
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : Text(
                                  optionLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Option text
                      Expanded(
                        child: Text(
                          option,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCorrect
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isCorrect
                                ? const Color(0xFF10B981)
                                : Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                      // Correct badge (only for correct option)
                      if (isCorrect)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.12),
                            border: Border.all(color: const Color(0xFF10B981)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Color(0xFF10B981),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Correct',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ] else if (question.correctAnswer != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 20,
                    color: Color(0xFF10B981),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Correct Answer:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          question.correctAnswer!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEndTestButton(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor, width: 0.8),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () {
                _showEndTestDialog(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.timer_off_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'End Test',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Test'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Edit test')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share Results'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share results')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export as PDF'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Export PDF')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete Test',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteDialog(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEndTestDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('End Test'),
          content: const Text(
            'Are you sure you want to end this test? Students will no longer be able to submit answers.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Test ended successfully')),
                );
              },
              child: const Text(
                'End Test',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Test'),
          content: const Text(
            'Are you sure you want to delete this test? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Go back to tests list
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Test deleted')));
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}

class CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;

  CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 10) / 2;

    // Background circle
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Painter for the semicircle performance gauge (0% -> left, 100% -> right)
class SemiGaugePainter extends CustomPainter {
  final double progress; // 0.0 - 1.0
  SemiGaugePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final strokeWidth = 20.0;
    final radius = (width - 60) / 2;
    final center = Offset(width / 2, height - 10);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = math.pi; // draw from left to right along top
    final sweepAngle = math.pi; // half circle

    // Background arc
    final bgPaint = Paint()
      ..color = const Color(0xFF2F2F2F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    // Gradient for progress
    final gradient = SweepGradient(
      startAngle: startAngle,
      endAngle: startAngle + sweepAngle,
      colors: const [Color(0xFFDC3545), Color(0xFFFFC107), Color(0xFF28A745)],
      stops: const [0.0, 0.5, 1.0],
    );
    final progPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final clamped = progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, startAngle, sweepAngle * clamped, false, progPaint);
  }

  @override
  bool shouldRepaint(covariant SemiGaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
