import 'badge_service.dart';

class BadgeRules {
  final BadgeService _service;
  BadgeRules(this._service);

  Future<void> onTestCompleted({
    required String studentId,
    required String testId,
    required int scorePercent,
    required int testsCompleted,
    int? previousScorePercent,
  }) async {
    // Award only ONE score-based badge (highest achieved)
    if (scorePercent == 100) {
      await _service.awardBadge(studentId, 'perfect_score', testId: testId);
    } else if (scorePercent >= 90) {
      await _service.awardBadge(studentId, 'high_scorer', testId: testId);
    } else if (scorePercent >= 80) {
      await _service.awardBadge(studentId, 'excellent_scorer', testId: testId);
    }

    // Improvement badge
    if (previousScorePercent != null &&
        (scorePercent - previousScorePercent) >= 15) {
      await _service.awardBadge(studentId, 'most_improved', testId: testId);
    }

    // Milestone badges - award ONLY on exact count to avoid duplicates
    if (testsCompleted == 1) {
      await _service.awardBadge(studentId, 'first_test', testId: testId);
    } else if (testsCompleted == 5) {
      await _service.awardBadge(studentId, 'fifth_test', testId: testId);
      await _service.awardBadge(studentId, 'test_streak_5', testId: testId);
    } else if (testsCompleted == 10) {
      await _service.awardBadge(studentId, 'tenth_test', testId: testId);
    }

    // Consistent performer - check last 3 tests all >= 75%
    // This would need historical data; simplified for now
    if (testsCompleted == 3 && scorePercent >= 75) {
      await _service.awardBadge(
        studentId,
        'consistent_performer',
        testId: testId,
      );
    }
  }

  Future<void> onDailyChallenge({
    required String studentId,
    required int streakDays,
    required bool fast,
    required int accuracyPercent,
  }) async {
    if (streakDays == 1) {
      await _service.awardBadge(studentId, 'first_challenge');
    }
    if (streakDays >= 3) {
      await _service.awardBadge(studentId, 'streak_3');
    }
    if (streakDays >= 5) {
      await _service.awardBadge(studentId, 'streak_5');
    }
    if (streakDays >= 7) {
      await _service.awardBadge(studentId, 'streak_7');
    }
    if (fast) {
      await _service.awardBadge(studentId, 'fast_solver');
    }
    if (accuracyPercent >= 90) {
      await _service.awardBadge(studentId, 'high_accuracy');
    }
  }
}
