import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../../models/test_result_model.dart';
import 'teacher_student_result_detail_screen.dart';
import 'dart:math' as math;

class TestResultScreen extends StatefulWidget {
  final String testId;
  final String testName;
  final String className;
  final String status;
  final String endTime;

  const TestResultScreen({
    super.key,
    required this.testId,
    required this.testName,
    required this.className,
    required this.status,
    required this.endTime,
  });

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  bool _isLoading = true;
  List<TestResultModel> _completedResults = [];
  List<Map<String, dynamic>> _allAssignments = [];
  int _totalAssigned = 0;
  double _averageScore = 0.0;
  double _highestScore = 0.0;
  double _lowestScore = 0.0;
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    _loadTestResults();
  }

  Future<void> _loadTestResults() async {
    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final teacherUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
      if (teacherUid == null || teacherUid.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get all assignments for this test (both completed and pending)
      final assignmentsSnapshot = await firestore
          .collection('testResults')
          .where('testId', isEqualTo: widget.testId)
          .where('teacherId', isEqualTo: teacherUid)
          .get();

      // Separate completed and pending, deduplicating by studentId
      // (prefer 'completed' entry over 'assigned' for the same student)
      final completed = <TestResultModel>[];
      final seenStudentIds = <String>{};
      final allAssignmentsByStudent = <String, Map<String, dynamic>>{};

      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        final studentId = (data['studentId'] ?? doc.id) as String;
        final status = data['status'] ?? 'assigned';
        final existing = allAssignmentsByStudent[studentId];

        // Keep completed over assigned; if both completed keep first seen
        if (existing == null ||
            (existing['status'] != 'completed' && status == 'completed')) {
          allAssignmentsByStudent[studentId] = {
            'id': doc.id,
            'studentName': data['studentName'] ?? '',
            'studentId': studentId,
            'status': status,
            'score': (data['score'] ?? 0).toDouble(),
            'totalQuestions': (data['totalQuestions'] ?? 0) as int,
            'correctAnswers': (data['correctAnswers'] ?? 0) as int,
            'totalMarks': (data['totalMarks'] ?? 0) as int,
            'violationDetected': (data['violationDetected'] ?? false) as bool,
          };
        }

        if (status == 'completed' && !seenStudentIds.contains(studentId)) {
          seenStudentIds.add(studentId);
          try {
            final result = TestResultModel.fromFirestore(doc);
            completed.add(result);
          } catch (e) {}
        }
      }

      final allAssignments = allAssignmentsByStudent.values.toList();
      _totalAssigned = allAssignments.length;

      // Get test details for total questions
      final testDoc = await firestore
          .collection('scheduledTests')
          .doc(widget.testId)
          .get();

      if (testDoc.exists) {
        final testData = testDoc.data()!;

        // Get questions list
        if (testData['questions'] != null) {
          _questions = List<Map<String, dynamic>>.from(
            testData['questions'].map((q) => Map<String, dynamic>.from(q)),
          );
          for (var i = 0; i < _questions.length; i++) {}
        }
      }

      // Calculate statistics from completed results
      if (completed.isNotEmpty) {
        // Calculate percentages properly
        final percentages = completed.map((r) {
          if (r.totalQuestions > 0) {
            return (r.correctAnswers / r.totalQuestions) * 100;
          }
          return 0.0;
        }).toList();

        _averageScore =
            percentages.reduce((a, b) => a + b) / percentages.length;
        _highestScore = percentages.reduce(math.max);
        _lowestScore = percentages.reduce(math.min);
      } else {
        _averageScore = 0.0;
        _highestScore = 0.0;
        _lowestScore = 0.0;
      }

      // Sort assignments: completed students first (by highest score), then pending (alphabetically)
      allAssignments.sort((a, b) {
        final aStatus = a['status'] as String;
        final bStatus = b['status'] as String;
        final aCompleted = aStatus == 'completed';
        final bCompleted = bStatus == 'completed';

        // If both completed or both not completed, sort accordingly
        if (aCompleted && bCompleted) {
          // Both completed: sort by score (highest first)
          final aTotalQuestions = a['totalQuestions'] as int;
          final bTotalQuestions = b['totalQuestions'] as int;

          // Calculate percentages
          final aPercentage = aTotalQuestions > 0
              ? (a['correctAnswers'] as int) / aTotalQuestions * 100
              : 0.0;
          final bPercentage = bTotalQuestions > 0
              ? (b['correctAnswers'] as int) / bTotalQuestions * 100
              : 0.0;

          return bPercentage.compareTo(aPercentage); // Descending order
        } else if (!aCompleted && !bCompleted) {
          // Both pending: sort alphabetically by name
          final aName = (a['studentName'] as String).toLowerCase();
          final bName = (b['studentName'] as String).toLowerCase();
          return aName.compareTo(bName);
        } else {
          // One completed, one not: completed students first
          return aCompleted ? -1 : 1;
        }
      });

      setState(() {
        _completedResults = completed;
        _allAssignments = allAssignments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: theme.textTheme.bodyLarge?.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Test Result',
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTestResults,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTestInfoCard(),
                    const SizedBox(height: 16),
                    _buildClassPerformanceCard(),
                    const SizedBox(height: 16),
                    _buildStudentResultsCard(),
                    const SizedBox(height: 16),
                    _buildTestQuestionsCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTestInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.testName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.className,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color:
                  ((widget.status).toLowerCase().contains('complete') ||
                      (widget.status).toLowerCase().contains('ended') ||
                      (widget.status).toLowerCase() == 'past')
                  ? const Color(0xFF22C55E)
                  : Colors.grey[800],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassPerformanceCard() {
    final completedCount = _completedResults.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Class Performance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          // Gauge Chart
          Center(
            child: SizedBox(
              height: 180,
              width: 180,
              child: CustomPaint(
                painter: _GaugePainter(
                  percentage: _averageScore,
                  color: _getScoreColor(_averageScore),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Average Score',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_averageScore.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Stats Row
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.arrow_upward,
                  label: 'Highest',
                  value: '${_highestScore.toStringAsFixed(0)}%',
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.arrow_downward,
                  label: 'Lowest',
                  value: '${_lowestScore.toStringAsFixed(0)}%',
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Participation
          Row(
            children: [
              Icon(Icons.people, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                'Participated: $completedCount / $_totalAssigned Students',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentResultsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student Results',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_allAssignments.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text(
                  'No students assigned to this test',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _allAssignments.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final assignment = _allAssignments[index];
                return _buildStudentResultItem(assignment);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStudentResultItem(Map<String, dynamic> assignment) {
    final status = assignment['status'] as String;
    final studentName = assignment['studentName'] as String;
    final isCompleted = status == 'completed';
    final violationDetected = assignment['violationDetected'] as bool;

    String scoreText = '-';
    double percentage = 0.0;

    if (isCompleted) {
      final correctAnswers = assignment['correctAnswers'] as int;
      final totalQuestions = assignment['totalQuestions'] as int;

      if (totalQuestions > 0) {
        percentage = (correctAnswers / totalQuestions) * 100;
        scoreText = '$correctAnswers / $totalQuestions';
      }
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      title: Text(
        studentName,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: isCompleted
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: Colors.grey[300],
                  color: _getScoreColor(percentage),
                  minHeight: 4,
                ),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (violationDetected)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning, color: Colors.orange, size: 18),
            ),
          const SizedBox(width: 8),
          if (isCompleted)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 18,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            scoreText,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isCompleted ? _getScoreColor(percentage) : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: isCompleted
          ? () {
              // Navigate to teacher-specific student result detail screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TeacherStudentResultDetailScreen(
                    resultId: assignment['id'],
                    testId: widget.testId,
                  ),
                ),
              );
            }
          : null,
    );
  }

  Widget _buildTestQuestionsCard() {
    if (_questions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.quiz, color: Colors.blue, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test Questions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No questions available',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.quiz, color: Colors.blue, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Test Questions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_questions.length} Questions',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),
          // Questions list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _questions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final question = _questions[index];
              return _buildQuestionItem(index + 1, question);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionItem(int questionNumber, Map<String, dynamic> question) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final questionText = question['questionText'] ?? question['question'] ?? '';
    final questionType = question['type'] ?? 'mcq';
    List<dynamic> options = question['options'] as List? ?? [];

    // For True/False questions, create synthetic options if none exist
    if (questionType == 'tf' && options.isEmpty) {
      options = ['True', 'False'];
    }

    final correctAnswer = question['correctAnswer'] ?? '';
    final marks = question['marks'] ?? 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Q$questionNumber',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$marks mark${marks > 1 ? "s" : ""}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Question text
        if (questionText.isNotEmpty)
          Text(
            questionText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        if (questionText.isNotEmpty) const SizedBox(height: 16),
        if (questionText.isEmpty)
          const Text(
            '(Question text not available)',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.grey,
            ),
          ),
        if (questionText.isEmpty) const SizedBox(height: 12),
        // Options
        ...options.asMap().entries.map((entry) {
          final optionIndex = entry.key;
          final option = entry.value.toString();
          final optionLabel = String.fromCharCode(
            65 + optionIndex,
          ); // A, B, C, D

          // Compare option label with correctAnswer (e.g., "A" == "A" or "true" == "true")
          final isCorrect =
              optionLabel == correctAnswer.toUpperCase() ||
              option.toLowerCase() == correctAnswer.toLowerCase();

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isCorrect
                    ? (isDark
                          ? Colors.green.withOpacity(0.25)
                          : Colors.green.withOpacity(0.15))
                    : (isDark ? Colors.grey[800] : Colors.grey[200]),
                border: Border.all(
                  color: isCorrect
                      ? Colors.green
                      : (isDark ? Colors.grey[700]! : Colors.grey[400]!),
                  width: isCorrect ? 3 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? Colors.green
                          : (isDark ? Colors.grey[700] : Colors.grey[400]),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        optionLabel,
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
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isCorrect
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  if (isCorrect)
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 90) return Colors.green;
    if (percentage >= 75) return Colors.lightGreen;
    if (percentage >= 60) return Colors.orange;
    if (percentage >= 35) return Colors.deepOrange;
    return Colors.red;
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final Color color;

  _GaugePainter({required this.percentage, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = 16.0;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      math.pi * 0.75, // Start at bottom-left
      math.pi * 1.5, // 270 degrees arc
      false,
      bgPaint,
    );

    // Progress arc
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.red,
          Colors.orange,
          Colors.yellow,
          Colors.lightGreen,
          Colors.green,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (percentage / 100) * math.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
      math.pi * 0.75,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
