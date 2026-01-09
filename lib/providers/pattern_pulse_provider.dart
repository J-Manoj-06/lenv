import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PatternPulseProvider with ChangeNotifier {
  static const String _highestLevelKey = 'pattern_pulse_highest_level';

  final List<Color> _colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.yellow,
  ];

  final List<int> _sequence = [];
  final List<int> _userInput = [];

  int _currentLevel = 1;
  int _highestLevel = 1;

  GameState _gameState = GameState.idle;
  int? _activeButton;

  int get currentLevel => _currentLevel;
  int get highestLevel => _highestLevel;
  GameState get gameState => _gameState;
  int? get activeButton => _activeButton;
  List<Color> get colors => _colors;

  int get flashSpeed => max(600 - (_currentLevel * 30), 200);
  int get sequenceLength => 3 + _currentLevel;

  PatternPulseProvider() {
    _loadHighestLevel();
  }

  Future<void> _loadHighestLevel() async {
    final prefs = await SharedPreferences.getInstance();
    _highestLevel = prefs.getInt(_highestLevelKey) ?? 1;
    notifyListeners();
  }

  Future<void> _saveHighestLevel() async {
    if (_currentLevel > _highestLevel) {
      _highestLevel = _currentLevel;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_highestLevelKey, _highestLevel);
      notifyListeners();
    }
  }

  void startGame() {
    _currentLevel = 1;
    _sequence.clear();
    _userInput.clear();
    _gameState = GameState.idle;
    notifyListeners();
    _startLevel();
  }

  void _startLevel() {
    _userInput.clear();
    _generateSequence();
    _gameState = GameState.showing;
    notifyListeners();
    _displaySequence();
  }

  void _generateSequence() {
    _sequence.clear();
    final random = Random();
    for (int i = 0; i < sequenceLength; i++) {
      _sequence.add(random.nextInt(4));
    }
  }

  Future<void> _displaySequence() async {
    await Future.delayed(const Duration(milliseconds: 500));

    for (int i = 0; i < _sequence.length; i++) {
      _activeButton = _sequence[i];
      notifyListeners();

      await Future.delayed(Duration(milliseconds: flashSpeed));

      _activeButton = null;
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 200));
    }

    _gameState = GameState.playing;
    notifyListeners();
  }

  void onButtonPressed(int index) {
    if (_gameState != GameState.playing) return;

    _activeButton = index;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 150), () {
      _activeButton = null;
      notifyListeners();
    });

    _userInput.add(index);

    // Check if correct
    if (_userInput.last != _sequence[_userInput.length - 1]) {
      _gameFailed();
      return;
    }

    // Check if sequence complete
    if (_userInput.length == _sequence.length) {
      _levelComplete();
    }
  }

  void _levelComplete() {
    _gameState = GameState.levelComplete;
    _currentLevel++;
    _saveHighestLevel();
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 1200), () {
      _startLevel();
    });
  }

  void _gameFailed() {
    _gameState = GameState.failed;
    notifyListeners();
  }

  void retryLevel() {
    _userInput.clear();
    _gameState = GameState.showing;
    notifyListeners();
    _displaySequence();
  }

  void exitGame() {
    _gameState = GameState.idle;
    _sequence.clear();
    _userInput.clear();
    notifyListeners();
  }
}

enum GameState { idle, showing, playing, levelComplete, failed }
