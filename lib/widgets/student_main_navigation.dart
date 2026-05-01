import 'package:flutter/gestures.dart';
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
  static const int _tabCount = 5;
  static const double _swipeDistanceThreshold = 48;
  static const double _swipeDominanceThreshold = 1.2;

  late final PageController _pageController;
  late int _currentIndex;
  final List<Widget> _screens = [];
  bool _initialized = false;
  bool _permissionPromptInProgress = false;
  int? _activePointerId;
  Offset? _swipeStartPosition;
  Offset? _swipeLastPosition;
  bool _swipeConsumed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _tabCount - 1);
    _pageController = PageController(initialPage: _currentIndex);
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
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToTab(int index) async {
    if (index == _currentIndex || !mounted) return;

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _resetSwipeTracking() {
    _activePointerId = null;
    _swipeStartPosition = null;
    _swipeLastPosition = null;
    _swipeConsumed = false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointerId != null) return;

    _activePointerId = event.pointer;
    _swipeStartPosition = event.position;
    _swipeLastPosition = event.position;
    _swipeConsumed = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activePointerId != event.pointer || _swipeStartPosition == null) {
      return;
    }

    _swipeLastPosition = event.position;
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    if (_activePointerId != event.pointer || _swipeStartPosition == null) {
      _resetSwipeTracking();
      return;
    }

    _swipeLastPosition = event.position;
    final delta = _swipeLastPosition!.dx - _swipeStartPosition!.dx;
    final verticalDelta = (_swipeLastPosition!.dy - _swipeStartPosition!.dy).abs();
    final horizontalDistance = delta.abs();

    final isSwipe = horizontalDistance >= _swipeDistanceThreshold &&
        horizontalDistance > verticalDelta * _swipeDominanceThreshold;

    if (!_swipeConsumed && isSwipe) {
      _swipeConsumed = true;
      final targetIndex = delta < 0
          ? (_currentIndex + 1).clamp(0, _tabCount - 1)
          : (_currentIndex - 1).clamp(0, _tabCount - 1);

      if (targetIndex != _currentIndex) {
        await _goToTab(targetIndex);
      }
    }

    _resetSwipeTracking();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_activePointerId == event.pointer) {
      _resetSwipeTracking();
    }
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
          await _goToTab(0);
          return false;
        }
        await SystemNavigator.pop();
        return false;
      },
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    if (_currentIndex == index) return;
                    setState(() => _currentIndex = index);
                  },
                  children: _screens
                      .map((screen) => _KeepAlivePage(child: screen))
                      .toList(growable: false),
                ),
              ),
              if (_currentIndex != 0)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 16,
                  child: _buildProfileQuickAccess(),
                ),
            ],
          ),
        ),
        bottomNavigationBar: StudentBottomNav(
          currentIndex: _currentIndex,
          onTabSelected: _goToTab,
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

class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
