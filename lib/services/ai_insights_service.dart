import '../models/test_result.dart';
import 'deepseek_service.dart';

class AiInsightsService {
  final DeepSeekService _deepSeekService = DeepSeekService();

  // Generate smart insights based on test results using DeepSeek AI
  Future<String> generateSmartInsights(List<TestResult> results) async {
    if (results.isEmpty) {
      return "No test data available yet. Take some tests to see your performance insights!";
    }

    if (results.length == 1) {
      final test = results.first;
      return "You scored ${test.percentage.toStringAsFixed(1)}% in ${test.subject}. Keep taking tests to track your progress!";
    }

    // Prepare data for AI analysis
    final Map<String, List<double>> subjectScores = {};
    final Map<String, List<String>> subjectGrades = {};

    for (var test in results) {
      if (!subjectScores.containsKey(test.subject)) {
        subjectScores[test.subject] = [];
        subjectGrades[test.subject] = [];
      }
      subjectScores[test.subject]!.add(test.percentage);
      subjectGrades[test.subject]!.add(test.grade);
    }

    // Build context for DeepSeek
    String context =
        "Analyze this student's performance data and provide 2-3 sentence insights:\n\n";

    subjectScores.forEach((subject, scores) {
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      final latest = scores.first;
      final grades = subjectGrades[subject]!.join(', ');
      context +=
          "$subject: Average ${avg.toStringAsFixed(1)}%, Latest ${latest.toStringAsFixed(1)}%, Grades: $grades\n";
    });

    context +=
        "\nProvide actionable insights about strengths, weaknesses, and improvement trends.";

    try {
      // Use DeepSeek to generate insights
      final aiInsight = await _deepSeekService.chat(context);
      return aiInsight.trim();
    } catch (e) {
      // Fallback to basic insights if API fails
      return _generateBasicInsights(subjectScores);
    }
  }

  // Fallback method for basic insights
  String _generateBasicInsights(Map<String, List<double>> subjectScores) {
    String? bestSubject;
    double bestAvg = 0;
    String? worstSubject;
    double worstAvg = 100;

    subjectScores.forEach((subject, scores) {
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      if (avg > bestAvg) {
        bestAvg = avg;
        bestSubject = subject;
      }
      if (avg < worstAvg) {
        worstAvg = avg;
        worstSubject = subject;
      }
    });

    final allScores = subjectScores.values.expand((s) => s).toList();
    final overallAvg = allScores.reduce((a, b) => a + b) / allScores.length;

    String insight = "Overall average: ${overallAvg.toStringAsFixed(1)}%.";
    if (bestSubject != null) {
      insight += " Strongest in $bestSubject (${bestAvg.toStringAsFixed(1)}%).";
    }
    if (worstSubject != null && worstSubject != bestSubject) {
      insight +=
          " $worstSubject needs focus (${worstAvg.toStringAsFixed(1)}%).";
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
