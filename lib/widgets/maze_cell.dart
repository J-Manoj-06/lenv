import 'dart:math';
import 'package:flutter/material.dart';

class MazeCell extends StatelessWidget {
  final bool isPath;
  final bool isHighlighted;
  final bool isUserPath;
  final bool isCorrect;
  final VoidCallback onTap;

  const MazeCell({
    super.key,
    required this.isPath,
    required this.isHighlighted,
    required this.isUserPath,
    required this.isCorrect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor = const Color(0xFF2A2A2A);

    if (isHighlighted) {
      bgColor = const Color(0xFFFF8A00);
    } else if (isUserPath) {
      bgColor = isCorrect ? Colors.green : Colors.red;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          boxShadow: isHighlighted || isUserPath
              ? [
                  BoxShadow(
                    color: bgColor.withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
