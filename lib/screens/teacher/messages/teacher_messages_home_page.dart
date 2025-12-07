import 'package:flutter/material.dart';
import 'teacher_message_groups_screen.dart';
import '../teacher_communities_screen.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF130F23)
          : const Color(0xFFF6F5F8),
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF130F23)
            : const Color(0xFFF6F5F8),
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'Messages',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Custom Tab Selector
          Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1A2F) : const Color(0xFFE8E5EF),
              borderRadius: BorderRadius.circular(50),
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
            child: TabBarView(
              controller: _tabController,
              children: const [
                TeacherMessageGroupsScreen(),
                TeacherCommunitiesScreen(),
              ],
            ),
          ),
        ],
      ),
    );
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
                  colors: [Color(0xFF6A4FF7), Color(0xFF8B6FFF)],
                )
              : null,
          borderRadius: BorderRadius.circular(50),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF6A4FF7).withValues(alpha: 0.3),
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
                : (isDark ? const Color(0xFFB0B0B0) : const Color(0xFF7A7A7A)),
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
