import 'package:flutter/material.dart';
import 'teacher_main_navigation.dart';

class TeacherBottomNav extends StatelessWidget {
  final int selectedIndex;

  const TeacherBottomNav({Key? key, required this.selectedIndex})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
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
                icon: Icons.school_outlined,
                selectedIcon: Icons.school,
                label: 'Classes',
                index: 1,
                route: '/classes',
              ),
              _buildNavItem(
                context,
                icon: Icons.assignment_outlined,
                selectedIcon: Icons.assignment,
                label: 'Tests',
                index: 2,
                route: '/tests',
              ),
              _buildNavItem(
                context,
                icon: Icons.leaderboard_outlined,
                selectedIcon: Icons.leaderboard,
                label: 'Leaderboard',
                index: 3,
                route: '/leaderboard',
              ),
              _buildNavItem(
                context,
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: 'Profile',
                index: 4,
                route: '/profile',
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
    final color = isSelected
        ? const Color(0xFF6366F1)
        : Theme.of(context).iconTheme.color?.withOpacity(0.6);

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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSelected ? selectedIcon : icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
