// Example: How to save test results to Firebase
// Add this code after a student completes a test

import 'package:new_reward/models/test_result.dart';
import 'package:new_reward/services/test_result_service.dart';

class TestCompletionHelper {
  final TestResultService _testService = TestResultService();

  /// Call this method when a student submits a test
  Future<void> saveTestResult({
    required String studentId,
    required String subject,
    required String chapter,
    required int score,
    required int totalQuestions,
    required int correctAnswers,
    required int wrongAnswers,
  }) async {
    try {
      // Create test result object
      final testResult = TestResult(
        testId: 'test_${DateTime.now().millisecondsSinceEpoch}',
        subject: subject,
        chapter: chapter,
        score: score,
        totalQuestions: totalQuestions,
        correctAnswers: correctAnswers,
        wrongAnswers: wrongAnswers,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Save to Firestore
      await _testService.saveTestResult(studentId, testResult);
    } catch (e) {
      rethrow;
    }
  }

  /// Example: Generate dummy test data for testing insights
  Future<void> generateDummyTestData(String studentId) async {
    final subjects = ['Mathematics', 'Science', 'English', 'Social Studies'];
    final random = DateTime.now().millisecond;

    for (int i = 0; i < 5; i++) {
      final subject = subjects[i % subjects.length];
      final score = 5 + (random + i * 13) % 6; // Score between 5-10

      await saveTestResult(
        studentId: studentId,
        subject: subject,
        chapter: 'Chapter ${i + 1}',
        score: score,
        totalQuestions: 10,
        correctAnswers: score,
        wrongAnswers: 10 - score,
      );

      // Wait a bit to get different timestamps
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}

// USAGE IN YOUR TEST SCREEN:
//
// After student completes test:
//
// final helper = TestCompletionHelper();
// await helper.saveTestResult(
//   studentId: currentUser.uid,
//   subject: 'Mathematics',
//   chapter: 'Algebra',
//   score: studentScore,
//   totalQuestions: questionsList.length,
//   correctAnswers: correctCount,
//   wrongAnswers: wrongCount,
// );
//
// For testing insights (run once):
//
// await helper.generateDummyTestData(currentUser.uid);
