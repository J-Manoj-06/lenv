import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/test_result_model.dart';
import 'dart:math' as math;

class TeacherStudentResultDetailScreen extends StatefulWidget {
  final String resultId;
  final String testId;

  const TeacherStudentResultDetailScreen({
    super.key,
    required this.resultId,
    required this.testId,
  });

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
          if (_questions.isNotEmpty) {}
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading result: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : theme.scaffoldBackgroundColor,
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
        title: _result != null
            ? Text(
                '${_result!.studentName} Performance',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              )
            : Text(
                'Test Results',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                    // Score Ring at top (like student UI)
                    _buildScoreRing(),
                    const SizedBox(height: 16),
                    // Student summary (name, email, completed at, time taken)
                    _buildStudentSummary(),
                    const SizedBox(height: 16),
                    // Compact score card (Score / Correct / Wrong)
                    _buildScoreCard(),
                    const SizedBox(height: 16),
                    _buildAnswersCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildScoreRing() {
    if (_result == null) return const SizedBox.shrink();
    final percentage = _result!.totalQuestions > 0
        ? (_result!.correctAnswers / _result!.totalQuestions) * 100
        : 0.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SizedBox(
        width: 192,
        height: 192,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _RingPainter(
                progress: 1.0,
                color: isDark ? Colors.white12 : Colors.grey.shade300,
                strokeWidth: 10,
              ),
            ),
            CustomPaint(
              painter: _RingPainter(
                progress: (percentage / 100).clamp(0.0, 1.0),
                color: const Color(0xFFF97316),
                strokeWidth: 10,
              ),
            ),
            Center(
              child: Text(
                '${percentage.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentSummary() {
    if (_result == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Text(
            _result!.studentName,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        if (_result!.studentEmail.isNotEmpty)
          Center(
            child: Text(
              _result!.studentEmail,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _infoChip(
              icon: Icons.access_time,
              label: 'Completed',
              value: _formatDateTime(_result!.completedAt),
            ),
            const SizedBox(width: 8),
            _infoChip(
              icon: Icons.timer,
              label: 'Time',
              value: _formatDuration(_result!.timeTaken),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF374151) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label: $value',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Old _buildStudentInfoCard removed (replaced by ring + summary like student UI)

  // Old _buildInfoRow removed (summary uses chips now)

  Widget _buildScoreCard() {
    if (_result == null) return const SizedBox.shrink();

    final percentage = _result!.totalQuestions > 0
        ? (_result!.correctAnswers / _result!.totalQuestions) * 100
        : 0.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildScoreStat(
            'Score',
            '${percentage.toStringAsFixed(1)}%',
            Icons.stars,
            color: const Color(0xFFF97316),
          ),
          _verticalDivider(isDark),
          _buildScoreStat(
            'Correct',
            '${_result!.correctAnswers}/${_result!.totalQuestions}',
            Icons.check_circle,
            color: Colors.green,
          ),
          _verticalDivider(isDark),
          _buildScoreStat(
            'Wrong',
            '${_result!.totalQuestions - _result!.correctAnswers}',
            Icons.cancel,
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreStat(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? (isDark ? Colors.white : Colors.black87);
    final sub = isDark ? Colors.white70 : Colors.black54;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: c, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: sub,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _verticalDivider(bool isDark) => Container(
    width: 1,
    height: 40,
    color: isDark ? const Color(0xFF374151) : Colors.grey.shade300,
  );

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

              // CRITICAL: Match question by questionText, not by index (answers may be shuffled!)
              final questionText = answer['questionText'] ?? '';
              Map<String, dynamic> questionData = {};

              // Find matching question by questionText
              for (var q in _questions) {
                if ((q['questionText'] ?? q['question'] ?? '') ==
                    questionText) {
                  questionData = q;
                  break;
                }
              }

              // Fallback: try to match by index if text match fails
              if (questionData.isEmpty && index < _questions.length) {
                questionData = _questions[index];
              }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final questionText =
        answer['questionText'] ??
        questionData['questionText'] ??
        questionData['question'] ??
        'Question $questionNumber';

    final dynamic userAnswer = _deriveUserAnswer(answer);
    final dynamic correctAnswer = _deriveCorrectAnswer(answer, questionData);

    // CRITICAL: Trust the isCorrect flag stored during test submission
    // Only fallback to inference if flag is missing
    final bool isCorrect = answer.containsKey('isCorrect')
        ? (answer['isCorrect'] == true)
        : _inferCorrectness(userAnswer, correctAnswer);

    // CRITICAL: Use options from the answer (what student actually saw) if available
    List<dynamic> rawOptions =
        (answer['options'] as List?) ??
        (questionData['options'] as List?) ??
        [];
    final questionType =
        (answer['questionType'] ?? questionData['type'] ?? 'mcq')
            .toString()
            .toLowerCase();
    if (rawOptions.isNotEmpty) {}

    // For True/False style questions, create synthetic options if none exist
    if ((questionType == 'tf' ||
            questionType == 'true_false' ||
            questionType == 'boolean') &&
        rawOptions.isEmpty) {
      rawOptions = ['True', 'False'];
    }

    // Normalize options into a consistent list of {label, text}
    final options = _normalizeOptions(rawOptions);

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
                  color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF374151)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  questionText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: isDark ? Colors.white : Colors.black87,
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
            final optionLabel = entry.value['label']!;
            final optionText = entry.value['text']!;

            // Determine if this is the user's answer or correct answer across formats
            final bool isUserAnswer = _matchesAnswer(
              userAnswer,
              optionLabel,
              optionText,
              optionIndex,
            );
            final bool isCorrectOption = _matchesAnswer(
              correctAnswer,
              optionLabel,
              optionText,
              optionIndex,
            );

            // DEBUG: Log matching for first 3 questions to help diagnose issues
            if (questionNumber <= 3) {
              debugPrint(
                'Q$questionNumber Option $optionLabel: '
                'isUser=$isUserAnswer, isCorrect=$isCorrectOption, '
                'userAns=$userAnswer, correctAns=$correctAnswer',
              );
            }

            Color? bgColor;
            Color? borderColor;
            IconData? icon;

            // Production-ready logic for answer display:
            // 1. If this option is BOTH user's answer AND correct → GREEN (user got it right)
            // 2. If this option is user's answer but NOT correct → RED (user's wrong answer)
            // 3. If this option is correct but NOT user's answer → GREEN (show correct answer)
            // 4. Otherwise → neutral (neither selected nor correct)

            if (isUserAnswer && isCorrectOption) {
              // User selected the correct answer - show green
              bgColor = Colors.green.withOpacity(0.2);
              borderColor = Colors.green;
              icon = Icons.check_circle;
            } else if (isUserAnswer && !isCorrectOption) {
              // User selected wrong answer - show red
              bgColor = Colors.red.withOpacity(0.2);
              borderColor = Colors.red;
              icon = Icons.cancel;
            } else if (!isUserAnswer && isCorrectOption) {
              // This is the correct answer but user didn't select it - show green
              bgColor = Colors.green.withOpacity(0.2);
              borderColor = Colors.green;
              icon = Icons.check_circle;
            }
            // else: neutral - neither selected nor correct

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:
                      bgColor ??
                      (isDark ? const Color(0xFF111827) : Colors.white),
                  border: Border.all(
                    color:
                        borderColor ??
                        (isDark
                            ? const Color(0xFF374151)
                            : Colors.grey.shade300),
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
                        color:
                            borderColor ??
                            (isDark
                                ? const Color(0xFF4B5563)
                                : Colors.grey.shade200),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          optionLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: borderColor != null
                                ? Colors.white
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        optionText,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: borderColor != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: borderColor != null
                              ? (borderColor == Colors.green
                                    ? (isDark
                                          ? Colors.white
                                          : Colors.green.shade900)
                                    : (isDark
                                          ? Colors.white
                                          : Colors.red.shade900))
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    if (icon != null) Icon(icon, color: borderColor, size: 24),
                  ],
                ),
              ),
            );
          }),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Expanded(
            child: Text(
              answer,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
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

  // Extract user answer from multiple possible keys
  dynamic _deriveUserAnswer(Map<String, dynamic> answer) {
    final keys = [
      'userAnswer',
      'selectedAnswer',
      'selectedOption',
      'selectedLabel',
      'selected',
      'userOption',
      'userLabel',
      'userIndex',
      'selectedIndex',
      'answer', // Sometimes stored as just 'answer'
      'studentAnswer',
      'choice',
    ];
    dynamic val;
    for (final k in keys) {
      if (answer.containsKey(k) && answer[k] != null) {
        val = answer[k];
        break;
      }
    }
    return _coerceAnswerValue(val);
  }

  // Extract correct answer - Use stored answer first (it has the correct text from student's view)
  dynamic _deriveCorrectAnswer(
    Map<String, dynamic> answer,
    Map<String, dynamic> question,
  ) {
    // CRITICAL: First check if correctAnswer is stored in the result
    // This is the correct answer TEXT that the student saw (from their shuffled options)
    if (answer.containsKey('correctAnswer') &&
        answer['correctAnswer'] != null) {
      return _coerceAnswerValue(answer['correctAnswer']);
    }

    // Fallback: try to derive from question data (less reliable if options were shuffled)
    final qKeys = [
      'correctAnswer',
      'answer',
      'correctOption',
      'correctLabel',
      'correctIndex',
      'correct_index',
    ];
    dynamic val;
    for (final k in qKeys) {
      if (question.containsKey(k) && question[k] != null) {
        val = question[k];
        break;
      }
    }

    if (val == null) {
      return null;
    }

    // If val is a letter (A/B/C/D) and we have options, resolve to option text
    if (val is String && val.trim().length == 1) {
      final letter = val.trim().toUpperCase();
      final index = letter.codeUnitAt(0) - 65; // A=0, B=1, etc
      final opts = question['options'] as List?;
      if (opts != null && index >= 0 && index < opts.length) {
        final resolved = opts[index];
        return _coerceAnswerValue(resolved);
      }
    }

    return _coerceAnswerValue(val);
  }

  dynamic _coerceAnswerValue(dynamic v) {
    if (v == null) return null;
    // If it's numeric string, parse
    if (v is String) {
      final s = v.trim();
      if (RegExp(r'^\d+$').hasMatch(s)) {
        return int.tryParse(s);
      }
      return _normalizeText(s);
    }
    return v; // keep num/bool/list as-is
  }

  bool _inferCorrectness(dynamic user, dynamic correct) {
    if (user == null || correct == null) return false;
    if (user is String && correct is String) {
      return user.trim().toLowerCase() == correct.trim().toLowerCase();
    }
    if (user is num && correct is num) return user == correct;
    return false;
  }

  // Normalize various option shapes into a consistent {label, text} list
  List<Map<String, String>> _normalizeOptions(dynamic rawOptions) {
    final List<Map<String, String>> out = [];

    // If options came as a map like {A: '...', B: '...'}
    if (rawOptions is Map) {
      int i = 0;
      rawOptions.forEach((k, v) {
        final label = k.toString().trim().toUpperCase();
        final text = _normalizeText(v?.toString() ?? '');
        out.add({
          'label': label.isNotEmpty ? label : String.fromCharCode(65 + i),
          'text': text,
        });
        i++;
      });
      return out;
    }

    if (rawOptions is! List) return out;

    for (int i = 0; i < rawOptions.length; i++) {
      final opt = rawOptions[i];
      String text = '';
      String? label;

      if (opt is Map) {
        final dynamic picked =
            opt['text'] ??
            opt['option'] ??
            opt['value'] ??
            opt['answer'] ??
            opt['title'] ??
            opt.values.firstWhere(
              (v) => v is String && v.trim().isNotEmpty,
              orElse: () => '',
            );
        text = _normalizeText(picked?.toString() ?? '');
        final rawLabel = opt['label'];
        if (rawLabel is String && rawLabel.trim().isNotEmpty) {
          label = rawLabel.trim();
        }
      } else {
        text = _normalizeText(opt?.toString() ?? '');
      }

      final computedLabel = (label ?? String.fromCharCode(65 + i))
          .toUpperCase();
      out.add({'label': computedLabel, 'text': text});
    }
    return out;
  }

  String _normalizeText(String s) {
    // Replace smart quotes and trim
    return s
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('’', "'")
        .trim();
  }

  // STRICT comparison: only exact matches to prevent false positives
  bool _matchesAnswer(dynamic ans, String label, String text, int index) {
    if (ans == null) return false;

    // If it's a list (multi-select), match any
    if (ans is Iterable) {
      for (final a in ans) {
        if (_matchesAnswer(a, label, text, index)) return true;
      }
      return false;
    }

    // If it's a number, check both against index AND against numeric value in text
    if (ans is num) {
      final i = ans.toInt();
      // Check if matches index (0-based or 1-based)
      if (i == index || i == index + 1) return true;
      // Also check if the text itself represents this number
      if (text.trim() == i.toString()) return true;
      // Try parsing text as number and compare
      final parsedText = int.tryParse(text.trim());
      if (parsedText != null && parsedText == i) return true;
      return false;
    }

    // Booleans for True/False
    if (ans is bool) {
      final s = ans ? 'true' : 'false';
      final normText = text.toLowerCase().trim();
      return normText == s;
    }

    // Strings: compare to label or text, normalize format
    final s = ans.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'not answered') return false;

    final normS = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final normText = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Direct label match (A/B/C/D) - STRICT: only if answer is EXACTLY the letter
    if (s.length == 1 && s.toUpperCase() == label) return true;

    // Exact text match (case-insensitive, punctuation-normalized) - MUST BE EXACT
    if (normS == normText) return true;

    // REMOVED: Similarity matching (was causing false positives)
    // Only exact matches are allowed now

    // Extract leading label like "A.", "A)", "(A)" or "A :" - but require exact match
    final m = RegExp(r'^[\(\s]*([A-Da-d])[\)\.:\s]').firstMatch(s);
    if (m != null) {
      final extracted = m.group(1)!.toUpperCase();
      if (extracted == label) {
        // Verify the rest of the string matches too if present
        final restOfAnswer = s.substring(m.end).trim();
        if (restOfAnswer.isEmpty || normS == normText) {
          return true;
        }
      }
    }

    // Handle true/false words - STRICT match only
    final lowerS = s.toLowerCase();
    final lowerText = text.toLowerCase();
    if ((lowerS == 'true' || lowerS == 'false') &&
        (lowerText == 'true' || lowerText == 'false')) {
      return lowerS == lowerText;
    }

    return false;
  }
}

// Painter for the circular score ring (mirrors student UI)
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
