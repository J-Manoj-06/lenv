import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_tile.dart';

class GhostMemoryProvider with ChangeNotifier {
  static const String _highScoreKey = 'ghost_memory_high_score';

  List<GameTile> _tiles = [];
  List<int> _targetIndices = [];
  List<int> _userTaps = [];

  int _currentLevel = 1;
  int _score = 0;
  int _highScore = 0;

  GameState _gameState = GameState.idle;

  int get gridSize => min(3 + (_currentLevel ~/ 3), 6);
  int get targetCount =>
      min(2 + (_currentLevel ~/ 2), gridSize * gridSize ~/ 2);
  int get flashDuration => max(1000 - (_currentLevel * 50), 400);

  List<GameTile> get tiles => _tiles;
  int get currentLevel => _currentLevel;
  int get score => _score;
  int get highScore => _highScore;
  GameState get gameState => _gameState;

  final List<String> _symbols = [
    '👻',
    '🎃',
    '🦇',
    '🕷️',
    '🌙',
    '⭐',
    '💀',
    '🔮',
    '🧙',
    '🕸️',
    '🍬',
    '🎭',
    '🌟',
    '💫',
    '✨',
    '🔥',
  ];

  GhostMemoryProvider() {
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
    _currentLevel = 1;
    _score = 0;
    _userTaps.clear();
    _gameState = GameState.idle;
    _generateLevel();
    notifyListeners();
  }

  void _generateLevel() {
    final size = gridSize;
    final totalTiles = size * size;

    _tiles.clear();
    _targetIndices.clear();
    _userTaps.clear();

    // Generate random target indices
    final random = Random();
    final availableIndices = List.generate(totalTiles, (i) => i);
    availableIndices.shuffle();
    _targetIndices = availableIndices.take(targetCount).toList();

    // Create tiles
    for (int i = 0; i < totalTiles; i++) {
      final isTarget = _targetIndices.contains(i);
      _tiles.add(
        GameTile(
          index: i,
          symbol: isTarget ? _symbols[random.nextInt(_symbols.length)] : '',
          isTarget: isTarget,
          isRevealed: false,
        ),
      );
    }

    _gameState = GameState.memorizing;
    notifyListeners();

    // Flash tiles
    _revealTiles();
  }

  void _revealTiles() {
    for (var tile in _tiles) {
      if (tile.isTarget) {
        tile.isRevealed = true;
      }
    }
    notifyListeners();

    Timer(Duration(milliseconds: flashDuration), () {
      for (var tile in _tiles) {
        tile.isRevealed = false;
      }
      _gameState = GameState.playing;
      notifyListeners();
    });
  }

  void onTileTap(int index) {
    if (_gameState != GameState.playing) return;

    final tile = _tiles[index];

    // Check if already tapped
    if (_userTaps.contains(index)) return;

    _userTaps.add(index);

    if (tile.isTarget) {
      tile.isMatched = true;
      _score += 10;

      if (_userTaps.length == _targetIndices.length) {
        _levelComplete();
      }
    } else {
      tile.isWrong = true;
      _gameOver();
    }

    notifyListeners();
  }

  void _levelComplete() {
    _gameState = GameState.levelComplete;
    _score += _currentLevel * 5;
    notifyListeners();

    Timer(const Duration(milliseconds: 800), () {
      _currentLevel++;
      _generateLevel();
    });
  }

  void _gameOver() {
    _gameState = GameState.gameOver;
    _saveHighScore();
    notifyListeners();
  }

  void retryLevel() {
    _userTaps.clear();
    for (var tile in _tiles) {
      tile.isMatched = false;
      tile.isWrong = false;
      tile.isRevealed = false;
    }
    _revealTiles();
  }

  void exitGame() {
    _gameState = GameState.idle;
    _tiles.clear();
    notifyListeners();
  }
}

enum GameState { idle, memorizing, playing, levelComplete, gameOver }
