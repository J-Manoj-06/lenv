import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/parent/parent_dashboard_screen.dart';
import '../screens/parent/parent_rewards_screen.dart';
import '../screens/parent/parent_messages_screen.dart';
import '../screens/parent/parent_tests_screen.dart';
import '../screens/parent/parent_reports_screen.dart';

/// Parent Main Navigation Wrapper
/// Provides 5 tabs: Dashboard, Rewards, Messages, Tests, Reports
/// Uses IndexedStack to preserve state while switching.
class ParentMainNavigation extends StatefulWidget {
  final int initialIndex;
  const ParentMainNavigation({super.key, this.initialIndex = 0});

  @override
  State<ParentMainNavigation> createState() => _ParentMainNavigationState();
}

class _ParentMainNavigationState extends State<ParentMainNavigation> {
  static const Color parentGreen = Color(0xFF14A670);
  late int _currentIndex;
  bool _initialized = false;

  // Define screens directly instead of using a list
  static const List<Widget> _screens = [
    ParentDashboardScreen(),
    ParentRewardsScreen(),
    ParentMessagesScreen(),
    ParentTestsScreen(),
    ParentReportsScreen(),
  ];

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
    }
  }

  void _onTap(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard,
                    label: 'Dashboard',
                    isSelected: _currentIndex == 0,
                    onTap: () => _onTap(0),
                    color: parentGreen,
                  ),
                  _NavItem(
                    icon: Icons.card_giftcard_outlined,
                    selectedIcon: Icons.card_giftcard,
                    label: 'Rewards',
                    isSelected: _currentIndex == 1,
                    onTap: () => _onTap(1),
                    color: parentGreen,
                  ),
                  _NavItem(
                    icon: Icons.message_outlined,
                    selectedIcon: Icons.message,
                    label: 'Messages',
                    isSelected: _currentIndex == 2,
                    onTap: () => _onTap(2),
                    color: parentGreen,
                  ),
                  _NavItem(
                    icon: Icons.quiz_outlined,
                    selectedIcon: Icons.quiz,
                    label: 'Tests',
                    isSelected: _currentIndex == 3,
                    onTap: () => _onTap(3),
                    color: parentGreen,
                  ),
                  _NavItem(
                    icon: Icons.assessment_outlined,
                    selectedIcon: Icons.assessment,
                    label: 'Reports',
                    isSelected: _currentIndex == 4,
                    onTap: () => _onTap(4),
                    color: parentGreen,
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
