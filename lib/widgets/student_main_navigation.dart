import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/student/student_dashboard_screen.dart';
import '../screens/student/student_tests_screen.dart';
import '../screens/student/student_leaderboard_screen.dart';
import '../screens/student/student_messages_screen.dart';
import '../features/rewards/rewards_screen_wrapper.dart';

/// Student Main Navigation Wrapper
/// Uses IndexedStack to preserve state when switching tabs
/// Prevents unnecessary rebuilds and reloading of data
class StudentMainNavigation extends StatefulWidget {
  final int initialIndex;

  const StudentMainNavigation({super.key, this.initialIndex = 0});

  @override
  State<StudentMainNavigation> createState() => _StudentMainNavigationState();
}

class _StudentMainNavigationState extends State<StudentMainNavigation> {
  late int _currentIndex;
  final List<Widget> _screens = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      // Initialize all screens once with current user
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _screens.addAll([
          const StudentDashboardScreen(), // 0: Home
          const StudentTestsScreen(), // 1: Tests
          const StudentMessagesScreen(), // 2: Messages
          RewardsScreenWrapper(userId: user.uid), // 3: Rewards
          const StudentLeaderboardScreen(), // 4: Leaderboard
        ]);
      }
    }
  }

  void _onTap(int index) {
    if (index != _currentIndex) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_screens.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);

    return WillPopScope(
      onWillPop: () async {
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return false;
        }
        await SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _screens),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    isSelected: _currentIndex == 0,
                    onTap: () => _onTap(0),
                  ),
                  _NavItem(
                    icon: Icons.assignment,
                    label: 'Tests',
                    isSelected: _currentIndex == 1,
                    onTap: () => _onTap(1),
                  ),
                  _NavItem(
                    icon: Icons.chat_bubble_outline,
                    label: 'Message',
                    isSelected: _currentIndex == 2,
                    onTap: () => _onTap(2),
                  ),
                  _NavItem(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Rewards',
                    isSelected: _currentIndex == 3,
                    onTap: () => _onTap(3),
                  ),
                  _NavItem(
                    icon: Icons.leaderboard,
                    label: 'Leaderboard',
                    isSelected: _currentIndex == 4,
                    onTap: () => _onTap(4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedColor = const Color(0xFFF27F0D);
    final unselectedColor = Theme.of(context).textTheme.bodySmall?.color;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
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
    );
  }
}
