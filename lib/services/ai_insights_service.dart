import '../models/test_result.dart';
import 'deepseek_service.dart';

class InsightResult {
  final String text;
  final Map<String, double> subjectAverages;

  InsightResult({required this.text, required this.subjectAverages});
}

class AiInsightsService {
  final DeepSeekService _deepSeekService = DeepSeekService();

  // Generate smart insights based on test results using DeepSeek AI
  Future<InsightResult> generateSmartInsights(List<TestResult> results) async {
    if (results.isEmpty) {
      return InsightResult(
        text:
            "No test data available yet. Take some tests to see your performance insights!",
        subjectAverages: {},
      );
    }

    // Separate attempted vs not attempted tests
    final attemptedTests = results.where((test) => test.isAttempted).toList();
    final notAttemptedTests = results
        .where((test) => !test.isAttempted)
        .toList();

    for (var test in results) {
    }

    if (attemptedTests.isEmpty) {
      return InsightResult(
        text:
            "You have ${notAttemptedTests.length} assigned test(s) that you haven't attempted yet. Start taking tests to track your performance!",
        subjectAverages: {},
      );
    }

    if (attemptedTests.length == 1 && notAttemptedTests.isEmpty) {
      final test = attemptedTests.first;
      return InsightResult(
        text:
            "You scored ${test.percentage.toStringAsFixed(1)}% in ${test.subject}. Keep taking tests to track your progress!",
        subjectAverages: {test.subject: test.percentage},
      );
    }

    // Prepare data for AI analysis - only attempted tests
    final Map<String, List<double>> subjectScores = {};
    final Map<String, List<String>> subjectGrades = {};
    final Map<String, List<bool>> subjectAttemptStatus = {};

    // Process ALL results (attempted + not attempted) to track patterns
    for (var test in results) {
      if (!subjectScores.containsKey(test.subject)) {
        subjectScores[test.subject] = [];
        subjectGrades[test.subject] = [];
        subjectAttemptStatus[test.subject] = [];
      }

      if (test.isAttempted) {
        // Cap percentages at 100% to handle data errors
        final cappedPercentage = test.percentage.clamp(0.0, 100.0);
        subjectScores[test.subject]!.add(cappedPercentage);
        subjectGrades[test.subject]!.add(test.grade);
        subjectAttemptStatus[test.subject]!.add(true);
      } else {
        // Mark as not attempted
        subjectAttemptStatus[test.subject]!.add(false);
      }
    }

    // Calculate subject averages (only from attempted tests)
    final Map<String, double> subjectAverages = {};
    subjectScores.forEach((subject, scores) {
      if (scores.isNotEmpty) {
        subjectAverages[subject] =
            scores.reduce((a, b) => a + b) / scores.length;
      }
    });

    // Build concise context for DeepSeek
    String context = "Student performance (last ${results.length} tests):\n";

    subjectScores.forEach((subject, scores) {
      if (scores.isNotEmpty) {
        final avg = scores.reduce((a, b) => a + b) / scores.length;
        final latest = scores.first;
        final totalTests = subjectAttemptStatus[subject]!.length;
        final attemptedCount = subjectAttemptStatus[subject]!
            .where((x) => x)
            .length;
        final notAttemptedCount = totalTests - attemptedCount;

        context +=
            "$subject: Avg ${avg.toStringAsFixed(0)}%, Latest ${latest.toStringAsFixed(0)}%";
        if (notAttemptedCount > 0) {
          context += " ($notAttemptedCount skipped)";
        }
        context += "\n";
      }
    });

    // Add non-attempted subjects
    subjectAttemptStatus.forEach((subject, statuses) {
      if (statuses.every((x) => !x)) {
        context += "$subject: Not attempted\n";
      }
    });

    context +=
        "\nGive 2 short sentences: strengths/weaknesses and if attendance is an issue.";

    try {
      // Use DeepSeek to generate insights
      final aiInsight = await _deepSeekService.chat(context);
      return InsightResult(
        text: aiInsight.trim(),
        subjectAverages: subjectAverages,
      );
    } catch (e) {
      // Fallback to basic insights if API fails
      return InsightResult(
        text: _generateBasicInsights(subjectScores, subjectAttemptStatus),
        subjectAverages: subjectAverages,
      );
    }
  }

