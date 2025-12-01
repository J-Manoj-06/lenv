import 'package:flutter/material.dart';

class MemoryTileWidget extends StatelessWidget {
  final String symbol;
  final bool isRevealed;
  final bool isMatched;
  final bool isWrong;
  final VoidCallback onTap;

  const MemoryTileWidget({
    super.key,
    required this.symbol,
    required this.isRevealed,
    required this.isMatched,
    required this.isWrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor = const Color(0xFF2A2A2A);

    if (isMatched) {
      bgColor = Colors.green.withOpacity(0.3);
    } else if (isWrong) {
      bgColor = Colors.red.withOpacity(0.3);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRevealed || isMatched
                ? const Color(0xFFFF8A00)
                : Colors.white24,
            width: 2,
          ),
          boxShadow: isRevealed || isMatched
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF8A00).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isRevealed || isMatched ? 1.0 : 0.0,
            child: Text(symbol, style: const TextStyle(fontSize: 32)),
          ),
        ),
      ),
    );
  }
}
