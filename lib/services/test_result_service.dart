import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/test_result.dart';

class TestResultService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Save test result to Firestore (using existing flat structure)
  Future<void> saveTestResult(String studentId, TestResult testResult) async {
    try {
      await _firestore
          .collection('testResults')
          .doc(testResult.testId)
          .set(testResult.toFirestore()..['studentId'] = studentId);
    } catch (e) {
      throw Exception('Failed to save test result: $e');
    }
  }

  // Get recent test results for a student from flat testResults collection
  Future<List<TestResult>> getRecentTestResults(
    String studentId, {
    int limit = 4,
  }) async {
    try {
      // Note: Avoid Firestore composite index requirement by sorting client-side.
      final snapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .limit(50) // fetch a reasonable number, then sort locally
          .get();

      print(
        '📊 Fetched ${snapshot.docs.length} test results for student $studentId',
      );

      final results = snapshot.docs.map((doc) {
        final data = doc.data();
        print(
          '   Test: ${data['testTitle']} - Score: ${data['score']}/${data['totalQuestions']}, Status: ${data['status'] ?? 'completed'}',
        );
        // Normalize numeric fields from Firestore (which may be int or double)
        final total = (data['totalQuestions'] is num)
            ? (data['totalQuestions'] as num).toInt()
            : 0;
        final correct = (data['correctAnswers'] is num)
            ? (data['correctAnswers'] as num).toInt()
            : 0;
        final wrong = total - correct;

        // Map existing structure to our TestResult model
        return TestResult(
          testId: doc.id,
          subject: (data['subject'] ?? 'Unknown').toString(),
          chapter: (data['testTitle'] ?? 'Unknown').toString(),
          score: (data['score'] is num ? (data['score'] as num).toInt() : 0),
          totalQuestions: total,
          correctAnswers: correct,
          wrongAnswers: wrong < 0 ? 0 : wrong,
          timestamp: (() {
            final ts = data['completedAt'];
            if (ts is Timestamp) return ts.millisecondsSinceEpoch;
            if (ts is DateTime) return ts.millisecondsSinceEpoch;
            if (ts is num) return ts.toInt();
            return DateTime.now().millisecondsSinceEpoch;
          })(),
          status: (data['status'] ?? 'completed').toString(),
        );
      }).toList();

      // Sort client-side by timestamp descending and apply limit
      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results.take(limit).toList();
    } catch (e) {
      print('❌ Error fetching test results: $e');
      return [];
    }
  }

  // Get all test results for a specific subject
  Future<List<TestResult>> getTestsBySubject(
    String studentId,
    String subject,
  ) async {
    try {
      // Avoid index requirement by client-side sorting
      final snapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where('subject', isEqualTo: subject)
          .limit(50)
          .get();

      final results = snapshot.docs.map((doc) {
        final data = doc.data();
        final total = (data['totalQuestions'] is num)
            ? (data['totalQuestions'] as num).toInt()
            : 0;
        final correct = (data['correctAnswers'] is num)
            ? (data['correctAnswers'] as num).toInt()
            : 0;
        final wrong = total - correct;
        return TestResult(
          testId: doc.id,
          subject: (data['subject'] ?? 'Unknown').toString(),
          chapter: (data['testTitle'] ?? 'Unknown').toString(),
          score: (data['score'] is num ? (data['score'] as num).toInt() : 0),
          totalQuestions: total,
          correctAnswers: correct,
          wrongAnswers: wrong < 0 ? 0 : wrong,
          timestamp: (() {
            final ts = data['completedAt'];
            if (ts is Timestamp) return ts.millisecondsSinceEpoch;
            if (ts is DateTime) return ts.millisecondsSinceEpoch;
            if (ts is num) return ts.toInt();
            return DateTime.now().millisecondsSinceEpoch;
          })(),
          status: (data['status'] ?? 'completed').toString(),
        );
      }).toList();

      results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return results;
    } catch (e) {
      print('Error fetching tests by subject: $e');
      return [];
    }
  }

  // Calculate subject-wise averages
  Future<Map<String, Map<String, dynamic>>> getSubjectWiseAverages(
    String studentId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .get();

      final tests = snapshot.docs.map((doc) {
        final data = doc.data();
        final total = (data['totalQuestions'] is num)
            ? (data['totalQuestions'] as num).toInt()
            : 0;
        final correct = (data['correctAnswers'] is num)
            ? (data['correctAnswers'] as num).toInt()
            : 0;
        final wrong = total - correct;
        return TestResult(
          testId: doc.id,
          subject: (data['subject'] ?? 'Unknown').toString(),
          chapter: (data['testTitle'] ?? 'Unknown').toString(),
          score: (data['score'] is num ? (data['score'] as num).toInt() : 0),
          totalQuestions: total,
          correctAnswers: correct,
          wrongAnswers: wrong < 0 ? 0 : wrong,
          timestamp: (() {
            final ts = data['completedAt'];
            if (ts is Timestamp) return ts.millisecondsSinceEpoch;
            if (ts is DateTime) return ts.millisecondsSinceEpoch;
            if (ts is num) return ts.toInt();
            return DateTime.now().millisecondsSinceEpoch;
          })(),
          status: (data['status'] ?? 'completed').toString(),
        );
      }).toList();

      final Map<String, List<double>> subjectScores = {};

      for (var test in tests) {
        if (!subjectScores.containsKey(test.subject)) {
          subjectScores[test.subject] = [];
        }
        subjectScores[test.subject]!.add(test.percentage);
      }

      final Map<String, Map<String, dynamic>> averages = {};

      subjectScores.forEach((subject, scores) {
        final average = scores.reduce((a, b) => a + b) / scores.length;
        final highest = scores.reduce((a, b) => a > b ? a : b);
        final lowest = scores.reduce((a, b) => a < b ? a : b);

        averages[subject] = {
          'average': average,
          'testCount': scores.length,
          'highest': highest,
          'lowest': lowest,
        };
      });

      return averages;
    } catch (e) {
      print('Error calculating averages: $e');
      return {};
    }
  }

  // Analyze performance trends
  Future<Map<String, String>> getPerformanceTrend(String studentId) async {
    try {
      // Avoid index requirement by client-side sorting
      final snapshot = await _firestore
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .limit(50)
          .get();

      final tests = snapshot.docs.map((doc) {
        final data = doc.data();
        final total = (data['totalQuestions'] is num)
            ? (data['totalQuestions'] as num).toInt()
            : 0;
        final correct = (data['correctAnswers'] is num)
            ? (data['correctAnswers'] as num).toInt()
            : 0;
        final wrong = total - correct;
        return TestResult(
          testId: doc.id,
          subject: (data['subject'] ?? 'Unknown').toString(),
          chapter: (data['testTitle'] ?? 'Unknown').toString(),
          score: (data['score'] is num ? (data['score'] as num).toInt() : 0),
          totalQuestions: total,
          correctAnswers: correct,
          wrongAnswers: wrong < 0 ? 0 : wrong,
          timestamp: (() {
            final ts = data['completedAt'];
            if (ts is Timestamp) return ts.millisecondsSinceEpoch;
            if (ts is DateTime) return ts.millisecondsSinceEpoch;
            if (ts is num) return ts.toInt();
            return DateTime.now().millisecondsSinceEpoch;
          })(),
          status: (data['status'] ?? 'completed').toString(),
        );
      }).toList();

      tests.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final limited = tests.take(6).toList();

      final Map<String, List<double>> subjectScores = {};

      for (var test in limited) {
        if (!subjectScores.containsKey(test.subject)) {
          subjectScores[test.subject] = [];
        }
        subjectScores[test.subject]!.add(test.percentage);
      }

      final Map<String, String> trends = {};

      subjectScores.forEach((subject, scores) {
        if (scores.length < 2) {
          trends[subject] = 'stable';
          return;
        }

        // Compare recent half vs older half
        final mid = scores.length ~/ 2;
        final recent = scores.sublist(0, mid);
        final older = scores.sublist(mid);

        final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
        final olderAvg = older.reduce((a, b) => a + b) / older.length;

        final diff = recentAvg - olderAvg;

        if (diff > 5) {
          trends[subject] = 'improving';
        } else if (diff < -5) {
          trends[subject] = 'declining';
        } else {
          trends[subject] = 'stable';
        }
      });

      return trends;
    } catch (e) {
      print('Error analyzing trends: $e');
      return {};
    }
  }
}
