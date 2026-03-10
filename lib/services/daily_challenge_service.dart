import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_challenge.dart';

class DailyChallengeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _dateKey = 'daily_challenge_date';
  static const String _jsonKey = 'daily_challenge_json';
  static const String _attemptedKey = 'daily_challenge_attempted';
  static const String _correctKey = 'daily_challenge_correct';
  static const String _pointsKey = 'daily_challenge_points';
  static const String _streakKey = 'daily_challenge_streak';

  /// Get smart difficulty based on student's standard/class
  /// Grades 4-6: Easy
  /// Grades 7-10: Medium
  /// Grades 11-12: Hard
  String getSmartDifficulty(int standard) {
    if (standard >= 4 && standard <= 6) {
      return 'easy';
    } else if (standard >= 7 && standard <= 10) {
      return 'medium';
    } else if (standard >= 11 && standard <= 12) {
      return 'hard';
    }
    return 'medium'; // Default fallback
  }

  /// Fetch question from Firebase (pre-cached by Cloudflare Worker)
  /// This is the PRIMARY method - questions are fetched once daily at 2 AM
  /// by Cloudflare Worker and stored in Firebase
  Future<DailyChallenge?> fetchQuestionFromFirebase(int standard) async {
    try {
      final difficulty = getSmartDifficulty(standard);
      final today = DateTime.now().toIso8601String().split('T').first;

      debugPrint(
        '📥 Fetching $difficulty question for grade $standard from Firebase...',
      );

      // Fetch from Firebase daily_challenges collection
      final doc = await _firestore
          .collection('daily_challenges')
          .doc(today)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!doc.exists || doc.data() == null) {
        debugPrint(
          '⚠️ No challenge found in Firebase for $today, falling back to API',
        );
        return await fetchQuestionFromAPI(standard);
      }

      final data = doc.data()!;

      // Get difficulty-specific fields
      final prefix = difficulty; // 'easy', 'medium', or 'hard'
      final question = data['${prefix}_question'] as String?;
      final correctAnswer = data['${prefix}_correctAnswer'] as String?;
      final optionsList = data['${prefix}_options'] as List?;
      final category = data['${prefix}_category'] as String?;
      final difficultyLevel = data['${prefix}_difficulty'] as String?;

      if (question == null || correctAnswer == null || optionsList == null) {
        debugPrint('⚠️ Incomplete data in Firebase, falling back to API');
        return await fetchQuestionFromAPI(standard);
      }

      final options = optionsList.map((e) => e.toString()).toList();

      debugPrint('✅ Successfully fetched $difficulty question from Firebase');

      return DailyChallenge(
        question: question,
        options: options,
        correctAnswer: correctAnswer,
        category: category ?? 'General Knowledge',
        difficulty: difficultyLevel ?? difficulty,
      );
    } catch (e) {
      debugPrint('❌ Error fetching from Firebase: $e');
      debugPrint('⚠️ Falling back to OpenTriviaDB API');
      return await fetchQuestionFromAPI(standard);
    }
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

  /// Fetch question from OpenTriviaDB API (FALLBACK ONLY)
  /// This is only used when Firebase fetch fails or data is missing
  Future<DailyChallenge?> fetchQuestionFromAPI(int standard) async {
    try {
      final difficulty = getSmartDifficulty(standard);
      final categoryList = getCategoryList(standard);
      categoryList.shuffle();
      final category = categoryList.first;

      debugPrint('🌐 Fetching from OpenTriviaDB API (fallback)...');

      final uri = Uri.parse(
        'https://opentdb.com/api.php?amount=1&type=multiple&category=$category&difficulty=$difficulty',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('❌ OpenTriviaDB API error: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List?;

      if (results == null || results.isEmpty) {
        debugPrint('❌ Empty results from OpenTriviaDB');
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

      debugPrint('✅ Successfully fetched from OpenTriviaDB API');

      return DailyChallenge(
        question: question,
        options: allOptions,
        correctAnswer: correctAnswer,
        category: questionData['category'] as String,
        difficulty: questionData['difficulty'] as String,
      );
    } catch (e) {
      debugPrint('❌ Error fetching from API: $e');
      return null;
    }
  }

  /// Debug print helper (silenced by default)
  void debugPrint(String message) {
    if (!DailyChallengeService.verbose) return;
    print('[DailyChallengeService] $message');
  }

  static bool verbose = false;

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
  /// PRIMARY: Fetch from Firebase (pre-cached by Cloudflare Worker)
  /// FALLBACK: Fetch from OpenTriviaDB API if Firebase fails
  Future<DailyChallenge?> getDailyChallengeForToday(
    String userId,
    int standard,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;

    final savedDate = prefs.getString('${_dateKey}_$userId');

    if (savedDate == today) {
      // Load saved challenge from local cache
      final jsonString = prefs.getString('${_jsonKey}_$userId');
      if (jsonString != null) {
        try {
          final jsonData = json.decode(jsonString) as Map<String, dynamic>;
          return DailyChallenge.fromJson(jsonData);
        } catch (e) {
          debugPrint('❌ Error loading cached challenge: $e');
        }
      }
    }

    // Fetch new challenge from Firebase (primary source)
    DailyChallenge? challenge = await fetchQuestionFromFirebase(standard);

    // If Firebase fails, fallback to API
    challenge ??= await fetchQuestionFromAPI(standard);

    if (challenge != null) {
      // Save new challenge to local cache
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
    final today = DateTime.now().toIso8601String().split('T').first;
    final savedDate = prefs.getString('${_dateKey}_$userId');
    final alreadyAttemptedToday =
        savedDate == today &&
        (prefs.getBool('${_attemptedKey}_$userId') ?? false);

    await prefs.setBool('${_attemptedKey}_$userId', true);
    await prefs.setBool('${_correctKey}_$userId', isCorrect);
    await prefs.setDouble('${_pointsKey}_$userId', points);

    // Update streak once per day, regardless of correct/incorrect answer
    if (!alreadyAttemptedToday) {
      final currentStreak = prefs.getInt('${_streakKey}_$userId') ?? 0;
      await prefs.setInt('${_streakKey}_$userId', currentStreak + 1);
    }
  }

  /// Get result data
  /// Note: streak should be retrieved from Firestore (users collection) 
  /// as it is the authoritative source and persists across app restarts
  Future<Map<String, dynamic>> getResultData(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isCorrect': prefs.getBool('${_correctKey}_$userId') ?? false,
      'points': prefs.getDouble('${_pointsKey}_$userId') ?? 0.0,
    };
  }

  /// Reset streak (optional, if user misses a day)
  Future<void> resetStreak(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_streakKey}_$userId', 0);
  }
}
