import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Provider for managing daily challenge state with caching
/// Prevents unnecessary Firestore reads and maintains state across navigation
class DailyChallengeProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache management
  Map<String, dynamic>? _cachedChallenge;
  String? _cachedDate;
  bool _isLoading = false;
  String? _errorMessage;

  // Answer state
  String? _selectedAnswer;
  bool _isSubmitting = false;
  bool _hasAnsweredToday = false;
  String? _todayResult; // 'correct' or 'incorrect'

  // Getters
  Map<String, dynamic>? get cachedChallenge => _cachedChallenge;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get selectedAnswer => _selectedAnswer;
  bool get isSubmitting => _isSubmitting;
  bool get hasAnsweredToday => _hasAnsweredToday;
  String? get todayResult => _todayResult;

  /// Get today's date in yyyy-MM-dd format
  String _getTodayDate() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  /// Initialize provider - load from cache and check answer status
  Future<void> initialize(String studentId) async {
    final today = _getTodayDate();

    // Load from cache first for instant display
    await _loadFromCache(today);

    // Check if answered today
    await _checkIfAnsweredToday(studentId);

    // Then fetch fresh data in background
    await fetchChallenge(studentId, forceRefresh: false);
  }

  /// Load cached challenge from SharedPreferences
  Future<void> _loadFromCache(String today) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedDatePref = prefs.getString('daily_challenge_date');
      final cachedDataPref = prefs.getString('daily_challenge_data');

      // Only use cache if it's from today
      if (cachedDatePref == today && cachedDataPref != null) {
        _cachedChallenge = jsonDecode(cachedDataPref);
        _cachedDate = cachedDatePref;
        notifyListeners();
      }
    } catch (e) {
      // Ignore cache errors
      debugPrint('Error loading cache: $e');
    }
  }

  /// Save challenge to cache
  Future<void> _saveToCache(String date, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('daily_challenge_date', date);
      await prefs.setString('daily_challenge_data', jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving cache: $e');
    }
  }

  /// Check if student has already answered today's challenge
  Future<void> _checkIfAnsweredToday(String studentId) async {
    try {
      final today = _getTodayDate();
      final answerDoc = await _firestore
          .collection('daily_challenge_answers')
          .doc('${studentId}_$today')
          .get();

      if (answerDoc.exists) {
        _hasAnsweredToday = true;
        _todayResult = answerDoc.data()?['isCorrect'] == true
            ? 'correct'
            : 'incorrect';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error checking answer status: $e');
    }
  }

  /// Fetch today's challenge from Firestore
  Future<void> fetchChallenge(
    String studentId, {
    bool forceRefresh = false,
  }) async {
    final today = _getTodayDate();

    // Return cached data if available and not forcing refresh
    if (!forceRefresh && _cachedDate == today && _cachedChallenge != null) {
      return;
    }

    _isLoading = true;
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
        _cachedChallenge = querySnapshot.docs.first.data();
        _cachedDate = today;
        _errorMessage = null;

        // Save to cache
        await _saveToCache(today, _cachedChallenge!);
      } else {
        _cachedChallenge = null;
        _errorMessage = 'No challenge available today';
      }
    } catch (e) {
      _errorMessage = 'Error loading challenge: ${e.toString()}';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set selected answer (without triggering reload)
  void setSelectedAnswer(String answer) {
    if (!_hasAnsweredToday && !_isSubmitting) {
      _selectedAnswer = answer;
      notifyListeners();
    }
  }

  /// Submit the selected answer
  Future<bool> submitAnswer(String studentId, String studentEmail) async {
    if (_selectedAnswer == null || _cachedChallenge == null) {
      return false;
    }

    _isSubmitting = true;
    notifyListeners();

    try {
      final correctAnswer = _cachedChallenge!['correctAnswer'] as String;
      final isCorrect = _selectedAnswer == correctAnswer;
      final today = _getTodayDate();

      // Save answer record
      await _firestore
          .collection('daily_challenge_answers')
          .doc('${studentId}_$today')
          .set({
            'studentId': studentId,
            'studentEmail': studentEmail,
            'date': today,
            'selectedAnswer': _selectedAnswer,
            'correctAnswer': correctAnswer,
            'isCorrect': isCorrect,
            'answeredAt': FieldValue.serverTimestamp(),
          });

      if (isCorrect) {
        // Update student's reward points
        await _firestore.collection('users').doc(studentId).update({
          'rewardPoints': FieldValue.increment(5),
        });
      }

      _hasAnsweredToday = true;
      _todayResult = isCorrect ? 'correct' : 'incorrect';
      _isSubmitting = false;
      notifyListeners();

      return isCorrect;
    } catch (e) {
      _errorMessage = 'Error submitting answer: ${e.toString()}';
      _isSubmitting = false;
      notifyListeners();
      return false;
    }
  }

  /// Reset provider for new day
  void reset() {
    _cachedChallenge = null;
    _cachedDate = null;
    _selectedAnswer = null;
    _hasAnsweredToday = false;
    _todayResult = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear cache (for debugging)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('daily_challenge_date');
      await prefs.remove('daily_challenge_data');
      reset();
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
}
