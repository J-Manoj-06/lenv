/// Test Question Model for AI-Generated Tests
///
/// This model represents a single question in an AI-generated test.
/// Supports multiple choice (MCQ) and true/false question types.
library;

/// Question type for AI-generated questions
enum QuestionTypeAI {
  mcq,
  trueFalse;

  /// Convert from string representation
  static QuestionTypeAI fromString(String type) {
    switch (type.toLowerCase()) {
      case 'mcq':
      case 'multiplechoice':
      case 'multiple_choice':
        return QuestionTypeAI.mcq;
      case 'truefalse':
      case 'true_false':
      case 'tf':
        return QuestionTypeAI.trueFalse;
      default:
        throw ArgumentError('Invalid question type: $type');
    }
  }

  /// Convert to string representation
  String toStringValue() {
    switch (this) {
      case QuestionTypeAI.mcq:
        return 'mcq';
      case QuestionTypeAI.trueFalse:
        return 'truefalse';
    }
  }
}

/// Test question model
class TestQuestion {
  /// Question type (mcq or truefalse)
  final QuestionTypeAI type;

  /// The question text
  final String questionText;

  /// Marks/points for this question
  final int marks;

  /// Options for MCQ questions (null for true/false)
  /// For MCQ: List of 4 options
  final List<String>? options;

  /// Correct answer
  /// For MCQ: 'A', 'B', 'C', or 'D' (option letter)
  /// For True/False: 'true' or 'false' (lowercase)
  final String correctAnswer;

  TestQuestion({
    required this.type,
    required this.questionText,
    required this.marks,
    this.options,
    required this.correctAnswer,
  });

  /// Create from JSON (AI response format)
  factory TestQuestion.fromJson(Map<String, dynamic> json) {
    try {
      final type = QuestionTypeAI.fromString(json['type'] as String);
      final questionText = (json['questionText'] as String).trim();
      final marks = json['marks'] as int;
      final correctAnswer = (json['correctAnswer'] as String).trim();

      List<String>? options;
      if (type == QuestionTypeAI.mcq) {
        if (json['options'] == null) {
          throw FormatException('MCQ question must have options');
        }
        options = (json['options'] as List<dynamic>)
            .map((e) => e.toString().trim())
            .toList();

        if (options.length != 4) {
          throw FormatException('MCQ question must have exactly 4 options');
        }
      }

      return TestQuestion(
        type: type,
        questionText: questionText,
        marks: marks,
        options: options,
        correctAnswer: correctAnswer,
      );
    } catch (e) {
      throw FormatException('Failed to parse TestQuestion: $e\nJSON: $json');
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.toStringValue(),
      'questionText': questionText,
      'marks': marks,
      if (options != null) 'options': options,
      'correctAnswer': correctAnswer,
    };
  }

  /// Convert to Firestore format
  Map<String, dynamic> toFirestore() {
    return {
      'id': questionText.hashCode.toString(), // Generate ID from question text
      'type': type.toStringValue(),
      'questionText': questionText,
      'marks': marks,
      if (options != null) 'options': options,
      'correctAnswer': correctAnswer,
    };
  }

  /// Validate question data
  bool isValid() {
    // Check basic fields
    if (questionText.isEmpty) return false;
    if (marks <= 0) return false;
    if (correctAnswer.isEmpty) return false;

    // Validate MCQ specific fields
    if (type == QuestionTypeAI.mcq) {
      if (options == null || options!.length != 4) return false;
      if (options!.any((opt) => opt.isEmpty)) return false;

      // Validate correct answer is A, B, C, or D
      final validAnswers = ['A', 'B', 'C', 'D'];
      if (!validAnswers.contains(correctAnswer.toUpperCase())) return false;
    }

    // Validate True/False specific fields
    if (type == QuestionTypeAI.trueFalse) {
      if (options != null) return false; // True/false shouldn't have options
      final validAnswers = ['true', 'false'];
      if (!validAnswers.contains(correctAnswer.toLowerCase())) return false;
    }

    return true;
  }

  /// Get normalized question text for duplicate detection
  String get normalizedText {
    return questionText.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Get display text for correct answer
  String get correctAnswerDisplay {
    if (type == QuestionTypeAI.mcq && options != null) {
      final index = _getAnswerIndex();
      if (index >= 0 && index < options!.length) {
        return '${correctAnswer.toUpperCase()}. ${options![index]}';
      }
      return correctAnswer;
    }
    return correctAnswer.toLowerCase() == 'true' ? 'True' : 'False';
  }

  /// Get answer index for MCQ questions
  int _getAnswerIndex() {
    final answer = correctAnswer.toUpperCase();
    switch (answer) {
      case 'A':
        return 0;
      case 'B':
        return 1;
      case 'C':
        return 2;
      case 'D':
        return 3;
      default:
        return -1;
    }
  }

  /// Copy with modifications
  TestQuestion copyWith({
    QuestionTypeAI? type,
    String? questionText,
    int? marks,
    List<String>? options,
    String? correctAnswer,
  }) {
    return TestQuestion(
      type: type ?? this.type,
      questionText: questionText ?? this.questionText,
      marks: marks ?? this.marks,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
    );
  }

  @override
  String toString() {
    return 'TestQuestion(type: ${type.toStringValue()}, text: ${questionText.substring(0, questionText.length > 50 ? 50 : questionText.length)}..., marks: $marks)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TestQuestion &&
        other.type == type &&
        other.normalizedText == normalizedText;
  }

  @override
  int get hashCode {
    return Object.hash(type, normalizedText);
  }
}
