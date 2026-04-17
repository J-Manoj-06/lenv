import 'dart:ui';

import 'package:flutter/material.dart';

class AnimatedNavItemData {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const AnimatedNavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class AnimatedNavbar extends StatelessWidget {
  final int currentIndex;
  final List<AnimatedNavItemData> items;
  final ValueChanged<int> onTap;

  const AnimatedNavbar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = const Color(0xFFF27F0D);
    final unselectedColor = Colors.grey[400] ?? Colors.grey;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withValues(alpha: 0.70),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 20,
                spreadRadius: 0,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0x00F27F0D),
                        Color(0x80F27F0D),
                        Color(0x00F27F0D),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: SizedBox(
                  height: 66,
                  child: Stack(
                    children: [
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment(-1 + ((currentIndex * 2) / (items.length - 1)), 0),
                        child: FractionallySizedBox(
                          widthFactor: 1 / items.length,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              height: 3,
                              width: 30,
                              decoration: BoxDecoration(
                                color: selectedColor,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(items.length, (index) {
                          final item = items[index];
                          final selected = index == currentIndex;
                          return Expanded(
                            child: InkWell(
                              onTap: () => onTap(index),
                              child: SizedBox(
                                height: 66,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedScale(
                                      scale: selected ? 1.1 : 1.0,
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOut,
                                      child: Icon(
                                        selected ? item.selectedIcon : item.icon,
                                        color: selected ? selectedColor : unselectedColor,
                                        size: selected ? 26 : 24,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 220),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: selected
                                            ? selectedColor
                                            : unselectedColor,
                                      ),
                                      child: Text(item.label),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
