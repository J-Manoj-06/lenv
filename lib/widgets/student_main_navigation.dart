import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../screens/student/student_dashboard_screen.dart';
import '../screens/student/student_tests_screen.dart';
import '../screens/student/student_leaderboard_screen.dart';
import '../screens/student/student_messages_screen.dart';
import '../screens/student/student_profile_screen.dart';
import '../screens/permissions/usage_access_permission_screen.dart';
import '../features/rewards/rewards_screen_wrapper.dart';
import 'student_bottom_nav.dart';
import '../utils/share_handler_mixin.dart';
import '../providers/student_provider.dart';
import '../providers/profile_dp_provider.dart';
import '../widgets/profile_avatar_widget.dart';
import '../services/student_usage_service.dart';

/// Student Main Navigation Wrapper
/// Uses IndexedStack to preserve state when switching tabs
/// Prevents unnecessary rebuilds and reloading of data
class StudentMainNavigation extends StatefulWidget {
  final int initialIndex;
  final bool shouldCheckUsagePermissionOnEntry;

  const StudentMainNavigation({
    super.key,
    this.initialIndex = 0,
    this.shouldCheckUsagePermissionOnEntry = false,
  });

  @override
  State<StudentMainNavigation> createState() => _StudentMainNavigationState();
}

class _StudentMainNavigationState extends State<StudentMainNavigation>
    with ShareHandlerMixin, WidgetsBindingObserver {
  late int _currentIndex;
  final List<Widget> _screens = [];
  bool _initialized = false;
  bool _permissionPromptInProgress = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    if (widget.shouldCheckUsagePermissionOnEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureUsagePermissionOnEntry();
      });
    }
  }

  Future<void> _ensureUsagePermissionOnEntry() async {
    if (!mounted || _permissionPromptInProgress || !Platform.isAndroid) return;

    _permissionPromptInProgress = true;
    try {
      final usageService = StudentUsageService();
      final granted = await usageService.isUsagePermissionGranted();
      if (!mounted || granted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UsageAccessPermissionScreen()),
      );
    } catch (_) {
      // Do not block student navigation if permission prompt flow fails.
    } finally {
      _permissionPromptInProgress = false;
    }
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

  @override
  Widget build(BuildContext context) {
    if (_screens.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
        body: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(index: _currentIndex, children: _screens),
            ),
            if (_currentIndex != 0)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: _buildProfileQuickAccess(),
              ),
          ],
        ),
        bottomNavigationBar: StudentBottomNav(
          currentIndex: _currentIndex,
          onTabSelected: (index) {
            if (_currentIndex == index) return;
            setState(() => _currentIndex = index);
          },
        ),
      ),
    );
  }

  Widget _buildProfileQuickAccess() {
    return Consumer<ProfileDPProvider>(
      builder: (context, dpProvider, _) {
        final studentName =
            Provider.of<StudentProvider>(
              context,
              listen: false,
            ).currentStudent?.name ??
            'Student';
        final imageUrl = dpProvider.currentUserDP;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StudentProfileScreen(),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            elevation: 6,
            shape: const CircleBorder(),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? ProfileAvatarWidget(
                    imageUrl: imageUrl,
                    name: studentName,
                    size: 44,
                    showBorder: true,
                    borderColor: const Color(0xFFF2800D),
                    borderWidth: 2,
                  )
                : ProfileAvatarWidget(
                    name: studentName,
                    size: 44,
                    showBorder: true,
                    borderColor: const Color(0xFFF2800D),
                    borderWidth: 2,
                    circleBackgroundColor: const Color(0xFF3D3D3D),
                    initialsColor: const Color(0xFFF2800D),
                  ),
          ),
        );
      },
    );
  }
}
