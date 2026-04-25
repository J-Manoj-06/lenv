import 'package:flutter/material.dart';
import 'dart:ui';

class StudentBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const StudentBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;
    onTabSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withOpacity(0.70),
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
              // Gradient separator line at the top edge
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
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: SizedBox(
                  height: 66,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _NavItem(
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home,
                        label: 'Home',
                        isSelected: currentIndex == 0,
                        onTap: () => _onTap(context, 0),
                      ),
                      _NavItem(
                        icon: Icons.assignment_outlined,
                        selectedIcon: Icons.assignment,
                        label: 'Tests',
                        isSelected: currentIndex == 1,
                        onTap: () => _onTap(context, 1),
                      ),
                      _NavItem(
                        icon: Icons.chat_bubble_outline,
                        selectedIcon: Icons.chat_bubble,
                        label: 'Message',
                        isSelected: currentIndex == 2,
                        onTap: () => _onTap(context, 2),
                      ),
                      _NavItem(
                        icon: Icons.workspace_premium_outlined,
                        selectedIcon: Icons.workspace_premium,
                        label: 'Rewards',
                        isSelected: currentIndex == 3,
                        onTap: () => _onTap(context, 3),
                      ),
                      _NavItem(
                        icon: Icons.leaderboard_outlined,
                        selectedIcon: Icons.leaderboard,
                        label: 'Leaderboard',
                        isSelected: currentIndex == 4,
                        onTap: () => _onTap(context, 4),
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const selectedColor = Color(0xFFF27F0D);
    final unselectedColor = Colors.grey[400];

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? selectedColor : unselectedColor,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? selectedColor : unselectedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
