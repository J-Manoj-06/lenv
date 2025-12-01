import 'package:flutter/material.dart';
import 'dart:ui';
import 'teacher_main_navigation.dart';

class TeacherBottomNav extends StatelessWidget {
  final int selectedIndex;

  const TeacherBottomNav({super.key, required this.selectedIndex});

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
                        Color(0x007961FF),
                        Color(0x807961FF),
                        Color(0x007961FF),
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
                      _buildNavItem(
                        context,
                        icon: Icons.dashboard_outlined,
                        selectedIcon: Icons.dashboard,
                        label: 'Dashboard',
                        index: 0,
                        route: '/teacher-dashboard',
                      ),
                      _buildNavItem(
                        context,
                        icon: Icons.assignment_outlined,
                        selectedIcon: Icons.assignment,
                        label: 'Tests',
                        index: 1,
                        route: '/tests',
                      ),
                      _buildNavItem(
                        context,
                        icon: Icons.message_outlined,
                        selectedIcon: Icons.message,
                        label: 'Messages',
                        index: 2,
                        route: '/messages',
                      ),
                      _buildNavItem(
                        context,
                        icon: Icons.groups_outlined,
                        selectedIcon: Icons.groups,
                        label: 'Classes',
                        index: 3,
                        route: '/classes',
                      ),
                      _buildNavItem(
                        context,
                        icon: Icons.leaderboard_outlined,
                        selectedIcon: Icons.leaderboard,
                        label: 'Leaderboard',
                        index: 4,
                        route: '/leaderboard',
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

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
    required String route,
  }) {
    final isSelected = selectedIndex == index;
    final inactive = Colors.grey[400];
    const primary = Color(0xFF7961FF);

    return Expanded(
      child: InkWell(
        onTap: () {
          if (!isSelected) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    TeacherMainNavigation(initialIndex: index),
              ),
              (route) => false,
            );
          }
        },
        child: SizedBox(
          height: 66,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? primary : inactive,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : inactive,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
