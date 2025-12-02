class DailyChallenge {
  final String question;
  final List<String> options;
  final String correctAnswer;
  final String category;
  final String difficulty;

  DailyChallenge({
    required this.question,
    required this.options,
    required this.correctAnswer,
    required this.category,
    required this.difficulty,
  });

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'options': options,
      'correctAnswer': correctAnswer,
      'category': category,
      'difficulty': difficulty,
    };
  }

  factory DailyChallenge.fromJson(Map<String, dynamic> json) {
    return DailyChallenge(
      question: json['question'] as String,
      options: List<String>.from(json['options'] as List),
      correctAnswer: json['correctAnswer'] as String,
      category: json['category'] as String,
      difficulty: json['difficulty'] as String,
    );
  }
}
