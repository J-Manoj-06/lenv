import 'package:flutter/material.dart';
import 'groups_list_page.dart';
import '../student/student_community_screen.dart';
import '../../widgets/main_nav_swipe_notification.dart';

class MessagesHomePage extends StatefulWidget {
  final String studentId;

  const MessagesHomePage({super.key, required this.studentId});

  @override
  State<MessagesHomePage> createState() => _MessagesHomePageState();
}

class _MessagesHomePageState extends State<MessagesHomePage>
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
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'Messages',
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Custom Tab Selector
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surface.withValues(alpha: 0.6)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: _buildTabButton('GROUPS', 0)),
                Expanded(child: _buildTabButton('COMMUNITIES', 1)),
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
                children: [
                  GroupsListPage(studentId: widget.studentId),
                  const StudentCommunityScreen(),
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

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedIndex == index;
    const primaryColor = Color(0xFFF97316);

    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
