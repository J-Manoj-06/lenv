import 'package:flutter/material.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({Key? key}) : super(key: key);

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedTabIndex = 0;
  String _selectedClassFilter = 'All Classes';

  final List<String> _tabs = ['All', 'Live', 'Scheduled', 'Past'];
  final List<String> _classFilters = [
    'All Classes',
    'Grade 10 - Math',
    'Grade 11 - Physics'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              _buildTabs(),
              _buildClassFilters(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  child: Column(
                    children: [
                      _buildLiveTestSection(),
                      const SizedBox(height: 24),
                      _buildUpcomingSection(),
                      const SizedBox(height: 24),
                      _buildCompletedSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _buildFAB(),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 48),
              const Text(
                'Tests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111418),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                iconSize: 24,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notifications')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by test name...',
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6B7280)),
          filled: true,
          fillColor: const Color(0xFFF6F7F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          setState(() {});
        },
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(_tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedTabIndex = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? const Color(0xFF6366F1)
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  _tabs[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? const Color(0xFF6366F1)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildClassFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // All Classes dropdown
            InkWell(
              onTap: () {
                _showClassFilterSheet();
              },
              child: Container(
                height: 32,
                padding: const EdgeInsets.only(left: 16, right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedClassFilter,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_more,
                      size: 18,
                      color: Color(0xFF6366F1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Individual class filters
            ...(_classFilters.skip(1).map((className) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedClassFilter = className;
                    });
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7F8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        className,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live Test',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),
        _buildTestCard(
          title: 'Mid-Term Physics Exam',
          subtitle: 'Grade 11 - Physics',
          status: 'Live',
          statusColor: const Color(0xFF10B981),
          statusBgColor: const Color(0xFFD1FAE5),
          footerIcon: Icons.timer_outlined,
          footerText: 'Ends in: 45:32',
          footerIconColor: const Color(0xFF6366F1),
          showEditButton: true,
          showDeleteButton: true,
          showStatsButton: true,
        ),
      ],
    );
  }

  Widget _buildUpcomingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upcoming',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),
        _buildTestCard(
          title: 'Algebra Weekly Quiz',
          subtitle: 'Grade 10 - Math',
          status: 'Scheduled',
          statusColor: const Color(0xFF6366F1),
          statusBgColor: const Color(0xFF6366F1).withOpacity(0.2),
          footerIcon: Icons.calendar_today_outlined,
          footerText: '28 Oct 2023, 10:00 AM',
          footerIconColor: const Color(0xFF6B7280),
          showEditButton: true,
          showDeleteButton: true,
        ),
      ],
    );
  }

  Widget _buildCompletedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Completed',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),
        _buildTestCard(
          title: 'Calculus Pop Quiz',
          subtitle: 'Grade 10 - Math',
          status: 'Past',
          statusColor: const Color(0xFF1F2937),
          statusBgColor: const Color(0xFFE5E7EB),
          footerIcon: Icons.leaderboard_outlined,
          footerText: 'Avg. Score: 82%',
          footerIconColor: const Color(0xFF6366F1),
          showStatsButton: true,
          showDeleteButton: true,
        ),
        const SizedBox(height: 16),
        _buildTestCard(
          title: 'Final Chemistry Paper',
          subtitle: 'Grade 11 - Physics',
          status: 'Past',
          statusColor: const Color(0xFF1F2937),
          statusBgColor: const Color(0xFFE5E7EB),
          footerIcon: Icons.leaderboard_outlined,
          footerText: 'Avg. Score: 76%',
          footerIconColor: const Color(0xFF6366F1),
          showStatsButton: true,
          showDeleteButton: true,
        ),
      ],
    );
  }

  Widget _buildTestCard({
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required Color statusBgColor,
    required IconData footerIcon,
    required String footerText,
    required Color footerIconColor,
    bool showEditButton = false,
    bool showDeleteButton = false,
    bool showStatsButton = false,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/test-result',
          arguments: {
            'name': title,
            'class': subtitle,
            'status': status,
            'endTime': footerText.contains('Ends in') 
                ? footerText.replaceAll('Ends in: ', '') 
                : footerText.replaceAll('28 Oct 2023, 10:00 AM', '24 Oct 2023, 10:00 AM'),
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Footer
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFF3F4F6), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(footerIcon, size: 18, color: footerIconColor),
                    const SizedBox(width: 8),
                    Text(
                      footerText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (showStatsButton)
                      IconButton(
                        icon: const Icon(Icons.bar_chart_outlined),
                        iconSize: 20,
                        color: const Color(0xFF6B7280),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('View stats for $title')),
                          );
                        },
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    if (showEditButton)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        iconSize: 20,
                        color: const Color(0xFF6B7280),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Edit $title')),
                          );
                        },
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    if (showDeleteButton)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        iconSize: 20,
                        color: const Color(0xFF6B7280),
                        onPressed: () {
                          _showDeleteDialog(title);
                        },
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Positioned(
      bottom: 100,
      right: 24,
      child: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/create-test');
        },
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add, size: 30, color: Colors.white),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 80,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.dashboard_outlined, 'Dashboard', false, () {
                Navigator.pushReplacementNamed(context, '/teacher-dashboard');
              }),
              _buildNavItem(Icons.school_outlined, 'Classes', false, () {
                Navigator.pushReplacementNamed(context, '/classes');
              }),
              _buildNavItem(Icons.quiz, 'Tests', true, () {}),
              _buildNavItem(Icons.leaderboard_outlined, 'Leaderboard', false, () {
                Navigator.pushReplacementNamed(context, '/leaderboard');
              }),
              _buildNavItem(Icons.person_outline, 'Profile', false, () {
                Navigator.pushReplacementNamed(context, '/profile');
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClassFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter by Class',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 16),
              ..._classFilters.map((className) {
                return ListTile(
                  title: Text(className),
                  trailing: _selectedClassFilter == className
                      ? const Icon(Icons.check, color: Color(0xFF6366F1))
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedClassFilter = className;
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteDialog(String testName) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Test'),
          content: Text('Are you sure you want to delete "$testName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$testName deleted')),
                );
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}
