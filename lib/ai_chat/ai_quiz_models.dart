class AiQuizOption {
  final String text;
  bool isCorrect;
  bool isSelected;

  AiQuizOption({
    required this.text,
    this.isCorrect = false,
    this.isSelected = false,
  });
}

class AiQuizQuestion {
  final String questionText;
  final List<AiQuizOption> options;
  final int correctIndex;
  int? selectedIndex;

  AiQuizQuestion({
    required this.questionText,
    required this.options,
    required this.correctIndex,
    this.selectedIndex,
  });
}

class AiShortAnswerQuestion {
  final String questionText;
  final String correctAnswer;
  String? userAnswer;
  bool? isCorrect;

  AiShortAnswerQuestion({
    required this.questionText,
    required this.correctAnswer,
    this.userAnswer,
    this.isCorrect,
  });
}

class AiMiniTest {
  final List<dynamic> items; // mix of AiQuizQuestion and AiShortAnswerQuestion
  AiMiniTest({required this.items});
}

class AiGeneratedQuiz {
  final List<AiQuizQuestion> mcqs;
  final List<AiShortAnswerQuestion> shortAnswers;
  final AiMiniTest miniTest;

  AiGeneratedQuiz({
    required this.mcqs,
    required this.shortAnswers,
    required this.miniTest,
  });
}

class AIResponse {
  final List<String> explanation;
  final List<String> similarQuestions;

  AIResponse({required this.explanation, required this.similarQuestions});
}
