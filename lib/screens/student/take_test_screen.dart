import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import 'dart:async';
import '../../utils/visibility_stub.dart'
    if (dart.library.html) '../../utils/visibility_web.dart'
    as vis;

class TakeTestScreen extends StatefulWidget {
  final TestModel test;

  const TakeTestScreen({Key? key, required this.test}) : super(key: key);

  @override
  State<TakeTestScreen> createState() => _TakeTestScreenState();
}

class _TakeTestScreenState extends State<TakeTestScreen>
    with WidgetsBindingObserver {
  int currentQuestionIndex = 0;
  Map<int, String> answers = {}; // questionIndex -> selected answer
  Timer? _timer;
  Duration _timeRemaining = Duration.zero;
  bool _isSubmitting = false;
  bool _hasLeftApp = false;
  int _tabSwitchCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeRemaining = Duration(minutes: widget.test.duration);
    _startTimer();
    // Web-specific: detect browser tab visibility change (tab switch)
    if (kIsWeb) {
      vis.attachWebVisibilityListener(() {
        if (!_isSubmitting) {
          _tabSwitchCount++;
          _autoSubmitTestForViolation('Tab switching detected');
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (kIsWeb) {
      vis.detachWebVisibilityListener();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Detect when app goes to background or is paused
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (!_hasLeftApp && !_isSubmitting) {
        _hasLeftApp = true;
        _tabSwitchCount++;

        // Auto-submit the test immediately
        _autoSubmitTestForViolation('Tab switching detected');
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining.inSeconds > 0) {
        setState(() {
          _timeRemaining -= const Duration(seconds: 1);
        });
      } else {
        _timer?.cancel();
        _autoSubmitTest();
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _selectAnswer(String answer) {
    setState(() {
      answers[currentQuestionIndex] = answer;
    });
  }

  void _previousQuestion() {
    if (currentQuestionIndex > 0) {
      setState(() {
        currentQuestionIndex--;
      });
    }
  }

  void _nextQuestion() {
    if (currentQuestionIndex < widget.test.questions.length - 1) {
      setState(() {
        currentQuestionIndex++;
      });
    }
  }

  Future<void> _submitTest({
    bool isViolation = false,
    String? violationReason,
  }) async {
    if (_isSubmitting) return;

    // Confirm submission only if not a violation
    if (!isViolation) {
      final shouldSubmit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Submit Test?'),
          content: Text(
            'You have answered ${answers.length} out of ${widget.test.questions.length} questions.\n\nAre you sure you want to submit?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2800D),
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      );

      if (shouldSubmit != true) return;
    }

    setState(() => _isSubmitting = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final studentId = auth.currentUser?.uid;
      final studentEmail = auth.currentUser?.email;

      if (studentId == null) {
        throw Exception('Student not logged in');
      }

      // Calculate score
      int correctAnswers = 0;
      List<Map<String, dynamic>> detailedAnswers = [];

      for (int i = 0; i < widget.test.questions.length; i++) {
        final question = widget.test.questions[i];
        final userAnswer = answers[i] ?? '';
        final isCorrect = userAnswer == question.correctAnswer;

        if (isCorrect) {
          correctAnswers++;
        }

        detailedAnswers.add({
          'questionText': question.question,
          'userAnswer': userAnswer,
          'correctAnswer': question.correctAnswer,
          'isCorrect': isCorrect,
        });
      }

      final score = widget.test.questions.isNotEmpty
          ? (correctAnswers / widget.test.questions.length * 100).round()
          : 0;

      // Create test result model
      final testResult = TestResultModel(
        id: '', // Will be auto-generated by Firestore
        testId: widget.test.id,
        testTitle: widget.test.title,
        subject: widget.test.subject,
        studentId: studentId,
        studentName: auth.currentUser?.name ?? 'Unknown',
        studentEmail: studentEmail ?? '',
        score: score.toDouble(),
        totalQuestions: widget.test.questions.length,
        correctAnswers: correctAnswers,
        completedAt: DateTime.now(),
        timeTaken: widget.test.duration - _timeRemaining.inMinutes,
        answers: detailedAnswers,
        wasProctored: true,
        tabSwitchCount: _tabSwitchCount,
        violationDetected: isViolation,
        violationReason: violationReason,
      );

      // Save to Firestore
      await FirestoreService().submitTestResult(testResult);

      if (!mounted) return;

      // Show result dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(isViolation ? 'Test Auto-Submitted' : 'Test Submitted!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isViolation ? Icons.warning : Icons.check_circle,
                color: isViolation ? Colors.orange : Colors.green,
                size: 64,
              ),
              const SizedBox(height: 16),
              if (isViolation && violationReason != null) ...[
                Text(
                  violationReason,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Your Score: $score%',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$correctAnswers out of ${widget.test.questions.length} correct',
              ),
              if (_tabSwitchCount > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '⚠️ Tab switches detected: $_tabSwitchCount',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back to rules screen
                Navigator.pop(context); // Go back to test list
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2800D),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error submitting test: $e')));
      setState(() => _isSubmitting = false);
    }
  }

  void _autoSubmitTest() {
    if (_isSubmitting) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Time is up! Auto-submitting test...')),
    );
    _submitTest();
  }

  void _autoSubmitTestForViolation(String reason) {
    if (_isSubmitting) return;
    _timer?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reason),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        _submitTest(isViolation: true, violationReason: reason);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.test.questions[currentQuestionIndex];
    final progress = (currentQuestionIndex + 1) / widget.test.questions.length;

    return Scaffold(
      backgroundColor: const Color(0xFFFCFAF8),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFCFAF8).withOpacity(0.8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.test.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1C140D),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4EDE7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 20,
                              color: Color(0xFF1C140D),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(_timeRemaining),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1C140D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: const Color(0xFFE8DBCE),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFF2800D),
                    ),
                    minHeight: 4,
                  ),
                ],
              ),
            ),

            // Question Card
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
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
                          Text(
                            'Question ${currentQuestionIndex + 1} of ${widget.test.questions.length}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            question.question,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1C140D),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Options
                          if (question.type == QuestionType.multipleChoice &&
                              question.options != null)
                            ...question.options!.map((option) {
                              final isSelected =
                                  answers[currentQuestionIndex] == option;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildOptionButton(option, isSelected),
                              );
                            }).toList()
                          else
                            // Short answer
                            TextField(
                              decoration: InputDecoration(
                                hintText: 'Type your answer here...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                              ),
                              maxLines: 3,
                              onChanged: (value) {
                                answers[currentQuestionIndex] = value;
                              },
                              controller: TextEditingController(
                                text: answers[currentQuestionIndex] ?? '',
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Progress Dots
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        widget.test.questions.length,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == currentQuestionIndex
                                ? const Color(0xFFF2800D)
                                : const Color(0xFFE8DBCE),
                          ),
                        ),
                      ),
                    ),

                    // Mascot
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFED7AA),
                        shape: BoxShape.circle,
                      ),
                      child: Image.network(
                        'https://lh3.googleusercontent.com/aida-public/AB6AXuAECnMmFhJ1ePsH1b-Lr28Nn9yv2FRIS-xEZQT6ll2luWP_7KHApEZMq_oEemv8HnqRG98HMU965zPk-KTJQRbOJCmHLoqKuxX5LIXrYZzURmwzwajZqoEa0oZzi1zn7gTs6mfIoCBAQhy23auHpmKT0gMNINQMoPGtwgVcoGScTU9tB3dX5CdjdQ_os3nZrRKh29w_L4L1DjUhrBLaKMQce52H5GpQQXy0q5ahkKeAtsubJR4QbEYBh-mljRBkDXkFHBDOIe4Udd0',
                        width: 80,
                        height: 80,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.emoji_emotions,
                            size: 80,
                            color: Color(0xFFF2800D),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer Navigation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFCFAF8).withOpacity(0.8),
                border: const Border(top: BorderSide(color: Color(0xFFE8DBCE))),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: currentQuestionIndex > 0
                              ? _previousQuestion
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Colors.grey),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Previous',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              currentQuestionIndex <
                                  widget.test.questions.length - 1
                              ? _nextQuestion
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFFF2800D)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Next',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFF2800D),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitTest,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFF2800D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 4,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Submit Test',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
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

  Widget _buildOptionButton(String option, bool isSelected) {
    return InkWell(
      onTap: () => _selectAnswer(option),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFF2800D) : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFFB923C), Color(0xFFF97316)],
                )
              : null,
          color: isSelected ? null : Colors.white,
        ),
        child: Text(
          option,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF1C140D),
          ),
        ),
      ),
    );
  }
}
