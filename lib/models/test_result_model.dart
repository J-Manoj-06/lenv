import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionResult {
  final int index;
  final String questionTitle; // e.g., "Question 1"
  final String yourAnswer;
  final String correctAnswer;
  final String notes; // teacher notes
  final bool isCorrect;

  QuestionResult({
    required this.index,
    required this.questionTitle,
    required this.yourAnswer,
    required this.correctAnswer,
    required this.notes,
    required this.isCorrect,
  });

  factory QuestionResult.fromMap(Map<String, dynamic> map) {
    return QuestionResult(
      index: (map['index'] ?? 0) as int,
      questionTitle: (map['questionTitle'] ?? '') as String,
      yourAnswer: (map['yourAnswer'] ?? '') as String,
      correctAnswer: (map['correctAnswer'] ?? '') as String,
      notes: (map['notes'] ?? '') as String,
      isCorrect: (map['isCorrect'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
    'index': index,
    'questionTitle': questionTitle,
    'yourAnswer': yourAnswer,
    'correctAnswer': correctAnswer,
    'notes': notes,
    'isCorrect': isCorrect,
  };
}

class SwotSummary {
  final String strengths;
  final String weaknesses;
  final String opportunities;
  final String threats;

  SwotSummary({
    required this.strengths,
    required this.weaknesses,
    required this.opportunities,
    required this.threats,
  });

  factory SwotSummary.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const {};
    return SwotSummary(
      strengths: (m['strengths'] ?? '') as String,
      weaknesses: (m['weaknesses'] ?? '') as String,
      opportunities: (m['opportunities'] ?? '') as String,
      threats: (m['threats'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() => {
    'strengths': strengths,
    'weaknesses': weaknesses,
    'opportunities': opportunities,
    'threats': threats,
  };
}

class TestResultModel {
  final String id;
  final String studentId;
  final String testId;
  final String testTitle;
  final String subject;
  final int score;
  final int totalPoints;
  final double percentage;
  final DateTime completedAt;
  final List<QuestionResult> questions;
  final List<String> badges; // e.g., ["Math Whiz", "Problem Solver"]
  final SwotSummary swot;

  TestResultModel({
    required this.id,
    required this.studentId,
    required this.testId,
    required this.testTitle,
    required this.subject,
    required this.score,
    required this.totalPoints,
    required this.percentage,
    required this.completedAt,
    required this.questions,
    required this.badges,
    required this.swot,
  });

  factory TestResultModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return TestResultModel(
      id: doc.id,
      studentId: (data['studentId'] ?? '') as String,
      testId: (data['testId'] ?? '') as String,
      testTitle: (data['testTitle'] ?? '') as String,
      subject: (data['subject'] ?? '') as String,
      score: (data['score'] ?? 0) as int,
      totalPoints: (data['totalPoints'] ?? 0) as int,
      percentage: (data['percentage'] ?? 0).toDouble(),
      completedAt:
          (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      questions: ((data['questions'] ?? []) as List)
          .map(
            (q) => QuestionResult.fromMap(Map<String, dynamic>.from(q as Map)),
          )
          .toList(),
      badges: ((data['badges'] ?? []) as List)
          .map((e) => e.toString())
          .toList(),
      swot: SwotSummary.fromMap(data['swot'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'studentId': studentId,
    'testId': testId,
    'testTitle': testTitle,
    'subject': subject,
    'score': score,
    'totalPoints': totalPoints,
    'percentage': percentage,
    'completedAt': Timestamp.fromDate(completedAt),
    'questions': questions.map((q) => q.toMap()).toList(),
    'badges': badges,
    'swot': swot.toMap(),
  };
}
