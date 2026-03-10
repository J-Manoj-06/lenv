import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/daily_challenge_service.dart';

/// Provider for managing daily challenge state with caching
/// Prevents unnecessary Firestore reads and maintains state across navigation
/// Now uses OpenTriviaDB API for fetching questions
class DailyChallengeProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DailyChallengeService _challengeService = DailyChallengeService();

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

    // STEP 1: Load from cache first for instant display
    await _loadFromCache(studentId, today);

    // STEP 2: Check answer status from Firestore (CRITICAL)
    // This ensures correct state even after app restart
    await _checkIfAnsweredToday(studentId);

    // STEP 3: Fetch fresh challenge data in background
    await fetchChallenge(studentId, forceRefresh: false);
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
    } catch (e) {}
  }

  /// Check if THIS SPECIFIC student has already answered today's challenge
  /// CRITICAL: Force fresh read from Firestore to ensure we get the latest state
  /// even on app restart or when offline persistence hasn't synced yet
  Future<void> _checkIfAnsweredToday(String studentId) async {
    try {
      final today = _getTodayDate();

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

        // ENHANCEMENT: Ensure cached challenge has correct answer from answer doc
        // This is critical for displaying the correct answer on dashboard after answering
        final answerData = answerDoc.data();
        if (answerData != null && _cachedChallenges[studentId] != null) {
          // Merge correct answer from answer document into cached challenge
          _cachedChallenges[studentId]!['correctAnswer'] =
              answerData['correctAnswer'];
          _cachedChallenges[studentId]!['question'] =
              answerData['question'] ??
              _cachedChallenges[studentId]!['question'];
        } else if (answerData != null && _cachedChallenges[studentId] == null) {
          // If no cached challenge but has answer, create minimal cache with answer data
          _cachedChallenges[studentId] = {
            'correctAnswer': answerData['correctAnswer'],
            'question': answerData['question'] ?? 'Daily Challenge Question',
          };
        }
      } else {
        _hasAnsweredStates[studentId] = false;
        _resultStates[studentId] = null;
      }
      notifyListeners();
    } catch (e) {
      // If server fetch fails (no internet), fall back to local cache
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

          // Also merge correct answer in offline mode
          final answerData = answerDoc.data();
          if (answerData != null && _cachedChallenges[studentId] != null) {
            _cachedChallenges[studentId]!['correctAnswer'] =
                answerData['correctAnswer'];
            _cachedChallenges[studentId]!['question'] =
                answerData['question'] ??
                _cachedChallenges[studentId]!['question'];
          } else if (answerData != null &&
              _cachedChallenges[studentId] == null) {
            _cachedChallenges[studentId] = {
              'correctAnswer': answerData['correctAnswer'],
              'question': answerData['question'] ?? 'Daily Challenge Question',
            };
          }
        } else {
          _hasAnsweredStates[studentId] = false;
          _resultStates[studentId] = null;
        }
      } catch (cacheError) {
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
      } else {
        // Fetch new challenge from OpenTriviaDB

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
        } catch (e) {}

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
        } else {
          _cachedChallenges[studentId] = null;
          _errorMessage = 'Unable to fetch challenge from OpenTriviaDB';
        }
      }
    } catch (e) {
      _errorMessage = 'Error loading challenge: ${e.toString()}';
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
      return false;
    }

    if (cachedChallenge == null) {
      return false;
    }

    _submittingStates[studentId] = true;
    notifyListeners();

    try {
      final correctAnswer = cachedChallenge['correctAnswer'] as String;
      final question =
          cachedChallenge['question'] as String? ?? 'Daily Challenge';
      final isCorrect = selectedAnswer == correctAnswer;
      final today = _getTodayDate();

      // Save answer record to daily_challenge_answers with student-specific doc ID
      final docId = '${studentId}_$today';
      await _firestore.collection('daily_challenge_answers').doc(docId).set({
        'studentId': studentId,
        'studentEmail': studentEmail,
        'date': today,
        'question': question, // Save question for later display
        'selectedAnswer': selectedAnswer,
        'correctAnswer': correctAnswer,
        'isCorrect': isCorrect,
        'answeredAt': FieldValue.serverTimestamp(),
      });

      // Update streak regardless of correct/incorrect answer
      await _updateStreak(studentId, today);

      if (isCorrect) {
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
      }

      // Update THIS student's state
      _hasAnsweredStates[studentId] = true;
      _resultStates[studentId] = isCorrect ? 'correct' : 'incorrect';
      _submittingStates[studentId] = false;

      // Clear selected answer after submission
      _selectedAnswers[studentId] = null;

      notifyListeners();

      return isCorrect;
    } catch (e) {
      _errorMessage = 'Error submitting answer: ${e.toString()}';
      _submittingStates[studentId] = false;
      notifyListeners();
      return false;
    }
  }

  /// Update streak for a student
  Future<void> _updateStreak(String studentId, String today) async {
    try {
      print('[Streak] 🔥 Updating streak for student: $studentId on $today');

      // Get student document
      final studentDoc = await _firestore
          .collection('users')
          .doc(studentId)
          .get();

      if (!studentDoc.exists) {
        print('[Streak] ❌ Student document does not exist');
        return;
      }

      final data = studentDoc.data() as Map<String, dynamic>;
      final lastStreakDate = _extractDateString(data['lastStreakDate']);
      final currentStreak = data['streak'] as int? ?? 0;

      print(
        '[Streak] 📊 Current streak: $currentStreak, Last date: $lastStreakDate',
      );

      int newStreak;

      if (lastStreakDate == null) {
        // First recorded attempt
        newStreak = 1;
        print('[Streak] 🆕 First recorded attempt - setting streak to 1');
      } else if (lastStreakDate == today) {
        // Already counted for today; do not increment twice
        newStreak = currentStreak;
        print(
          '[Streak] ⚠️ Already counted today - keeping streak at $currentStreak',
        );
      } else {
        // New day attempt: increment streak regardless of gap and correctness
        newStreak = currentStreak + 1;
        print(
          '[Streak] ✅ New day attempt recorded - incrementing streak: $currentStreak → $newStreak',
        );
      }

      print(
        '[Streak] 💾 Updating Firestore: streak=$newStreak, lastStreakDate=$today',
      );

      // Update BOTH users and students collections for consistency
      // Use sequential writes to ensure atomicity
      await _firestore.collection('users').doc(studentId).set({
        'streak': newStreak,
        'lastStreakDate': today,
      }, SetOptions(merge: true));

      print('[Streak] ✅ Updated users collection');

      await _firestore.collection('students').doc(studentId).set({
        'streak': newStreak,
        'lastStreakDate': today,
      }, SetOptions(merge: true));

      print('[Streak] ✅ Streak updated successfully in both collections!');

      // Wait for Firestore to propagate (important for consistency)
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('[Streak] ❌ Error updating streak: $e');
    }
  }

  String? _extractDateString(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      if (value.isEmpty) return null;
      if (value.length >= 10) {
        return value.substring(0, 10);
      }
      return value;
    }

    if (value is Timestamp) {
      final date = value.toDate();
      final year = date.year.toString().padLeft(4, '0');
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      return '$year-$month-$day';
    }

    return null;
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
    } catch (e) {}

    // Clear in-memory state
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
    } catch (e) {}
  }
}
