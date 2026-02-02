import 'dart:ui';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import '../screens/institute/institute_dashboard_screen.dart';
import '../screens/institute/institute_staff_screen.dart';
import '../screens/institute/institute_messages_screen.dart';
import '../screens/institute/institute_insights_screen.dart';
import '../screens/institute/institute_profile_screen.dart';
import '../utils/share_handler_mixin.dart';

class InstituteMainNavigation extends StatefulWidget {
  const InstituteMainNavigation({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<InstituteMainNavigation> createState() =>
      _InstituteMainNavigationState();
}

class _InstituteMainNavigationState extends State<InstituteMainNavigation>
    with ShareHandlerMixin, WidgetsBindingObserver {
  late int _currentIndex;
  late final List<Widget> _screens;

  static const Color _primary = Color(0xFF146D7A);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    _screens = [
      const InstituteDashboardScreen(),
      const InstituteStaffScreen(),
      const InstituteMessagesScreen(),
      const InstituteInsightsScreen(),
      const InstituteProfileScreen(),
    ];
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

  void _onTap(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        bottomNavigationBar: _GlassyBottomBar(
          currentIndex: _currentIndex,
          onTap: _onTap,
          primary: _primary,
        ),
      ),
    );
  }
}

class _GlassyBottomBar extends StatelessWidget {
  const _GlassyBottomBar({
    required this.currentIndex,
    required this.onTap,
    required this.primary,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final inactive = Colors.grey[400];

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B1113).withOpacity(0.9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 66,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard,
                    label: 'Dashboard',
                    isSelected: currentIndex == 0,
                    activeColor: primary,
                    inactiveColor: inactive,
                    onTap: () => onTap(0),
                  ),
                  _NavItem(
                    icon: Icons.group_outlined,
                    selectedIcon: Icons.group,
                    label: 'Staff',
                    isSelected: currentIndex == 1,
                    activeColor: primary,
                    inactiveColor: inactive,
                    onTap: () => onTap(1),
                  ),
                  _NavItem(
                    icon: Icons.chat_bubble_outline,
                    selectedIcon: Icons.chat_bubble,
                    label: 'Messages',
                    isSelected: currentIndex == 2,
                    activeColor: primary,
                    inactiveColor: inactive,
                    onTap: () => onTap(2),
                  ),
                  _NavItem(
                    icon: Icons.bar_chart_outlined,
                    selectedIcon: Icons.bar_chart,
                    label: 'Insights',
                    isSelected: currentIndex == 3,
                    activeColor: primary,
                    inactiveColor: inactive,
                    onTap: () => onTap(3),
                  ),
                  _NavItem(
                    icon: Icons.person_outline,
                    selectedIcon: Icons.person,
                    label: 'Profile',
                    isSelected: currentIndex == 4,
                    activeColor: primary,
                    inactiveColor: inactive,
                    onTap: () => onTap(4),
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
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final Color activeColor;
  final Color? inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                color: isSelected ? activeColor : inactiveColor,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
