import 'package:flutter/material.dart';
import 'student_main_navigation.dart';
import 'animated_navbar.dart';

class StudentBottomNav extends StatelessWidget {
  final int currentIndex;
  const StudentBottomNav({super.key, required this.currentIndex});

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;

    // Navigate to the main navigation wrapper with the selected index
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) =>
            StudentMainNavigation(initialIndex: index),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.02, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedNavbar(
      currentIndex: currentIndex,
      onTap: (index) => _onTap(context, index),
      items: const [
        AnimatedNavItemData(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Home',
        ),
        AnimatedNavItemData(
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment,
          label: 'Tests',
        ),
        AnimatedNavItemData(
          icon: Icons.chat_bubble_outline,
          selectedIcon: Icons.chat_bubble,
          label: 'Message',
        ),
        AnimatedNavItemData(
          icon: Icons.workspace_premium_outlined,
          selectedIcon: Icons.workspace_premium,
          label: 'Rewards',
        ),
        AnimatedNavItemData(
          icon: Icons.leaderboard_outlined,
          selectedIcon: Icons.leaderboard,
          label: 'Leaderboard',
        ),
      ],
    );
  }
}
