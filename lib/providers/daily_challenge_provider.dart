import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/daily_challenge_service.dart';
import '../services/badge_service.dart';
import '../services/badge_rules.dart';

/// Provider for managing daily challenge state with caching
/// Prevents unnecessary Firestore reads and maintains state across navigation
/// Now uses OpenTriviaDB API for fetching questions
class DailyChallengeProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DailyChallengeService _challengeService = DailyChallengeService();
  final BadgeService _badgeService = BadgeService();
  late final BadgeRules _badgeRules = BadgeRules(_badgeService);

  // Cache management - per student
  final Map<String, Map<String, dynamic>?> _cachedChallenges = {};
  String? _cachedDate;
  final Map<String, bool> _loadingStates = {};
  String? _errorMessage;

  // Answer state - per student
  final Map<String, String?> _selectedAnswers = {};
  final Map<String, bool> _submittingStates = {};
  final Map<String, bool> _hasAnsweredStates = {};
  final Map<String, String?> _resultStates = {}; // 'correct' or 'incorrect'

  // Getters - now require studentId
  Map<String, dynamic>? getCachedChallenge(String studentId) =>
      _cachedChallenges[studentId];
  bool hasChallenge(String studentId) => _cachedChallenges[studentId] != null;
  bool isLoading(String studentId) => _loadingStates[studentId] ?? false;
  String? get errorMessage => _errorMessage;
  String? getSelectedAnswer(String studentId) => _selectedAnswers[studentId];
  bool isSubmitting(String studentId) => _submittingStates[studentId] ?? false;
  bool hasAnsweredToday(String studentId) =>
      _hasAnsweredStates[studentId] ?? false;
  String? getTodayResult(String studentId) => _resultStates[studentId];

  /// Get today's date in yyyy-MM-dd format
  String _getTodayDate() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  /// Initialize provider - load from cache and check answer status
  /// CRITICAL: This must run on EVERY dashboard load (including app restart)
  Future<void> initialize(String studentId) async {
    final today = _getTodayDate();
    print('🔧 DailyChallengeProvider.initialize for student: $studentId');

    // STEP 1: Load from cache first for instant display
    await _loadFromCache(studentId, today);
    print('📦 Cache loaded for $studentId');

    // STEP 2: Check answer status from Firestore (CRITICAL)
    // This ensures correct state even after app restart
    await _checkIfAnsweredToday(studentId);
    print(
      '✅ Answer status checked. Has answered: ${_hasAnsweredStates[studentId]}',
    );

    // STEP 3: Fetch fresh challenge data in background
    await fetchChallenge(studentId, forceRefresh: false);
    print('🔄 Fresh challenge data fetched');
  }

  /// Load cached challenge from SharedPreferences (per student)
  Future<void> _loadFromCache(String studentId, String today) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'daily_challenge_${studentId}_date';
      final dataKey = 'daily_challenge_${studentId}_data';

      final cachedDatePref = prefs.getString(cacheKey);
      final cachedDataPref = prefs.getString(dataKey);

      // Only use cache if it's from today
      if (cachedDatePref == today && cachedDataPref != null) {
        _cachedChallenges[studentId] = jsonDecode(cachedDataPref);
        _cachedDate = cachedDatePref;
        notifyListeners();
      }
    } catch (e) {
      // Ignore cache errors
      debugPrint('Error loading cache for student $studentId: $e');
    }
  }

  /// Save challenge to cache (per student)
  Future<void> _saveToCache(
    String studentId,
    String date,
    Map<String, dynamic> data,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'daily_challenge_${studentId}_date';
      final dataKey = 'daily_challenge_${studentId}_data';

      await prefs.setString(cacheKey, date);
      await prefs.setString(dataKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving cache for student $studentId: $e');
    }
  }

  /// Check if THIS SPECIFIC student has already answered today's challenge
  /// CRITICAL: Force fresh read from Firestore to ensure we get the latest state
  /// even on app restart or when offline persistence hasn't synced yet
  Future<void> _checkIfAnsweredToday(String studentId) async {
    try {
      final today = _getTodayDate();
      debugPrint(
        '🔍 Checking if student $studentId answered today ($today)...',
      );

      // CRITICAL: Force fresh read from Firestore
      // This ensures we always get the latest answer status from the server
      // even on app restart when offline persistence might not be synced yet
      final answerDoc = await _firestore
          .collection('daily_challenge_answers')
          .doc('${studentId}_$today')
          .get(const GetOptions(source: Source.server));

      if (answerDoc.exists) {
        _hasAnsweredStates[studentId] = true;
        final isCorrect = answerDoc.data()?['isCorrect'] == true;
        _resultStates[studentId] = isCorrect ? 'correct' : 'incorrect';
        debugPrint(
          '✅ Student $studentId has already answered today: ${isCorrect ? "correct" : "incorrect"}',
        );
      } else {
        _hasAnsweredStates[studentId] = false;
        _resultStates[studentId] = null;
        debugPrint('📝 Student $studentId has NOT answered today');
      }
      notifyListeners();
    } catch (e) {
      // If server fetch fails (no internet), fall back to local cache
      debugPrint(
        '⚠️ Server fetch failed for $studentId, trying local cache: $e',
      );
      try {
        final today = _getTodayDate();
        final answerDoc = await _firestore
            .collection('daily_challenge_answers')
            .doc('${studentId}_$today')
            .get(const GetOptions(source: Source.cache));

        if (answerDoc.exists) {
          _hasAnsweredStates[studentId] = true;
          final isCorrect = answerDoc.data()?['isCorrect'] == true;
          _resultStates[studentId] = isCorrect ? 'correct' : 'incorrect';
          debugPrint(
            '✅ Student $studentId (cached): ${isCorrect ? "correct" : "incorrect"}',
          );
        } else {
          _hasAnsweredStates[studentId] = false;
          _resultStates[studentId] = null;
          debugPrint('📝 Student $studentId (cached): NOT answered');
        }
      } catch (cacheError) {
        debugPrint(
          '❌ Both server and cache failed for $studentId: $cacheError',
        );
        _hasAnsweredStates[studentId] = false;
        _resultStates[studentId] = null;
      }
      notifyListeners();
    }
  }

  /// Fetch today's challenge from OpenTriviaDB API
  Future<void> fetchChallenge(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final today = _getTodayDate();

    // Return cached data if available and not forcing refresh
    if (!forceRefresh &&
        _cachedDate == today &&
        _cachedChallenges[studentId] != null) {
      return;
    }

    _loadingStates[studentId] = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check if challenge exists in SharedPreferences for today
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'daily_challenge_${studentId}_date';
      final dataKey = 'daily_challenge_${studentId}_data';
      final standardKey = 'daily_challenge_${studentId}_standard';

      final cachedDatePref = prefs.getString(cacheKey);
      final cachedDataPref = prefs.getString(dataKey);

      // If cache is from today, use it
      if (!forceRefresh && cachedDatePref == today && cachedDataPref != null) {
        _cachedChallenges[studentId] = jsonDecode(cachedDataPref);
        _cachedDate = today;
        _errorMessage = null;
        debugPrint('✅ Loaded cached challenge for student $studentId');
      } else {
        // Fetch new challenge from OpenTriviaDB
        debugPrint(
          '🔄 Fetching NEW challenge from OpenTriviaDB for student $studentId',
        );

        // Get student's standard/class from Firestore
        int standard = 8; // Default
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(studentId)
              .get();
          if (userDoc.exists) {
            final data = userDoc.data();
            // Try different field names for standard
            standard =
                data?['standard'] ?? data?['class'] ?? data?['grade'] ?? 8;
          }
        } catch (e) {
          debugPrint('⚠️ Could not fetch student standard, using default: $e');
        }

        // Fetch from OpenTriviaDB
        final challenge = await _challengeService.getDailyChallengeForToday(
          studentId,
          standard,
        );

        if (challenge != null) {
          final challengeData = challenge.toJson();
          _cachedChallenges[studentId] = challengeData;
          _cachedDate = today;
          _errorMessage = null;

          // Save to cache
          await _saveToCache(studentId, today, challengeData);
          await prefs.setInt(standardKey, standard);

          debugPrint(
            '✅ Fetched and cached new challenge for student $studentId (standard: $standard)',
          );
        } else {
          _cachedChallenges[studentId] = null;
          _errorMessage = 'Unable to fetch challenge from OpenTriviaDB';
          debugPrint(
            '❌ Failed to fetch challenge from OpenTriviaDB for student $studentId',
          );
        }
      }
    } catch (e) {
      _errorMessage = 'Error loading challenge: ${e.toString()}';
      debugPrint('❌ Error in fetchChallenge for student $studentId: $e');
    } finally {
      _loadingStates[studentId] = false;
      notifyListeners();
    }
  }

  /// Set selected answer for THIS student (without triggering reload)
  void setSelectedAnswer(String studentId, String answer) {
    if (!(_hasAnsweredStates[studentId] ?? false) &&
        !(_submittingStates[studentId] ?? false)) {
      _selectedAnswers[studentId] = answer;
      notifyListeners();
    }
  }

  /// Submit the selected answer for THIS student
  Future<bool> submitAnswer(String studentId, String studentEmail) async {
    final selectedAnswer = _selectedAnswers[studentId];
    final cachedChallenge = _cachedChallenges[studentId];

    if (selectedAnswer == null) {
      debugPrint('❌ Submit failed: No selected answer for student $studentId');
      return false;
    }

    if (cachedChallenge == null) {
      debugPrint('❌ Submit failed: No cached challenge for student $studentId');
      return false;
    }

    _submittingStates[studentId] = true;
    notifyListeners();

    try {
      final correctAnswer = cachedChallenge['correctAnswer'] as String;
      final isCorrect = selectedAnswer == correctAnswer;
      final today = _getTodayDate();

      debugPrint(
        '📝 Submitting answer for student $studentId: selected="$selectedAnswer", correct="$correctAnswer", isCorrect=$isCorrect',
      );

      // Save answer record to daily_challenge_answers with student-specific doc ID
      final docId = '${studentId}_$today';
      await _firestore.collection('daily_challenge_answers').doc(docId).set({
        'studentId': studentId,
        'studentEmail': studentEmail,
        'date': today,
        'selectedAnswer': selectedAnswer,
        'correctAnswer': correctAnswer,
        'isCorrect': isCorrect,
        'answeredAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Saved to daily_challenge_answers with doc ID: $docId');

      // Update streak regardless of correct/incorrect answer
      await _updateStreak(studentId, today);

      if (isCorrect) {
        debugPrint(
          '🎯 Daily Challenge: Awarding 5 points to student $studentId',
        );

        // Create student_rewards entry for THIS student only
        final rewardDoc = _firestore.collection('student_rewards').doc();
        await rewardDoc.set({
          'id': rewardDoc.id,
          'studentId': studentId,
          'testId': 'daily_challenge_$today',
          'marks': 1.0,
          'totalMarks': 1.0,
          'pointsEarned': 5,
          'timestamp': FieldValue.serverTimestamp(),
          'source': 'daily_challenge',
          'date': today,
        });

        // Update THIS student's rewardPoints
        await _firestore.collection('users').doc(studentId).set({
          'rewardPoints': FieldValue.increment(5),
        }, SetOptions(merge: true));

        debugPrint(
          '✅ Student $studentId: Points saved to student_rewards and users collection',
        );

        // Award badges for daily challenge
        try {
          final studentDoc = await _firestore
              .collection('users')
              .doc(studentId)
              .get();
          final streakDays =
              (studentDoc.data()?['dailyChallengeStreak'] as int?) ?? 1;

          debugPrint(
            '🏆 Awarding badges for daily challenge: streak=$streakDays',
          );

          await _badgeRules.onDailyChallenge(
            studentId: studentId,
            streakDays: streakDays,
            fast: false, // Could track answer time in future
            accuracyPercent: 100, // Daily challenge is single question
          );

          debugPrint('✅ Badges awarded successfully for student $studentId');
        } catch (e) {
          debugPrint('❌ Error awarding badges: $e');
        }
      }

      // Update THIS student's state
      _hasAnsweredStates[studentId] = true;
      _resultStates[studentId] = isCorrect ? 'correct' : 'incorrect';
      _submittingStates[studentId] = false;

      // Clear selected answer after submission
      _selectedAnswers[studentId] = null;

      debugPrint(
        '✅ Daily Challenge: Updated state for student $studentId - hasAnswered: true, result: ${isCorrect ? "correct" : "incorrect"}',
      );

      notifyListeners();

      return isCorrect;
    } catch (e) {
      _errorMessage = 'Error submitting answer: ${e.toString()}';
      debugPrint(
        '❌ Error submitting daily challenge for student $studentId: $e',
      );
      _submittingStates[studentId] = false;
      notifyListeners();
      return false;
    }
  }

  /// Update streak for a student
  Future<void> _updateStreak(String studentId, String today) async {
    try {
      // Get student document
      final studentDoc = await _firestore
          .collection('users')
          .doc(studentId)
          .get();

      if (!studentDoc.exists) {
        debugPrint('⚠️ Student document not found for $studentId');
        return;
      }

      final data = studentDoc.data() as Map<String, dynamic>;
      final lastStreakDate = data['lastStreakDate'] as String?;
      final currentStreak = data['streak'] as int? ?? 0;

      int newStreak;

      if (lastStreakDate == null) {
        // First time answering
        newStreak = 1;
      } else if (lastStreakDate == today) {
        // Already answered today (shouldn't happen, but keep current streak)
        newStreak = currentStreak;
      } else {
        // Check if it's a consecutive day
        final lastDate = _parseDate(lastStreakDate);
        final todayDate = _parseDate(today);

        if (lastDate != null && todayDate != null) {
          final daysDiff = todayDate.difference(lastDate).inDays;

          if (daysDiff == 1) {
            // Consecutive day - increment streak
            newStreak = currentStreak + 1;
          } else {
            // Missed days - reset streak
            newStreak = 1;
          }
        } else {
          // Error parsing dates - reset streak
          newStreak = 1;
        }
      }

      // Update student document
      await _firestore.collection('users').doc(studentId).set({
        'streak': newStreak,
        'lastStreakDate': today,
      }, SetOptions(merge: true));

      debugPrint(
        '🔥 Updated streak for $studentId: $newStreak (previous: $currentStreak, lastDate: $lastStreakDate)',
      );
    } catch (e) {
      debugPrint('❌ Error updating streak for $studentId: $e');
    }
  }

  /// Parse date string (yyyy-MM-dd) to DateTime
  DateTime? _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length != 3) return null;

      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final day = int.tryParse(parts[2]);

      if (year == null || month == null || day == null) return null;

      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  /// Reset provider for new day
  void reset() {
    _cachedChallenges.clear();
    _cachedDate = null;
    _selectedAnswers.clear();
    _hasAnsweredStates.clear();
    _resultStates.clear();
    _errorMessage = null;
    _loadingStates.clear();
    _submittingStates.clear();
    notifyListeners();
  }

  /// Clear all state completely (used on logout/user switch)
  Future<void> clearAllState() async {
    try {
      // Clear SharedPreferences for all cached students
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // Remove all daily_challenge related keys
      for (final key in keys) {
        if (key.startsWith('daily_challenge_')) {
          await prefs.remove(key);
        }
      }

      debugPrint('🧹 DailyChallengeProvider: Cleared SharedPreferences cache');
    } catch (e) {
      debugPrint('⚠️ Error clearing SharedPreferences: $e');
    }

    // Clear in-memory state
    _cachedChallenges.clear();
    _cachedDate = null;
    _selectedAnswers.clear();
    _hasAnsweredStates.clear();
    _resultStates.clear();
    _errorMessage = null;
    _loadingStates.clear();
    _submittingStates.clear();
    debugPrint('🧹 DailyChallengeProvider: All state cleared for user switch');
    notifyListeners();
  }

  /// Clear cache for specific student (for debugging)
  Future<void> clearCache(String studentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'daily_challenge_${studentId}_date';
      final dataKey = 'daily_challenge_${studentId}_data';

      await prefs.remove(cacheKey);
      await prefs.remove(dataKey);

      _cachedChallenges.remove(studentId);
      _selectedAnswers.remove(studentId);
      _hasAnsweredStates.remove(studentId);
      _resultStates.remove(studentId);
      _loadingStates.remove(studentId);
      _submittingStates.remove(studentId);

      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing cache for student $studentId: $e');
    }
  }
}
