import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/test_result_model.dart';
import 'dart:math' as math;

class TeacherStudentResultDetailScreen extends StatefulWidget {
  final String resultId;
  final String testId;

  const TeacherStudentResultDetailScreen({
    Key? key,
    required this.resultId,
    required this.testId,
  }) : super(key: key);

  @override
  State<TeacherStudentResultDetailScreen> createState() =>
      _TeacherStudentResultDetailScreenState();
}

class _TeacherStudentResultDetailScreenState
    extends State<TeacherStudentResultDetailScreen> {
  bool _isLoading = true;
  TestResultModel? _result;
  List<Map<String, dynamic>> _questions = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadResultDetails();
  }

  Future<void> _loadResultDetails() async {
    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;

      // Load the result document
      final resultDoc = await firestore
          .collection('testResults')
          .doc(widget.resultId)
          .get();

      if (!resultDoc.exists) {
        setState(() {
          _errorMessage = 'Result not found';
          _isLoading = false;
        });
        return;
      }

      _result = TestResultModel.fromFirestore(resultDoc);

      // Load test questions
      final testDoc = await firestore
          .collection('scheduledTests')
          .doc(widget.testId)
          .get();

      if (testDoc.exists) {
        final testData = testDoc.data()!;
        if (testData['questions'] != null) {
          _questions = List<Map<String, dynamic>>.from(
            testData['questions'].map((q) => Map<String, dynamic>.from(q)),
          );
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading result details: $e');
      setState(() {
        _errorMessage = 'Error loading result: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Student Result Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadResultDetails,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadResultDetails,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadResultDetails,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStudentInfoCard(),
                    const SizedBox(height: 16),
                    _buildScoreCard(),
                    const SizedBox(height: 16),
                    _buildAnswersCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStudentInfoCard() {
    if (_result == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.blue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _result!.studentName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _result!.studentEmail,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.access_time,
            'Completed At',
            _formatDateTime(_result!.completedAt),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            Icons.timer,
            'Time Taken',
            _formatDuration(_result!.timeTaken),
          ),
          if (_result!.violationDetected) ...[
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.warning,
              'Violations',
              '${_result!.tabSwitchCount} tab switches',
              color: Colors.orange,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color ?? Theme.of(context).textTheme.bodyLarge?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreCard() {
    if (_result == null) return const SizedBox.shrink();

    final percentage = _result!.totalQuestions > 0
        ? (_result!.correctAnswers / _result!.totalQuestions) * 100
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getScoreColor(percentage),
            _getScoreColor(percentage).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _getScoreColor(percentage).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildScoreStat(
                'Score',
                '${percentage.toStringAsFixed(1)}%',
                Icons.stars,
              ),
              Container(
                width: 1,
                height: 60,
                color: Colors.white.withOpacity(0.3),
              ),
              _buildScoreStat(
                'Correct',
                '${_result!.correctAnswers}/${_result!.totalQuestions}',
                Icons.check_circle,
              ),
              Container(
                width: 1,
                height: 60,
                color: Colors.white.withOpacity(0.3),
              ),
              _buildScoreStat(
                'Wrong',
                '${_result!.totalQuestions - _result!.correctAnswers}',
                Icons.cancel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
        ),
      ],
    );
  }

  Widget _buildAnswersCard() {
    if (_result == null || _result!.answers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: Text('No answers available')),
      );
    }

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
            'Detailed Answers',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _result!.answers.length,
            separatorBuilder: (context, index) => const Divider(height: 32),
            itemBuilder: (context, index) {
              final answer = _result!.answers[index];
              final questionData = index < _questions.length
                  ? _questions[index]
                  : <String, dynamic>{};
              return _buildAnswerItem(index + 1, answer, questionData);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerItem(
    int questionNumber,
    Map<String, dynamic> answer,
    Map<String, dynamic> questionData,
  ) {
    final questionText =
        answer['questionText'] ??
        questionData['questionText'] ??
        questionData['question'] ??
        'Question $questionNumber';
    final userAnswer = answer['userAnswer'] ?? 'Not answered';
    final correctAnswer = answer['correctAnswer'] ?? '';
    final isCorrect = answer['isCorrect'] ?? false;

    List<dynamic> options = questionData['options'] as List? ?? [];
    final questionType = questionData['type'] ?? 'mcq';

    // For True/False questions, create synthetic options if none exist
    if (questionType == 'tf' && options.isEmpty) {
      options = ['True', 'False'];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question Header
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCorrect
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isCorrect ? Colors.green : Colors.red,
                  width: 2,
                ),
              ),
              child: Text(
                'Q$questionNumber',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isCorrect ? Colors.green : Colors.red,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  questionText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Options (if available)
        if (options.isNotEmpty) ...[
          ...options.asMap().entries.map((entry) {
            final optionIndex = entry.key;
            final option = entry.value.toString();
            final optionLabel = String.fromCharCode(65 + optionIndex);

            // Determine if this is the user's answer or correct answer
            final isUserAnswer =
                userAnswer == option || userAnswer.toUpperCase() == optionLabel;
            final isCorrectOption =
                correctAnswer == optionLabel ||
                correctAnswer.toLowerCase() == option.toLowerCase();

            Color? bgColor;
            Color? borderColor;
            IconData? icon;

            if (isCorrectOption) {
              bgColor = Colors.green.withOpacity(0.2);
              borderColor = Colors.green;
              icon = Icons.check_circle;
            } else if (isUserAnswer) {
              bgColor = Colors.red.withOpacity(0.2);
              borderColor = Colors.red;
              icon = Icons.cancel;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: bgColor ?? Colors.grey[800],
                  border: Border.all(
                    color: borderColor ?? Colors.grey[700]!,
                    width: borderColor != null ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: borderColor ?? Colors.grey[700],
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          optionLabel,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        option,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: borderColor != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (icon != null) Icon(icon, color: borderColor, size: 24),
                  ],
                ),
              ),
            );
          }).toList(),
        ] else ...[
          // No options available - show simple answer comparison
          _buildSimpleAnswer('Student Answer', userAnswer, isCorrect),
          const SizedBox(height: 8),
          _buildSimpleAnswer('Correct Answer', correctAnswer, true),
        ],
      ],
    );
  }

  Widget _buildSimpleAnswer(String label, String answer, bool isCorrect) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCorrect
            ? Colors.green.withOpacity(0.2)
            : Colors.red.withOpacity(0.2),
        border: Border.all(
          color: isCorrect ? Colors.green : Colors.red,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.cancel,
            color: isCorrect ? Colors.green : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[400],
            ),
          ),
          Expanded(
            child: Text(
              answer,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 90) return Colors.green;
    if (percentage >= 75) return Colors.lightGreen;
    if (percentage >= 60) return Colors.orange;
    if (percentage >= 35) return Colors.deepOrange;
    return Colors.red;
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min${minutes != 1 ? 's' : ''}';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }
}