  // Fallback method for basic insights
  String _generateBasicInsights(
    Map<String, List<double>> subjectScores,
    Map<String, List<bool>> subjectAttemptStatus,
  ) {
    String? bestSubject;
    double bestAvg = 0;
    String? worstSubject;
    double worstAvg = 100;
    List<String> notAttemptedSubjects = [];

    subjectScores.forEach((subject, scores) {
      if (scores.isEmpty) return;

      final avg = scores.reduce((a, b) => a + b) / scores.length;
      if (avg > bestAvg) {
        bestAvg = avg;
        bestSubject = subject;
      }
      if (avg < worstAvg) {
        worstAvg = avg;
        worstSubject = subject;
      }

      // Check for not attempted tests
      final totalTests = subjectAttemptStatus[subject]!.length;
      final attemptedCount = subjectAttemptStatus[subject]!
          .where((x) => x)
          .length;
      if (attemptedCount < totalTests) {
        notAttemptedSubjects.add(subject);
      }
    });

    // Check for completely not attempted subjects
    subjectAttemptStatus.forEach((subject, statuses) {
      if (statuses.every((x) => !x)) {
        notAttemptedSubjects.add(subject);
      }
    });

    String insight = "";

    if (subjectScores.isEmpty || subjectScores.values.every((s) => s.isEmpty)) {
      insight =
          "You have not attempted any tests yet. Start taking tests to see your performance!";
      return insight;
    }

    final allScores = subjectScores.values.expand((s) => s).toList();
    final overallAvg = allScores.reduce((a, b) => a + b) / allScores.length;

    insight = "Overall average: ${overallAvg.toStringAsFixed(1)}%. ";

    if (bestSubject != null) {
      insight += "Strongest in $bestSubject (${bestAvg.toStringAsFixed(1)}%). ";
    }
    if (worstSubject != null && worstSubject != bestSubject) {
      insight +=
          "$worstSubject needs focus (${worstAvg.toStringAsFixed(1)}%). ";
    }

    if (notAttemptedSubjects.isNotEmpty) {
      insight +=
          "⚠️ Not attempted: ${notAttemptedSubjects.join(', ')}. Complete all assigned tests!";
    }

    return insight;
  }

  // Generate personalized study plan using DeepSeek AI
  Future<String> generateStudyPlan(
    List<String> subjects,
    List<TestResult> results,
  ) async {
    if (subjects.isEmpty) {
      return "No subjects found. Please update your profile to get a personalized study plan.";
    }

    if (results.isEmpty) {
      // Use AI to generate default plan
      String context =
          "Create a balanced daily study plan for these subjects: ${subjects.join(', ')}. ";
      context +=
          "Include time allocation and practice recommendations for each subject. ";
      context += "Format with emojis and bullet points.";

      try {
        return await _deepSeekService.chat(context);
      } catch (e) {
        return _generateDefaultPlan(subjects);
      }
    }

    // Build context for AI with performance data
    final Map<String, double> subjectAvg = {};
    final Map<String, int> testCounts = {};

    for (var test in results) {
      if (!subjectAvg.containsKey(test.subject)) {
        subjectAvg[test.subject] = 0;
        testCounts[test.subject] = 0;
      }
      subjectAvg[test.subject] =
          (subjectAvg[test.subject]! * testCounts[test.subject]! +
              test.percentage) /
          (testCounts[test.subject]! + 1);
      testCounts[test.subject] = testCounts[test.subject]! + 1;
    }

    String context =
        "Create a personalized daily study plan based on this performance data:\n\n";

    for (var subject in subjects) {
      if (subjectAvg.containsKey(subject)) {
        context +=
            "$subject: ${subjectAvg[subject]!.toStringAsFixed(1)}% average (${testCounts[subject]} tests)\n";
      } else {
        context += "$subject: No test data yet\n";
      }
    }

    context += "\nProvide a prioritized study plan with:\n";
    context += "- Priority subject (weakest): 20 min + 10 MCQs\n";
    context += "- Medium subjects: 10 min + 5 MCQs\n";
    context += "- Strong subjects: 5 min maintenance\n";
    context +=
        "Format with emojis (🎯📖✅) and clear time allocations. Add motivational tip at end.";

    try {
      final aiPlan = await _deepSeekService.chat(context);
      return aiPlan.trim();
    } catch (e) {
      // Fallback to basic plan
      return _generateBasicStudyPlan(subjects, subjectAvg);
    }
  }

