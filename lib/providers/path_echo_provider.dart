import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PathEchoProvider with ChangeNotifier {
  static const String _highestLevelKey = 'path_echo_highest_level';

  List<Point<int>> _path = [];
  List<Point<int>> _userPath = [];
  Set<Point<int>> _visitedCells = {};

  int _currentLevel = 1;
  int _displayIndex = 0;
  int _highestLevel = 1;

  GameState _gameState = GameState.idle;
  Point<int>? _currentHighlight;

  int get currentLevel => _currentLevel;
  int get highestLevel => _highestLevel;
  GameState get gameState => _gameState;
  List<Point<int>> get path => _path;
  List<Point<int>> get userPath => _userPath;
  Set<Point<int>> get visitedCells => _visitedCells;
  Point<int>? get currentHighlight => _currentHighlight;

  int get gridSize => min(5 + (_currentLevel ~/ 4), 7);
  int get pathLength => min(4 + _currentLevel, gridSize * 2);
  int get animationSpeed => max(500 - (_currentLevel * 20), 200);

  PathEchoProvider() {
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
    _userPath.clear();
    _visitedCells.clear();
    _gameState = GameState.idle;
    notifyListeners();
    _startLevel();
  }

  void _startLevel() {
    _userPath.clear();
    _visitedCells.clear();
    _generatePath();
    _gameState = GameState.showing;
    notifyListeners();
    _animatePath();
  }

  void _generatePath() {
    _path.clear();
    final random = Random();
    final size = gridSize;

    // Start from random position
    var current = Point(random.nextInt(size), random.nextInt(size));
    _path.add(current);

    // Generate path with valid moves
    for (int i = 1; i < pathLength; i++) {
      final validMoves = <Point<int>>[];

      // Check all 4 directions
      final directions = [
        Point(0, -1), // up
        Point(0, 1), // down
        Point(-1, 0), // left
        Point(1, 0), // right
      ];

      for (final dir in directions) {
        final next = Point(current.x + dir.x, current.y + dir.y);
        if (next.x >= 0 && next.x < size && next.y >= 0 && next.y < size) {
          // Avoid immediate backtrack
          if (_path.length < 2 || next != _path[_path.length - 2]) {
            validMoves.add(next);
          }
        }
      }

      if (validMoves.isEmpty) break;

      current = validMoves[random.nextInt(validMoves.length)];
      _path.add(current);
    }
  }

  Future<void> _animatePath() async {
    await Future.delayed(const Duration(milliseconds: 500));

    for (int i = 0; i < _path.length; i++) {
      _displayIndex = i;
      _currentHighlight = _path[i];
      notifyListeners();

      await Future.delayed(Duration(milliseconds: animationSpeed));
    }

    _currentHighlight = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 300));

    _gameState = GameState.playing;
    notifyListeners();
  }

  void onCellTap(int x, int y) {
    if (_gameState != GameState.playing) return;

    final point = Point(x, y);

    // Check if this is the next correct cell
    if (_userPath.length < _path.length) {
      final expectedPoint = _path[_userPath.length];

      if (point == expectedPoint) {
        _userPath.add(point);
        _visitedCells.add(point);

        // Check if path is complete
        if (_userPath.length == _path.length) {
          _levelComplete();
        }
      } else {
        _pathFailed();
      }
    }

    notifyListeners();
  }

  void _levelComplete() {
    _gameState = GameState.levelComplete;
    _currentLevel++;
    _saveHighestLevel();
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 1500), () {
      _startLevel();
    });
  }

  void _pathFailed() {
    _gameState = GameState.failed;
    notifyListeners();
  }

  void retryLevel() {
    _userPath.clear();
    _visitedCells.clear();
    _gameState = GameState.showing;
    notifyListeners();
    _animatePath();
  }

  void exitGame() {
    _gameState = GameState.idle;
    _path.clear();
    _userPath.clear();
    _visitedCells.clear();
    notifyListeners();
  }
}

enum GameState { idle, showing, playing, levelComplete, failed }
