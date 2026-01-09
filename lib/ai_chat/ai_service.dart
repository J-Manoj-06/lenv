import 'dart:io';
import 'ai_quiz_models.dart';

class AiService {
  Future<AIResponse> analyzeDoubt(File image) async {
    await Future.delayed(const Duration(seconds: 1));
    return AIResponse(
      explanation: [
        'Identify given values and what is asked.',
        'Apply the relevant formula step-by-step.',
        'Simplify carefully and verify units.',
      ],
      similarQuestions: [
        'Solve: 2x + 5 = 15',
        'Find area of a triangle with base 6 cm and height 4 cm',
        'Simplify: (a^2 * a^3) / a',
      ],
    );
  }

  Future<AIResponse> analyzeText(String question) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final q = question.trim();
    return AIResponse(
      explanation: [
        'Question: "$q"',
        '1) Identify the key concept involved.',
        '2) Apply the rule or formula.',
        '3) Work through the steps carefully.',
        '4) Check units/logic and state the final answer.',
      ],
      similarQuestions: [
        'Practice: Try a similar problem using the same concept.',
        'Explain: Why does this method work here?',
        'Extend: What changes if one parameter doubles?',
      ],
    );
  }

  Future<AiGeneratedQuiz> generateQuizFromImage(File image) async {
    await Future.delayed(const Duration(seconds: 1));
    final mcqs = List.generate(10, (i) {
      final correct = i % 4;
      final options = List.generate(
        4,
        (j) => AiQuizOption(text: 'Option ${j + 1}', isCorrect: j == correct),
      );
      return AiQuizQuestion(
        questionText: 'MCQ Question ${i + 1}',
        options: options,
        correctIndex: correct,
      );
    });
    final shorts = List.generate(
      5,
      (i) => AiShortAnswerQuestion(
        questionText: 'Short Answer ${i + 1}: What is 2 + ${i + 1}?',
        correctAnswer: '${2 + (i + 1)}',
      ),
    );
    final miniItems = [mcqs[0], shorts[0], mcqs[1], shorts[1], mcqs[2]];

    return AiGeneratedQuiz(
      mcqs: mcqs,
      shortAnswers: shorts,
      miniTest: AiMiniTest(items: miniItems),
    );
  }

  Future<AiGeneratedQuiz> generateQuizFromTopic(String topic) async {
    await Future.delayed(const Duration(milliseconds: 800));
    final t = topic.trim().isEmpty ? 'General Knowledge' : topic.trim();
    final mcqs = List.generate(10, (i) {
      final correct = (i + 1) % 4;
      final options = List.generate(
        4,
        (j) =>
            AiQuizOption(text: '$t - Choice ${j + 1}', isCorrect: j == correct),
      );
      return AiQuizQuestion(
        questionText: '$t - MCQ ${i + 1}',
        options: options,
        correctIndex: correct,
      );
    });
    final shorts = List.generate(
      5,
      (i) => AiShortAnswerQuestion(
        questionText: '$t - Short ${i + 1}: Define the key term.',
        correctAnswer: 'Sample reference answer',
      ),
    );
    final miniItems = [mcqs[0], shorts[0], mcqs[1], shorts[1], mcqs[2]];

    return AiGeneratedQuiz(
      mcqs: mcqs,
      shortAnswers: shorts,
      miniTest: AiMiniTest(items: miniItems),
    );
  }
}
