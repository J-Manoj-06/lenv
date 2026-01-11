import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import 'dart:async';
import '../../utils/visibility_stub.dart'
    if (dart.library.html) '../../utils/visibility_web.dart'
    as vis;
import '../../services/badge_service.dart';
import '../../services/badge_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TakeTestScreen extends StatefulWidget {
  final TestModel test;

  const TakeTestScreen({super.key, required this.test});

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
  // Shuffled question list specific to this student
  List<Question> _questions = [];
  // Per-question shuffled options cached by index in _questions
  final Map<int, List<String>> _shuffledOptions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Calculate remaining time from test end time minus current time
    final now = DateTime.now();
    final testEnd = widget.test.endDate;
    final remainingDuration = testEnd.difference(now);

    // Use remaining time or full duration, whichever is smaller
    if (remainingDuration.isNegative) {
      _timeRemaining = Duration.zero;
    } else {
      final fullDuration = Duration(minutes: widget.test.duration);
      _timeRemaining = remainingDuration < fullDuration
          ? remainingDuration
          : fullDuration;
    }
    _startTimer();
    _initQuestions();
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

  Future<void> _initQuestions() async {
    // Start with original order until loaded
    _questions = List<Question>.from(widget.test.questions);
    setState(() {});

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final studentId = auth.currentUser?.uid;
      if (studentId == null) return;
      final testId = widget.test.id;
      final qs = await FirebaseFirestore.instance
          .collection('testResults')
          .where('testId', isEqualTo: testId)
          .where('studentId', isEqualTo: studentId)
          .limit(1)
          .get();
      if (qs.docs.isEmpty) {
        // No assignment doc yet (unlikely) – generate and abort
        final order = List<int>.generate(_questions.length, (i) => i)
          ..shuffle();
        _questions = order.map((i) => widget.test.questions[i]).toList();
        _prepareShuffledOptions();
        setState(() {});
        return;
      }
      final doc = qs.docs.first;
      final data = doc.data();
      List<dynamic>? orderRaw = data['questionOrder'] as List<dynamic>?;
      if (orderRaw == null || orderRaw.length != widget.test.questions.length) {
        // Create and persist a new order if missing or size mismatch
        final newOrder = List<int>.generate(
          widget.test.questions.length,
          (i) => i,
        )..shuffle();
        await doc.reference.update({'questionOrder': newOrder});
        _questions = newOrder.map((i) => widget.test.questions[i]).toList();
        _prepareShuffledOptions();
      } else {
        final indices = orderRaw.map((e) => (e as num).toInt()).toList();
        _questions = indices.map((i) => widget.test.questions[i]).toList();
        _prepareShuffledOptions();
      }
      setState(() {});
    } catch (e) {
      // Fallback: keep original order
      _prepareShuffledOptions();
      setState(() {});
    }
  }

  void _prepareShuffledOptions() {
    _shuffledOptions.clear();
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      if (q.options != null && q.options!.isNotEmpty) {
        final copy = List<String>.from(q.options!);
        copy.shuffle();
        _shuffledOptions[i] = copy;
      }
    }
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
    if (currentQuestionIndex < _questions.length - 1) {
      setState(() {
        currentQuestionIndex++;
      });
    }
  }

  Future<void> _submitTest({
    bool isViolation = false,
    String? violationReason,
    bool force = false, // when true, skip confirmation dialog
  }) async {
    if (_isSubmitting) return;

    // Confirm submission only if not a violation and not forced
    if (!isViolation && !force) {
      final shouldSubmit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _buildSubmitConfirmationDialog(),
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

      // Calculate score using shuffled per-student questions
      int correctAnswers = 0;
      int totalMarksEarned = 0; // Actual marks based on question points
      List<Map<String, dynamic>> detailedAnswers = [];

      for (int i = 0; i < _questions.length; i++) {
        final question = _questions[i];
        final userAnswerRaw = answers[i] ?? '';
        final userAnswer = userAnswerRaw.trim();
        final correctRaw = (question.correctAnswer ?? '').trim();

        bool isCorrect = false;

        // Multiple Choice logic: handle letter code (A-D), index (0-3 / 1-4), or direct text match
        if (question.type == QuestionType.multipleChoice &&
            question.options != null) {
          final options = question.options!;
          final upper = correctRaw.toUpperCase();
          // If stored as letter A-D
          if (upper.length == 1 &&
              upper.codeUnitAt(0) >= 65 &&
              upper.codeUnitAt(0) <= 68) {
            final idx = upper.codeUnitAt(0) - 65; // A->0
            if (idx >= 0 && idx < options.length) {
              final expectedText = options[idx].trim();
              if (userAnswer.toLowerCase() == expectedText.toLowerCase() ||
                  userAnswer.toUpperCase() == upper) {
                isCorrect = true;
              }
            }
          } else {
            // If stored as numeric index (0-based or 1-based)
            final numeric = int.tryParse(correctRaw);
            if (numeric != null) {
              // Accept both 0-based and 1-based
              final possibleIdxs = <int>{numeric, numeric - 1};
              for (final idx in possibleIdxs) {
                if (idx >= 0 && idx < options.length) {
                  final expectedText = options[idx].trim();
                  if (userAnswer.toLowerCase() == expectedText.toLowerCase()) {
                    isCorrect = true;
                    break;
                  }
                }
              }
            }
            // Direct text match fallback
            if (!isCorrect) {
              if (userAnswer.toLowerCase() == correctRaw.toLowerCase()) {
                isCorrect = true;
              }
            }
          }
        } else if (question.type == QuestionType.trueFalse) {
          // True/False: case-insensitive comparison; allow variations (True/true)
          if (userAnswer.toLowerCase() == correctRaw.toLowerCase()) {
            isCorrect = true;
          }
        } else {
          // Short answer / other types: simple case-insensitive comparison
          if (userAnswer.isNotEmpty &&
              userAnswer.toLowerCase() == correctRaw.toLowerCase()) {
            isCorrect = true;
          }
        }

        if (isCorrect) {
          correctAnswers++;
          totalMarksEarned +=
              question.points; // Add actual points for this question
        }

        // Store a normalized correct answer text for MCQ letter codes so teacher view is clearer
        String storedCorrectAnswer = correctRaw;
        if (question.type == QuestionType.multipleChoice &&
            question.options != null) {
          final upper = correctRaw.toUpperCase();
          if (upper.length == 1 &&
              upper.codeUnitAt(0) >= 65 &&
              upper.codeUnitAt(0) <= 68) {
            final idx = upper.codeUnitAt(0) - 65;
            if (idx >= 0 && idx < question.options!.length) {
              storedCorrectAnswer = question.options![idx].trim();
            }
          }
        }

        detailedAnswers.add({
          'questionText': question.question,
          'userAnswer': userAnswer,
          'correctAnswer': storedCorrectAnswer,
          'rawCorrectAnswer': correctRaw, // keep original for debugging
          'isCorrect': isCorrect,
        });
      }

      final score = _questions.isNotEmpty
          ? (correctAnswers / _questions.length * 100).round()
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
        totalQuestions: _questions.length,
        correctAnswers: correctAnswers,
        completedAt: DateTime.now(),
        timeTaken: widget.test.duration - _timeRemaining.inMinutes,
        answers: detailedAnswers,
        wasProctored: true,
        tabSwitchCount: _tabSwitchCount,
        violationDetected: isViolation,
        violationReason: violationReason,
        totalPoints: totalMarksEarned, // Pass actual marks earned
      );

      // Save to Firestore
      await FirestoreService().submitTestResult(
        testResult,
        testEndDate: widget.test.endDate,
      );

      // Award badges ONLY if test has ended (not during active period)
      final now = DateTime.now();
      final testHasEnded = now.isAfter(widget.test.endDate);

      if (testHasEnded) {
        try {
          // Get total tests completed by this student
          final allResults = await FirestoreService()
              .getTestResultsByStudent(studentId)
              .first;
          final testsCompleted = allResults.length;

          // Get previous test score for improvement calculation
          int? previousScorePercent;
          if (allResults.length > 1) {
            // Sort by completion date and get second-to-last
            final sorted = allResults.toList()
              ..sort((a, b) => a.completedAt.compareTo(b.completedAt));
            if (sorted.length >= 2) {
              previousScorePercent = sorted[sorted.length - 2].score.round();
            }
          }

          final rules = BadgeRules(BadgeService());
          await rules.onTestCompleted(
            studentId: studentId,
            testId: widget.test.id,
            scorePercent: score,
            testsCompleted: testsCompleted,
            previousScorePercent: previousScorePercent,
          );
        } catch (e) {
        }
      } else {
      }

      if (!mounted) return;

      // Handle post-submission UX
      if (isViolation) {
        // For violations: no dialog, immediate redirect
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/student-dashboard',
            (route) => false,
          );
        }
      } else {
        // Normal submission: show confirmation dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final now = DateTime.now();
            final showScore = now.isAfter(widget.test.endDate);
            return AlertDialog(
              title: const Text('Test Submitted!'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  if (showScore) ...[
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
                  ] else ...[
                    const Text(
                      '✅ Test submitted successfully. Results will be available after the test ends.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
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
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/student-dashboard',
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF2800D),
                  ),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      }
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
    _timer?.cancel();
    // Show a popup informing time is up, then auto-submit without confirmation
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Time Ended'),
          content: const Text(
            'The test time limit has ended. Your answers will be auto-submitted now.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _submitTest(force: true);
    });
  }

  Future<void> _autoSubmitTestForViolation(String reason) async {
    if (_isSubmitting) return;
    _timer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reason),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
        // Submit (treated as violation). After submission we will navigate.
        await _submitTest(isViolation: true, violationReason: reason);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalQuestions = _questions.length;
    final question = totalQuestions > 0 && currentQuestionIndex < totalQuestions
        ? _questions[currentQuestionIndex]
        : null;
    final progress = totalQuestions == 0
        ? 0.0
        : (currentQuestionIndex + 1) / totalQuestions;

    return WillPopScope(
      onWillPop: () async {
        // Confirm exiting test -> auto submit
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit Test?'),
            content: const Text(
              'Going back will auto submit your test immediately. Are you sure you want to exit?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2800D),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exit & Submit'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _autoSubmitTestForViolation('Exited test early');
        }
        // Prevent default pop; navigation handled after submission
        return false;
      },
      child: Scaffold(
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
                              'Question ${currentQuestionIndex + 1} of $totalQuestions',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (question != null)
                              Text(
                                question.question,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1C140D),
                                ),
                              ),
                            const SizedBox(height: 24),

                            // Options for MCQ
                            if (question != null &&
                                question.type == QuestionType.multipleChoice &&
                                question.options != null) ...[
                              ...(_shuffledOptions[currentQuestionIndex] ??
                                      question.options!)
                                  .map((option) {
                                    final isSelected =
                                        answers[currentQuestionIndex] == option;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: _buildOptionButton(
                                        option,
                                        isSelected,
                                      ),
                                    );
                                  }),
                              // Clear Response Button for MCQ
                              if (answers.containsKey(currentQuestionIndex))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        answers.remove(currentQuestionIndex);
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Clear Response',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                            ] else if (question != null &&
                                question.type == QuestionType.trueFalse) ...[
                              // True/False options
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildOptionButton(
                                  'True',
                                  answers[currentQuestionIndex] == 'True',
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildOptionButton(
                                  'False',
                                  answers[currentQuestionIndex] == 'False',
                                ),
                              ),
                              // Clear Response Button for True/False
                              if (answers.containsKey(currentQuestionIndex))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        answers.remove(currentQuestionIndex);
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Clear Response',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                            ] else ...[
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
                              // Clear Response Button for Text Field
                              if (answers.containsKey(currentQuestionIndex) &&
                                  answers[currentQuestionIndex]!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        answers.remove(currentQuestionIndex);
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.clear,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'Clear Response',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),

                      // Progress Dots
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          totalQuestions,
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
                        width: 96,
                        height: 96,
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFED7AA),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: Image.network(
                            'https://lh3.googleusercontent.com/aida-public/AB6AXuAECnMmFhJ1ePsH1b-Lr28Nn9yv2FRIS-xEZQT6ll2luWP_7KHApEZMq_oEemv8HnqRG98HMU965zPk-KTJQRbOJCmHLoqKuxX5LIXrYZzURmwzwajZqoEa0oZzi1zn7gTs6mfIoCBAQhy23auHpmKT0gMNINQMoPGtwgVcoGScTU9tB3dX5CdjdQ_os3nZrRKh29w_L4L1DjUhrBLaKMQce52H5GpQQXy0q5ahkKeAtsubJR4QbEYBh-mljRBkDXkFHBDOIe4Udd0',
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.emoji_emotions,
                                size: 64,
                                color: Color(0xFFF2800D),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer Navigation - Always visible
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(
                    top: BorderSide(color: Color(0xFFE8DBCE)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                              side: BorderSide(
                                color: currentQuestionIndex > 0
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade300,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Previous',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: currentQuestionIndex > 0
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: currentQuestionIndex < totalQuestions - 1
                                ? _nextQuestion
                                : null,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor:
                                  currentQuestionIndex < totalQuestions - 1
                                  ? const Color(0xFFF2800D)
                                  : Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              disabledBackgroundColor: Colors.grey.shade300,
                            ),
                            child: Text(
                              'Next',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: currentQuestionIndex < totalQuestions - 1
                                    ? Colors.white
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Submit Test button - Always visible
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitTest,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: const Color(0xFFF2800D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
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

  Widget _buildSubmitConfirmationDialog() {
    final attemptedCount = answers.length;
    final totalCount = _questions.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main content section
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    // Lightbulb icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2800D).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/teddy_bear.png',
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.lightbulb,
                                size: 48,
                                color: Color(0xFFF2800D),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    const Text(
                      'Ready to Submit?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // Description
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF6B7280),
                        ),
                        children: [
                          const TextSpan(text: "You've attempted "),
                          TextSpan(
                            text: '$attemptedCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const TextSpan(text: ' out of '),
                          TextSpan(
                            text: '$totalCount',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const TextSpan(text: ' questions.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Progress bar
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            height: 8,
                            child: LinearProgressIndicator(
                              value: attemptedCount / totalCount,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFF2800D),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Make sure you've reviewed your answers before submitting.",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF6B7280),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Warning text
                    const Text(
                      "Once submitted, you can't change your answers.",
                      style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // Buttons section
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey.shade200.withOpacity(0.6),
                    ),
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Cancel button
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(
                            color: Color(0xFFF2800D),
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF2800D),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Confirm button
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF8A00), Color(0xFFFF6A00)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF97316).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 20,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Confirm &\nSubmit',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            ],
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
      ),
    );
  }
}
