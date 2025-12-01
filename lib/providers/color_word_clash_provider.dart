import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ColorWordClashProvider with ChangeNotifier {
  static const String _highScoreKey = 'color_word_clash_high_score';

  final List<ColorData> _colors = [
    ColorData(name: 'RED', color: Colors.red),
    ColorData(name: 'BLUE', color: Colors.blue),
    ColorData(name: 'GREEN', color: Colors.green),
    ColorData(name: 'YELLOW', color: Colors.yellow),
  ];

  String _currentWord = '';
  Color _currentColor = Colors.white;
  int _correctAnswerIndex = 0;

  int _score = 0;
  int _highScore = 0;
  int _round = 0;
  double _timeLeft = 1.5;

  GameState _gameState = GameState.idle;
  bool _isAnswered = false;
  bool? _lastAnswerCorrect;

  Timer? _gameTimer;
  Timer? _countdownTimer;

  List<ColorData> get colors => _colors;
  String get currentWord => _currentWord;
  Color get currentColor => _currentColor;
  int get score => _score;
  int get highScore => _highScore;
  int get round => _round;
  double get timeLeft => _timeLeft;
  GameState get gameState => _gameState;
  bool? get lastAnswerCorrect => _lastAnswerCorrect;

  double get timeLimit => max(1.5 - (_round * 0.02), 0.5);

  ColorWordClashProvider() {
    _loadHighScore();
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    _highScore = prefs.getInt(_highScoreKey) ?? 0;
    notifyListeners();
  }

  Future<void> _saveHighScore() async {
    if (_score > _highScore) {
      _highScore = _score;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_highScoreKey, _highScore);
      notifyListeners();
    }
  }

  void startGame() {
    _score = 0;
    _round = 0;
    _gameState = GameState.playing;
    _lastAnswerCorrect = null;
    notifyListeners();
    _nextRound();
  }

  void _nextRound() {
    _round++;
    _isAnswered = false;
    _lastAnswerCorrect = null;
    _timeLeft = timeLimit;

    final random = Random();

    // Pick random word and random color (ensure they're different for challenge)
    final wordIndex = random.nextInt(_colors.length);
    int colorIndex;
    do {
      colorIndex = random.nextInt(_colors.length);
    } while (colorIndex == wordIndex);

    _currentWord = _colors[wordIndex].name;
    _currentColor = _colors[colorIndex].color;
    _correctAnswerIndex = colorIndex;

    notifyListeners();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _timeLeft -= 0.05;
      if (_timeLeft <= 0) {
        _timeLeft = 0;
        timer.cancel();
        if (!_isAnswered) {
          _handleTimeout();
        }
      }
      notifyListeners();
    });
  }

  void onColorTap(int index) {
    if (_isAnswered || _gameState != GameState.playing) return;

    _isAnswered = true;
    _countdownTimer?.cancel();

    if (index == _correctAnswerIndex) {
      _lastAnswerCorrect = true;
      final timeBonus = (_timeLeft * 10).round();
      _score += 10 + timeBonus;

      Future.delayed(const Duration(milliseconds: 500), () {
        if (_gameState == GameState.playing) {
          _nextRound();
        }
      });
    } else {
      _lastAnswerCorrect = false;
      _gameOver();
    }

    notifyListeners();
  }

  void _handleTimeout() {
    _lastAnswerCorrect = false;
    _gameOver();
  }

  void _gameOver() {
    _countdownTimer?.cancel();
    _gameState = GameState.gameOver;
    _saveHighScore();
    notifyListeners();
  }

  void exitGame() {
    _countdownTimer?.cancel();
    _gameTimer?.cancel();
    _gameState = GameState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _gameTimer?.cancel();
    super.dispose();
  }
}

class ColorData {
  final String name;
  final Color color;

  ColorData({required this.name, required this.color});
}

enum GameState { idle, playing, gameOver }
