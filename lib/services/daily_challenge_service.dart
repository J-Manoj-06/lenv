import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_challenge.dart';

class DailyChallengeService {
  static const String _dateKey = 'daily_challenge_date';
  static const String _jsonKey = 'daily_challenge_json';
  static const String _attemptedKey = 'daily_challenge_attempted';
  static const String _correctKey = 'daily_challenge_correct';
  static const String _pointsKey = 'daily_challenge_points';
  static const String _streakKey = 'daily_challenge_streak';

  /// Get smart difficulty based on student's standard/class
  String getSmartDifficulty(int standard) {
    if (standard >= 1 && standard <= 8) {
      return 'easy';
    } else if (standard >= 9 && standard <= 10) {
      return 'medium';
    } else if (standard >= 11 && standard <= 12) {
      // Probability system for class 11-12
      final random = DateTime.now().millisecondsSinceEpoch % 100;
      if (random < 30) {
        return 'easy'; // 30% chance
      } else if (random < 80) {
        return 'medium'; // 50% chance
      } else {
        return 'hard'; // 20% chance
      }
    }
    return 'easy'; // Default fallback
  }

  /// Get category list based on student's standard/class
  List<int> getCategoryList(int standard) {
    if (standard >= 1 && standard <= 4) {
      return [9, 17]; // General Knowledge, Science & Nature
    } else if (standard >= 5 && standard <= 8) {
      return [18, 22, 23]; // Computers, Geography, History
    } else if (standard >= 9 && standard <= 10) {
      return [17, 18, 19]; // Science, Computers, Math
    } else if (standard >= 11 && standard <= 12) {
      return [
        17,
        18,
        19,
        23,
        24,
      ]; // Science, Computers, Math, History, Politics
    }
    return [9]; // Default General Knowledge
  }

  /// Fetch question from OpenTriviaDB API
  Future<DailyChallenge?> fetchQuestionFromAPI(int standard) async {
    try {
      final difficulty = getSmartDifficulty(standard);
      final categoryList = getCategoryList(standard);
      categoryList.shuffle();
      final category = categoryList.first;

      final uri = Uri.parse(
        'https://opentdb.com/api.php?amount=1&type=multiple&category=$category&difficulty=$difficulty',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List?;

      if (results == null || results.isEmpty) {
        return null;
      }

      final questionData = results.first as Map<String, dynamic>;

      // Decode HTML entities
      final question = decodeHtmlEntities(questionData['question'] as String);
      final correctAnswer = decodeHtmlEntities(
        questionData['correct_answer'] as String,
      );
      final incorrectAnswers = (questionData['incorrect_answers'] as List)
          .map((e) => decodeHtmlEntities(e as String))
          .toList();

      // Shuffle answers
      final allOptions = [correctAnswer, ...incorrectAnswers];
      allOptions.shuffle(Random(DateTime.now().millisecondsSinceEpoch));

      return DailyChallenge(
        question: question,
        options: allOptions,
        correctAnswer: correctAnswer,
        category: questionData['category'] as String,
        difficulty: questionData['difficulty'] as String,
      );
    } catch (e) {
      return null;
    }
  }

  /// Decode HTML entities (&quot;, &#039;, &amp;, etc.)
  String decodeHtmlEntities(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&apos;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"')
        .replaceAll('&hellip;', '...')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—');
  }

  /// Get daily challenge for today (load or fetch new)
  Future<DailyChallenge?> getDailyChallengeForToday(
    String userId,
    int standard,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;

    final savedDate = prefs.getString('${_dateKey}_$userId');

    if (savedDate == today) {
      // Load saved challenge
      final jsonString = prefs.getString('${_jsonKey}_$userId');
      if (jsonString != null) {
        final jsonData = json.decode(jsonString) as Map<String, dynamic>;
        return DailyChallenge.fromJson(jsonData);
      }
    }

    // Fetch new challenge
    final challenge = await fetchQuestionFromAPI(standard);
    if (challenge != null) {
      // Save new challenge
      await prefs.setString('${_dateKey}_$userId', today);
      await prefs.setString(
        '${_jsonKey}_$userId',
        json.encode(challenge.toJson()),
      );
      await prefs.setBool('${_attemptedKey}_$userId', false);
      await prefs.remove('${_correctKey}_$userId');
      await prefs.remove('${_pointsKey}_$userId');
    }

    return challenge;
  }

  /// Check if today's challenge has been attempted
  Future<bool> isAttemptedToday(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('${_attemptedKey}_$userId') ?? false;
  }

  /// Save daily result after answering
  Future<void> saveDailyResult(
    String userId,
    bool isCorrect,
    double points,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_attemptedKey}_$userId', true);
    await prefs.setBool('${_correctKey}_$userId', isCorrect);
    await prefs.setDouble('${_pointsKey}_$userId', points);

    // Update streak
    if (isCorrect) {
      final currentStreak = prefs.getInt('${_streakKey}_$userId') ?? 0;
      await prefs.setInt('${_streakKey}_$userId', currentStreak + 1);
    }
  }

  /// Get result data
  Future<Map<String, dynamic>> getResultData(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isCorrect': prefs.getBool('${_correctKey}_$userId') ?? false,
      'points': prefs.getDouble('${_pointsKey}_$userId') ?? 0.0,
      'streak': prefs.getInt('${_streakKey}_$userId') ?? 0,
    };
  }

  /// Reset streak (optional, if user misses a day)
  Future<void> resetStreak(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_streakKey}_$userId', 0);
  }
}
