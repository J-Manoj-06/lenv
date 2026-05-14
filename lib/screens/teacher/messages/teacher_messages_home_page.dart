import 'package:flutter/material.dart';
import '../../../widgets/main_nav_swipe_notification.dart';
import 'teacher_message_groups_screen.dart';
import '../teacher_community_screen.dart';

class TeacherMessagesHomePage extends StatefulWidget {
  const TeacherMessagesHomePage({super.key});

  @override
  State<TeacherMessagesHomePage> createState() =>
      _TeacherMessagesHomePageState();
}

class _TeacherMessagesHomePageState extends State<TeacherMessagesHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  bool _navSwipeTriggered = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedIndex = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(
          'Messages',
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            color: theme.iconTheme.color,
            tooltip: 'Profile',
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Custom Tab Selector
          Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surface
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: theme.dividerColor, width: 1),
            ),
            child: Row(
              children: [
                Expanded(child: _buildTabButton('GROUPS', 0, isDark)),
                Expanded(child: _buildTabButton('COMMUNITIES', 1, isDark)),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleTabScrollNotification,
              child: TabBarView(
                controller: _tabController,
                physics: const PageScrollPhysics(),
                children: const [
                  TeacherMessageGroupsScreen(),
                  TeacherCommunityScreen(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _handleTabScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }

    if (notification is ScrollEndNotification) {
      _navSwipeTriggered = false;
      return false;
    }

    if (notification is! OverscrollNotification || _navSwipeTriggered) {
      return false;
    }

    final isAtFirstTab = _selectedIndex == 0;
    final isAtLastTab = _selectedIndex == _tabController.length - 1;

    if (notification.overscroll < 0 && isAtFirstTab) {
      _navSwipeTriggered = true;
      MainNavSwipeNotification(MainNavSwipeDirection.right).dispatch(context);
    } else if (notification.overscroll > 0 && isAtLastTab) {
      _navSwipeTriggered = true;
      MainNavSwipeNotification(MainNavSwipeDirection.left).dispatch(context);
    }

    return false;
  }

  Widget _buildTabButton(String label, int index, bool isDark) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF355872), Color(0xFF355872)],
                )
              : null,
          borderRadius: BorderRadius.circular(50),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF355872).withValues(alpha: 0.25),
                    blurRadius: 15,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
