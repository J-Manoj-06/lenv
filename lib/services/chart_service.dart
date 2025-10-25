import '../models/performance_model.dart';

class ChartDataPoint {
  final String label;
  final double value;
  final DateTime? date;

  ChartDataPoint({
    required this.label,
    required this.value,
    this.date,
  });
}

class ChartService {
  // Get performance trend data for charts
  List<ChartDataPoint> getPerformanceTrend(PerformanceModel performance) {
    return performance.submissions.map((submission) {
      return ChartDataPoint(
        label: submission.testTitle,
        value: submission.percentage,
        date: submission.submittedAt,
      );
    }).toList();
  }

  // Get subject-wise performance
  Map<String, double> getSubjectWisePerformance(List<TestSubmission> submissions) {
    // This is a simplified version. You can enhance it based on test subjects
    // Group scores by subject (you'll need to add subject info to TestSubmission)
    // For now, returning a placeholder
    return {
      'Mathematics': 85.0,
      'Science': 78.0,
      'English': 92.0,
      'History': 88.0,
    };
  }

  // Calculate average score over time period
  double calculateAverageScore(List<TestSubmission> submissions, {int? lastNTests}) {
    if (submissions.isEmpty) return 0.0;
    
    final relevantSubmissions = lastNTests != null && lastNTests < submissions.length
        ? submissions.take(lastNTests).toList()
        : submissions;
    
    final totalPercentage = relevantSubmissions.fold<double>(
      0.0,
      (sum, submission) => sum + submission.percentage,
    );
    
    return totalPercentage / relevantSubmissions.length;
  }

  // Get score distribution
  Map<String, int> getScoreDistribution(List<TestSubmission> submissions) {
    final distribution = {
      'A (90-100)': 0,
      'B (80-89)': 0,
      'C (70-79)': 0,
      'D (60-69)': 0,
      'F (<60)': 0,
    };

    for (final submission in submissions) {
      if (submission.percentage >= 90) {
        distribution['A (90-100)'] = distribution['A (90-100)']! + 1;
      } else if (submission.percentage >= 80) {
        distribution['B (80-89)'] = distribution['B (80-89)']! + 1;
      } else if (submission.percentage >= 70) {
        distribution['C (70-79)'] = distribution['C (70-79)']! + 1;
      } else if (submission.percentage >= 60) {
        distribution['D (60-69)'] = distribution['D (60-69)']! + 1;
      } else {
        distribution['F (<60)'] = distribution['F (<60)']! + 1;
      }
    }

    return distribution;
  }

  // Get monthly performance data
  List<ChartDataPoint> getMonthlyPerformance(List<TestSubmission> submissions) {
    final monthlyData = <String, List<double>>{};

    for (final submission in submissions) {
      final monthKey = '${submission.submittedAt.year}-${submission.submittedAt.month.toString().padLeft(2, '0')}';
      
      if (!monthlyData.containsKey(monthKey)) {
        monthlyData[monthKey] = [];
      }
      monthlyData[monthKey]!.add(submission.percentage);
    }

    return monthlyData.entries.map((entry) {
      final average = entry.value.reduce((a, b) => a + b) / entry.value.length;
      return ChartDataPoint(
        label: entry.key,
        value: average,
      );
    }).toList();
  }

  // Compare student with class average
  Map<String, double> compareWithClassAverage({
    required double studentAverage,
    required double classAverage,
  }) {
    return {
      'student': studentAverage,
      'class': classAverage,
      'difference': studentAverage - classAverage,
    };
  }
}
