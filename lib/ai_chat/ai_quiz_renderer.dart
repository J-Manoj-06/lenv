import 'package:flutter/material.dart';
import 'ai_quiz_models.dart';

class AiQuizRenderer extends StatefulWidget {
  final AiGeneratedQuiz quiz;
  const AiQuizRenderer({super.key, required this.quiz});

  @override
  State<AiQuizRenderer> createState() => _AiQuizRendererState();
}

class _AiQuizRendererState extends State<AiQuizRenderer> {
  static const green = Color(0xFF28C76F);
  static const red = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('MCQs (tap once)'),
        ...widget.quiz.mcqs.map(_mcqTile),
        const SizedBox(height: 16),
        _sectionTitle('Short Answers'),
        ...widget.quiz.shortAnswers.map(_shortAnswerTile),
        const SizedBox(height: 16),
        _sectionTitle('Mini Test'),
        ...widget.quiz.miniTest.items.map((item) {
          if (item is AiQuizQuestion) return _mcqTile(item);
          if (item is AiShortAnswerQuestion) return _shortAnswerTile(item);
          return const SizedBox.shrink();
        }),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
  );

  Widget _mcqTile(AiQuizQuestion q) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q.questionText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...List.generate(q.options.length, (index) {
              final opt = q.options[index];
              final isSelected = q.selectedIndex == index;
              Color bg = Colors.grey.shade200;
              if (q.selectedIndex != null) {
                bg = opt.isCorrect ? green : (isSelected ? red : bg);
              }
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  title: Text(opt.text),
                  onTap: () {
                    if (q.selectedIndex != null) return; // one attempt
                    setState(() {
                      q.selectedIndex = index;
                      for (var o in q.options) {
                        o.isSelected = false;
                      }
                      opt.isSelected = true;
                    });
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _shortAnswerTile(AiShortAnswerQuestion q) {
    final controller = TextEditingController(text: q.userAnswer);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              q.questionText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Your answer'),
              onChanged: (v) => q.userAnswer = v,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      q.isCorrect =
                          (q.userAnswer ?? '').trim().toLowerCase() ==
                          q.correctAnswer.trim().toLowerCase();
                    });
                  },
                  child: const Text('Check'),
                ),
                const SizedBox(width: 12),
                if (q.isCorrect != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: q.isCorrect! ? green : red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      q.isCorrect! ? 'Correct' : 'Wrong',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
