import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/student/student_dashboard_screen.dart';
import '../screens/student/student_tests_screen.dart';
import '../screens/student/student_leaderboard_screen.dart';
import '../screens/student/student_messages_screen.dart';
import '../features/rewards/rewards_screen_wrapper.dart';
import 'student_bottom_nav.dart';
import '../utils/share_handler_mixin.dart';

/// Student Main Navigation Wrapper
/// Uses IndexedStack to preserve state when switching tabs
/// Prevents unnecessary rebuilds and reloading of data
class StudentMainNavigation extends StatefulWidget {
  final int initialIndex;

  const StudentMainNavigation({super.key, this.initialIndex = 0});

  @override
  State<StudentMainNavigation> createState() => _StudentMainNavigationState();
}

class _StudentMainNavigationState extends State<StudentMainNavigation>
    with ShareHandlerMixin, WidgetsBindingObserver {
  late int _currentIndex;
  final List<Widget> _screens = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      handleAppResume();
    }
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
        bottomNavigationBar: StudentBottomNav(currentIndex: _currentIndex),
      ),
    );
  }
}
