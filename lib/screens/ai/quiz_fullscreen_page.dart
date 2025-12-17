import 'package:flutter/material.dart';
import '../../models/quiz_question.dart';

class QuizFullScreenPage extends StatefulWidget {
  final Map<String, dynamic> quizData;
  const QuizFullScreenPage({super.key, required this.quizData});

  @override
  State<QuizFullScreenPage> createState() => _QuizFullScreenPageState();
}

class _QuizFullScreenPageState extends State<QuizFullScreenPage> {
  late List<QuizQuestion> _questions;
  late List<int?> _answers; // selected index per question
  bool _submitted = false;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    final raw = widget.quizData['questions'] as List<dynamic>? ?? [];
    _questions = raw
        .map((e) => QuizQuestion.fromMap(e as Map<String, dynamic>))
        .toList();
    _answers = List<int?>.filled(_questions.length, null);
  }

  void _submit() {
    int s = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_answers[i] != null && _answers[i] == _questions[i].correctIndex) {
        s++;
      }
    }
    setState(() {
      _submitted = true;
      _score = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.quizData['title']?.toString() ?? 'Quiz';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_submitted)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events,
                    color: Colors.green.withOpacity(0.9),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Score: $_score / ${_questions.length}',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                final q = _questions[index];
                return _QuestionCard(
                  question: q,
                  index: index,
                  selected: _answers[index],
                  onSelect: (opt) {
                    if (_submitted) return; // lock after submit
                    setState(() => _answers[index] = opt);
                  },
                  showResult: _submitted,
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - 32,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _submitted
                ? Colors.grey.shade300
                : const Color(0xFFFF8A00),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: _submitted ? null : _submit,
          child: Text(
            _submitted ? 'Submitted' : 'Submit Quiz',
            style: TextStyle(
              color: _submitted ? Colors.black54 : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final QuizQuestion question;
  final int index;
  final int? selected;
  final ValueChanged<int> onSelect;
  final bool showResult;

  const _QuestionCard({
    required this.question,
    required this.index,
    required this.selected,
    required this.onSelect,
    required this.showResult,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Q${index + 1}. ${question.question}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(question.options.length, (optIndex) {
              final optText = question.options[optIndex];
              final isSelected = selected == optIndex;
              final isCorrect = question.correctIndex == optIndex;
              Color borderColor = Colors.white.withOpacity(0.12);
              Color? fillColor;
              IconData? icon;

              if (showResult) {
                if (isCorrect) {
                  borderColor = Colors.green;
                  fillColor = Colors.green.withOpacity(0.15);
                  icon = Icons.check_circle;
                } else if (isSelected && !isCorrect) {
                  borderColor = Colors.red;
                  fillColor = Colors.red.withOpacity(0.15);
                  icon = Icons.cancel;
                }
              } else if (isSelected) {
                borderColor = const Color(0xFFFF8A00);
                fillColor = const Color(0xFFFF8A00).withOpacity(0.15);
              }

              return InkWell(
                onTap: () => onSelect(optIndex),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor, width: 1.4),
                    color: fillColor,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          optText,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (icon != null)
                        Icon(
                          icon,
                          color: icon == Icons.check_circle
                              ? Colors.green
                              : Colors.red,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