  // Fallback for default plan
  String _generateDefaultPlan(List<String> subjects) {
    String plan = "📚 Daily Study Plan:\n\n";
    for (var subject in subjects) {
      plan += "• $subject: 15 min revision + 5 MCQs\n";
    }
    plan += "\n💡 Take tests regularly to get personalized recommendations!";
    return plan;
  }

  // Fallback for basic study plan
  String _generateBasicStudyPlan(
    List<String> subjects,
    Map<String, double> subjectAvg,
  ) {
    final sortedSubjects = subjects.toList()
      ..sort((a, b) {
        final avgA = subjectAvg[a] ?? 50;
        final avgB = subjectAvg[b] ?? 50;
        return avgA.compareTo(avgB);
      });

    String plan = "📝 Personalized Study Plan:\n\n";

    if (sortedSubjects.isNotEmpty) {
      final weakest = sortedSubjects.first;
      final weakAvg = subjectAvg[weakest] ?? 0;
      plan += "🎯 Priority: $weakest (${weakAvg.toStringAsFixed(0)}%)\n";
      plan += "   → 20 min focused practice daily\n";
      plan += "   → Solve 10 MCQs\n\n";
    }

    for (int i = 1; i < sortedSubjects.length - 1 && i < 3; i++) {
      final subject = sortedSubjects[i];
      final avg = subjectAvg[subject] ?? 0;
      plan += "📖 $subject (${avg.toStringAsFixed(0)}%)\n";
      plan += "   → 10 min revision + 5 MCQs\n\n";
    }

    if (sortedSubjects.length > 1) {
      final strongest = sortedSubjects.last;
      final strongAvg = subjectAvg[strongest] ?? 0;
      plan += "✅ $strongest (${strongAvg.toStringAsFixed(0)}%)\n";
      plan += "   → 5 min quick revision\n\n";
    }

    plan += "💡 Daily target: 30-45 minutes";
    return plan;
  }

  // Generate quick performance summary
  String generateQuickSummary(List<TestResult> results) {
    if (results.isEmpty) {
      return "No test data available.";
    }

    final latest = results.first;
    final avgScore =
        results.map((t) => t.percentage).reduce((a, b) => a + b) /
        results.length;

    String summary =
        "Latest: ${latest.subject} - ${latest.percentage.toStringAsFixed(1)}%\n";
    summary += "Overall Average: ${avgScore.toStringAsFixed(1)}%\n";
    summary += "Tests taken: ${results.length}";

    return summary;
  }

  // Suggest what to study next
  String suggestNextTopic(List<TestResult> results, List<String> subjects) {
    if (results.isEmpty) {
      return "Take a test in ${subjects.first} to get started!";
    }

    // Find subject with worst recent performance
    final Map<String, double> recentScores = {};
    for (var test in results.take(3)) {
      if (!recentScores.containsKey(test.subject)) {
        recentScores[test.subject] = test.percentage;
      }
    }

    String? worstSubject;
    double worstScore = 100;
    recentScores.forEach((subject, score) {
      if (score < worstScore) {
        worstScore = score;
        worstSubject = subject;
      }
    });

    if (worstSubject != null) {
      return "Focus on $worstSubject next. Your recent score: ${worstScore.toStringAsFixed(1)}%";
    }

    return "Keep practicing all subjects regularly!";
  }
}
