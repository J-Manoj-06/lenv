import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../screens/parent/parent_dashboard_screen.dart';
import '../screens/parent/parent_rewards_screen.dart';
import '../screens/parent/parent_messages_screen.dart';
import '../screens/parent/parent_tests_screen.dart';
import '../screens/parent/parent_attendance_screen.dart';
import '../utils/share_handler_mixin.dart';
import '../providers/parent_provider.dart';
import '../providers/auth_provider.dart';
import 'main_nav_swipe_notification.dart';

/// Parent Main Navigation Wrapper
/// Provides 5 tabs: Dashboard, Rewards, Messages, Tests, Attendance
/// Uses IndexedStack to preserve state while switching.
class ParentMainNavigation extends StatefulWidget {
  final int initialIndex;
  const ParentMainNavigation({super.key, this.initialIndex = 0});

  @override
  State<ParentMainNavigation> createState() => _ParentMainNavigationState();
}

class _ParentMainNavigationState extends State<ParentMainNavigation>
    with ShareHandlerMixin, WidgetsBindingObserver {
  static const Color parentGreen = Color(0xFF14A670);
  static const int _tabCount = 5;
  static const double _swipeVelocityThreshold = 320;

  late final PageController _pageController;
  late int _currentIndex;
  bool _initialized = false;

  // Screens are created once so IndexedStack preserves their state.
  // Dashboard receives a callback to switch to the Rewards tab directly.
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _tabCount - 1);
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
    _screens = [
      ParentDashboardScreen(onSwitchToRewards: () => _goToTab(1)),
      const ParentRewardsScreen(),
      const ParentMessagesScreen(),
      const ParentTestsScreen(),
      const ParentAttendanceScreen(),
    ];
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
    final theme = Theme.of(context);
    return Consumer2<AuthProvider, ParentProvider>(
      builder: (context, authProvider, parentProvider, child) {
        // Check if loading (only on dashboard tab)
        final isLoading =
            _currentIndex == 0 &&
            (!authProvider.isInitialized || parentProvider.isLoadingChildren);

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
            bottomNavigationBar: IgnorePointer(
              ignoring: isLoading,
              child: Opacity(
                opacity: isLoading ? 0.5 : 1.0,
                child: Container(
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
                            icon: Icons.dashboard_outlined,
                            selectedIcon: Icons.dashboard,
                            label: 'Dashboard',
                            isSelected: _currentIndex == 0,
                            onTap: () => _goToTab(0),
                            color: parentGreen,
                          ),
                          _NavItem(
                            icon: Icons.card_giftcard_outlined,
                            selectedIcon: Icons.card_giftcard,
                            label: 'Rewards',
                            isSelected: _currentIndex == 1,
                            onTap: () => _goToTab(1),
                            color: parentGreen,
                          ),
                          _NavItem(
                            icon: Icons.message_outlined,
                            selectedIcon: Icons.message,
                            label: 'Messages',
                            isSelected: _currentIndex == 2,
                            onTap: () => _goToTab(2),
                            color: parentGreen,
                          ),
                          _NavItem(
                            icon: Icons.quiz_outlined,
                            selectedIcon: Icons.quiz,
                            label: 'Tests',
                            isSelected: _currentIndex == 3,
                            onTap: () => _goToTab(3),
                            color: parentGreen,
                          ),
                          _NavItem(
                            icon: Icons.calendar_today_outlined,
                            selectedIcon: Icons.calendar_today,
                            label: 'Attendance',
                            isSelected: _currentIndex == 4,
                            onTap: () => _goToTab(4),
                            color: parentGreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

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
  final Color color;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Replace deprecated withOpacity with alpha adjustment for future compatibility.
    final baseIconColor = Theme.of(context).iconTheme.color;
    final unselectedColor = baseIconColor?.withAlpha((0.6 * 255).round());
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? color : unselectedColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : unselectedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
