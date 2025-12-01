class TestResult {
  final String testId;
  final String subject;
  final String chapter;
  final int score;
  final int totalQuestions;
  final int correctAnswers;
  final int wrongAnswers;
  final int timestamp;

  TestResult({
    required this.testId,
    required this.subject,
    required this.chapter,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.timestamp,
  });

  // Convert from Firestore document
  factory TestResult.fromFirestore(Map<String, dynamic> data, String testId) {
    return TestResult(
      testId: testId,
      subject: data['subject'] ?? '',
      chapter: data['chapter'] ?? '',
      score: data['score'] ?? 0,
      totalQuestions: data['totalQuestions'] ?? 0,
      correctAnswers: data['correctAnswers'] ?? 0,
      wrongAnswers: data['wrongAnswers'] ?? 0,
      timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'subject': subject,
      'chapter': chapter,
      'score': score,
      'totalQuestions': totalQuestions,
      'correctAnswers': correctAnswers,
      'wrongAnswers': wrongAnswers,
      'timestamp': timestamp,
    };
  }

  // Calculate percentage
  double get percentage {
    if (totalQuestions == 0) return 0.0;
    return (score / totalQuestions) * 100;
  }

  // Get performance grade
  String get grade {
    final perc = percentage;
    if (perc >= 90) return 'A+';
    if (perc >= 80) return 'A';
    if (perc >= 70) return 'B';
    if (perc >= 60) return 'C';
    if (perc >= 50) return 'D';
    return 'F';
  }
}
