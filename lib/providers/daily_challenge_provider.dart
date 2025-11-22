import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Provider for managing daily challenge state with caching
/// Prevents unnecessary Firestore reads and maintains state across navigation
class DailyChallengeProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  Future<void> initialize(String studentId) async {
    final today = _getTodayDate();

    // Load from cache first for instant display
    await _loadFromCache(studentId, today);

    // Check if THIS student has answered today
    await _checkIfAnsweredToday(studentId);

    // Then fetch fresh data in background
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
  Future<void> _checkIfAnsweredToday(String studentId) async {
    try {
      final today = _getTodayDate();
      final answerDoc = await _firestore
          .collection('daily_challenge_answers')
          .doc('${studentId}_$today')
          .get();

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
      debugPrint('Error checking answer status for student $studentId: $e');
    }
  }

  /// Fetch today's challenge from Firestore
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
      // Query by date field
      final querySnapshot = await _firestore
          .collection('daily_challenges')
          .where('date', isEqualTo: today)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        _cachedChallenges[studentId] = querySnapshot.docs.first.data();
        _cachedDate = today;
        _errorMessage = null;

        // Save to cache
        await _saveToCache(studentId, today, _cachedChallenges[studentId]!);
      } else {
        _cachedChallenges[studentId] = null;
        _errorMessage = 'No challenge available today';
      }
    } catch (e) {
      _errorMessage = 'Error loading challenge: ${e.toString()}';
      debugPrint(_errorMessage);
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

    if (selectedAnswer == null || cachedChallenge == null) {
      return false;
    }

    _submittingStates[studentId] = true;
    notifyListeners();

    try {
      final correctAnswer = cachedChallenge['correctAnswer'] as String;
      final isCorrect = selectedAnswer == correctAnswer;
      final today = _getTodayDate();

      // Save answer record to daily_challenge_answers with student-specific doc ID
      await _firestore
          .collection('daily_challenge_answers')
          .doc('${studentId}_$today')
          .set({
            'studentId': studentId,
            'studentEmail': studentEmail,
            'date': today,
            'selectedAnswer': selectedAnswer,
            'correctAnswer': correctAnswer,
            'isCorrect': isCorrect,
            'answeredAt': FieldValue.serverTimestamp(),
          });

      debugPrint(
        '📝 Student $studentId answered: $selectedAnswer (${isCorrect ? "CORRECT" : "WRONG"})',
      );

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
      }

      // Update THIS student's state
      _hasAnsweredStates[studentId] = true;
      _resultStates[studentId] = isCorrect ? 'correct' : 'incorrect';
      _submittingStates[studentId] = false;
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
  void clearAllState() {
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
