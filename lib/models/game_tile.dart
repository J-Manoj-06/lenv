class GameTile {
  final int index;
  final String symbol;
  final bool isTarget;
  bool isRevealed;
  bool isMatched;
  bool isWrong;

  GameTile({
    required this.index,
    required this.symbol,
    this.isTarget = false,
    this.isRevealed = false,
    this.isMatched = false,
    this.isWrong = false,
  });

  GameTile copyWith({
    int? index,
    String? symbol,
    bool? isTarget,
    bool? isRevealed,
    bool? isMatched,
    bool? isWrong,
  }) {
    return GameTile(
      index: index ?? this.index,
      symbol: symbol ?? this.symbol,
      isTarget: isTarget ?? this.isTarget,
      isRevealed: isRevealed ?? this.isRevealed,
      isMatched: isMatched ?? this.isMatched,
      isWrong: isWrong ?? this.isWrong,
    );
  }
}
