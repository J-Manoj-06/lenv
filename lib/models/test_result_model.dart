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
  final String studentName;
  final String studentEmail;
  final String testId;
  final String testTitle;
  final String subject;
  final double score;
  final int totalQuestions;
  final int correctAnswers;
  final DateTime completedAt;
  final int timeTaken; // in minutes
  final List<Map<String, dynamic>> answers;
  final bool wasProctored;
  final int tabSwitchCount;
  final bool violationDetected;
  final String? violationReason;

  // Legacy fields for backward compatibility
  final int? totalPoints;
  final double? percentage;
  final List<QuestionResult>? questions;
  final List<String>? badges;
  final SwotSummary? swot;

  TestResultModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    required this.testId,
    required this.testTitle,
    required this.subject,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.completedAt,
    required this.timeTaken,
    required this.answers,
    this.wasProctored = false,
    this.tabSwitchCount = 0,
    this.violationDetected = false,
    this.violationReason,
    this.totalPoints,
    this.percentage,
    this.questions,
    this.badges,
    this.swot,
  });

  factory TestResultModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return TestResultModel(
      id: doc.id,
      studentId: (data['studentId'] ?? '') as String,
      studentName: (data['studentName'] ?? '') as String,
      studentEmail: (data['studentEmail'] ?? '') as String,
      testId: (data['testId'] ?? '') as String,
      testTitle: (data['testTitle'] ?? '') as String,
      subject: (data['subject'] ?? '') as String,
      score: (data['score'] ?? 0).toDouble(),
      totalQuestions: (data['totalQuestions'] ?? 0) as int,
      correctAnswers: (data['correctAnswers'] ?? 0) as int,
      completedAt:
          (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      timeTaken: (data['timeTaken'] ?? 0) as int,
      answers: ((data['answers'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      wasProctored: (data['wasProctored'] ?? false) as bool,
      tabSwitchCount: (data['tabSwitchCount'] ?? 0) as int,
      violationDetected: (data['violationDetected'] ?? false) as bool,
      violationReason: data['violationReason'] as String?,
      // Legacy fields
      totalPoints: data['totalPoints'] as int?,
      percentage: (data['percentage'] as num?)?.toDouble(),
      questions: data['questions'] != null
          ? ((data['questions'] as List)
                .map(
                  (q) => QuestionResult.fromMap(
                    Map<String, dynamic>.from(q as Map),
                  ),
                )
                .toList())
          : null,
      badges: data['badges'] != null
          ? ((data['badges'] as List).map((e) => e.toString()).toList())
          : null,
      swot: data['swot'] != null
          ? SwotSummary.fromMap(data['swot'] as Map<String, dynamic>?)
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'studentId': studentId,
    'studentName': studentName,
    'studentEmail': studentEmail,
    'testId': testId,
    'testTitle': testTitle,
    'subject': subject,
    'score': score,
    'totalQuestions': totalQuestions,
    'correctAnswers': correctAnswers,
    'completedAt': Timestamp.fromDate(completedAt),
    'timeTaken': timeTaken,
    'answers': answers,
    'wasProctored': wasProctored,
    'tabSwitchCount': tabSwitchCount,
    'violationDetected': violationDetected,
    if (violationReason != null) 'violationReason': violationReason,
    // Legacy fields for backward compatibility
    if (totalPoints != null) 'totalPoints': totalPoints,
    if (percentage != null) 'percentage': percentage,
    if (questions != null)
      'questions': questions!.map((q) => q.toMap()).toList(),
    if (badges != null) 'badges': badges,
    if (swot != null) 'swot': swot!.toMap(),
  };
}
