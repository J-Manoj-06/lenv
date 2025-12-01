import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NBackProvider with ChangeNotifier {
  static const String _highScoreKey = 'nback_high_score';
  static const String _maxNKey = 'nback_max_n';

  final List<String> _symbols = ['◆', '●', '■', '▲', '★', '♦', '♥', '♣'];
  final List<String> _sequence = [];

  int _currentN = 1;
  int _round = 0;
  int _score = 0;
  int _highScore = 0;
  int _maxNReached = 1;
  int _correctAnswers = 0;
  int _totalAnswers = 0;

  String _currentSymbol = '';
  bool _isPlaying = false;
  bool _canAnswer = false;
  bool? _lastAnswerCorrect;
  Timer? _sequenceTimer;

  int get currentN => _currentN;
  int get round => _round;
  int get score => _score;
  int get highScore => _highScore;
  int get maxNReached => _maxNReached;
  String get currentSymbol => _currentSymbol;
  bool get isPlaying => _isPlaying;
  bool get canAnswer => _canAnswer;
  bool? get lastAnswerCorrect => _lastAnswerCorrect;

  double get accuracy =>
      _totalAnswers == 0 ? 0.0 : (_correctAnswers / _totalAnswers) * 100;

  int get roundsInLevel => max(8, _currentN * 5);

  NBackProvider() {
    _loadScores();
  }

  Future<void> _loadScores() async {
    final prefs = await SharedPreferences.getInstance();
    _highScore = prefs.getInt(_highScoreKey) ?? 0;
    _maxNReached = prefs.getInt(_maxNKey) ?? 1;
    notifyListeners();
  }

  Future<void> _saveScores() async {
    final prefs = await SharedPreferences.getInstance();
    if (_score > _highScore) {
      _highScore = _score;
      await prefs.setInt(_highScoreKey, _highScore);
    }
    if (_currentN > _maxNReached) {
      _maxNReached = _currentN;
      await prefs.setInt(_maxNKey, _maxNReached);
    }
    notifyListeners();
  }

  void startGame() {
    _currentN = 1;
    _round = 0;
    _score = 0;
    _correctAnswers = 0;
    _totalAnswers = 0;
    _sequence.clear();
    _lastAnswerCorrect = null;
    _isPlaying = true;
    notifyListeners();
    _startSequence();
  }

  void _startSequence() {
    _sequenceTimer?.cancel();
    _sequenceTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _nextSymbol(),
    );
  }

  void _nextSymbol() {
    if (_round >= roundsInLevel) {
      _evaluateLevel();
      return;
    }

    _round++;
    _lastAnswerCorrect = null;

    final random = Random();

    // 30% chance to create a match if possible
    if (_sequence.length >= _currentN && random.nextDouble() < 0.3) {
      _currentSymbol = _sequence[_sequence.length - _currentN];
    } else {
      _currentSymbol = _symbols[random.nextInt(_symbols.length)];
    }

    _sequence.add(_currentSymbol);
    _canAnswer = _sequence.length > _currentN;

    notifyListeners();
  }

  void onMatchPressed() {
    if (!_canAnswer || !_isPlaying) return;

    _canAnswer = false;
    _totalAnswers++;

    final nStepsAgo = _sequence[_sequence.length - _currentN - 1];
    final isMatch = _currentSymbol == nStepsAgo;

    if (isMatch) {
      _correctAnswers++;
      _score += _currentN * 10;
      _lastAnswerCorrect = true;
    } else {
      _lastAnswerCorrect = false;
    }

    notifyListeners();
  }

  void onSkipPressed() {
    if (!_canAnswer || !_isPlaying) return;

    _canAnswer = false;
    _totalAnswers++;

    final nStepsAgo = _sequence[_sequence.length - _currentN - 1];
    final isMatch = _currentSymbol == nStepsAgo;

    if (!isMatch) {
      _correctAnswers++;
      _score += 5;
      _lastAnswerCorrect = true;
    } else {
      _lastAnswerCorrect = false;
    }

    notifyListeners();
  }

  void _evaluateLevel() {
    _sequenceTimer?.cancel();
    _isPlaying = false;

    final acc = accuracy;

    if (acc >= 80 && _currentN < 8) {
      _currentN++;
      _score += 50;
    } else if (acc < 50 && _currentN > 1) {
      _currentN--;
    }

    _saveScores();
    notifyListeners();
  }

  void nextLevel() {
    _round = 0;
    _correctAnswers = 0;
    _totalAnswers = 0;
    _sequence.clear();
    _lastAnswerCorrect = null;
    _isPlaying = true;
    notifyListeners();
    _startSequence();
  }

  void endGame() {
    _sequenceTimer?.cancel();
    _isPlaying = false;
    _saveScores();
    notifyListeners();
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    super.dispose();
  }
}
