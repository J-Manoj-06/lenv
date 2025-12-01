import 'package:flutter/material.dart';

class PatternButton extends StatelessWidget {
  final Color color;
  final bool isActive;
  final VoidCallback onPressed;

  const PatternButton({
    super.key,
    required this.color,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isActive ? color : color.withOpacity(0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.8),
                    blurRadius: 25,
                    spreadRadius: 5,
                  ),
                ]
              : [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
        ),
      ),
    );
  }
}
