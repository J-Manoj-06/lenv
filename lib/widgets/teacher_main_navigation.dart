import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/teacher/teacher_dashboard.dart';
import '../screens/teacher/classes_screen.dart';
import '../screens/teacher/tests_screen.dart';
import '../screens/teacher/messages/teacher_messages_home_page.dart';
import '../screens/teacher/leaderboard_screen.dart';
import '../utils/share_handler_mixin.dart';
import 'main_nav_swipe_notification.dart';

/// Teacher Main Navigation Wrapper
/// Uses IndexedStack to preserve state when switching tabs
/// Prevents unnecessary rebuilds and reloading of data
class TeacherMainNavigation extends StatefulWidget {
  final int initialIndex;

  const TeacherMainNavigation({super.key, this.initialIndex = 0});

  @override
  State<TeacherMainNavigation> createState() => _TeacherMainNavigationState();
}

class _TeacherMainNavigationState extends State<TeacherMainNavigation>
    with ShareHandlerMixin, WidgetsBindingObserver {
  static const int _tabCount = 5;
  static const double _swipeVelocityThreshold = 320;

  late final PageController _pageController;
  late int _currentIndex;
  final List<Widget> _screens = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _tabCount - 1);
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
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
          const TeacherDashboardScreen(),
          const TestsScreen(),
          // Messages page with tabs for Groups and Communities
          const TeacherMessagesHomePage(),
          const ClassesScreen(),
          const LeaderboardScreen(),
        ]);
      }
    }
  }

  Future<void> _goToTab(int index) async {
    if (index == _currentIndex || !mounted) return;

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handleMainNavSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < _swipeVelocityThreshold) return;

    if (velocity < 0) {
      _goToTab((_currentIndex + 1).clamp(0, _tabCount - 1));
    } else {
      _goToTab((_currentIndex - 1).clamp(0, _tabCount - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_screens.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        if (_currentIndex != 0) {
          _goToTab(0);
          return;
        }

        SystemNavigator.pop();
      },
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: _handleMainNavSwipe,
          child: NotificationListener<MainNavSwipeNotification>(
            onNotification: (notification) {
              final targetIndex =
                  notification.direction == MainNavSwipeDirection.left
                  ? (_currentIndex + 1).clamp(0, _tabCount - 1)
                  : (_currentIndex - 1).clamp(0, _tabCount - 1);
              _goToTab(targetIndex);
              return true;
            },
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
        ),
        bottomNavigationBar: _GlassyBottomBar(
          currentIndex: _currentIndex,
          onTap: _goToTab,
        ),
      ),
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
    const primary = Color(0xFF355872);
    final inactive = Colors.grey[400];

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
                maxLines: 1,
                overflow: TextOverflow.visible,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassyBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GlassyBottomBar({required this.currentIndex, required this.onTap});

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
                      _NavItem(
                        icon: Icons.dashboard_outlined,
                        selectedIcon: Icons.dashboard,
                        label: 'Home',
                        isSelected: currentIndex == 0,
                        onTap: () => onTap(0),
                      ),
                      _NavItem(
                        icon: Icons.assignment_outlined,
                        selectedIcon: Icons.assignment,
                        label: 'Tests',
                        isSelected: currentIndex == 1,
                        onTap: () => onTap(1),
                      ),
                      _NavItem(
                        icon: Icons.message_outlined,
                        selectedIcon: Icons.message,
                        label: 'Chats',
                        isSelected: currentIndex == 2,
                        onTap: () => onTap(2),
                      ),
                      _NavItem(
                        icon: Icons.groups_outlined,
                        selectedIcon: Icons.groups,
                        label: 'Classes',
                        isSelected: currentIndex == 3,
                        onTap: () => onTap(3),
                      ),
                      _NavItem(
                        icon: Icons.leaderboard_outlined,
                        selectedIcon: Icons.leaderboard,
                        label: 'Ranks',
                        isSelected: currentIndex == 4,
                        onTap: () => onTap(4),
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
