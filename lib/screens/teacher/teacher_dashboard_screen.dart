/*
import 'package:flutter/material.dart';import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

/// Minimal teacher dashboard screen to restore app routing.import '../../providers/auth_provider.dart';

/// You can replace its content later with the full dashboard UI.import '../../services/teacher_service.dart';
import '../../services/firestore_service.dart';

class TeacherDashboardScreen extends StatelessWidget {

  const TeacherDashboardScreen({Key? key}) : super(key: key);class TeacherDashboardScreen extends StatefulWidget {

  const TeacherDashboardScreen({Key? key}) : super(key: key);

  @override

  Widget build(BuildContext context) {  @override

    return Scaffold(  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();

      appBar: AppBar(}

        title: const Text('Teacher Dashboard'),

      ),class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {

      body: Center(  String? selectedClass;

        child: Column(  int selectedNavIndex = 0;

          mainAxisAlignment: MainAxisAlignment.center,

          children: [  final TeacherService _teacherService = TeacherService();

            const Icon(Icons.school, size: 48, color: Color(0xFF6366F1)),  Map<String, dynamic>? _teacherData;

            const SizedBox(height: 12),  List<Map<String, dynamic>> _students = [];

            const Text(  List<String> _classes = [];

              'Teacher Dashboard',  bool _isLoading = true;

              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),  String? _error;

            ),

            const SizedBox(height: 8),  @override

            Text(  void initState() {

              'This is a placeholder screen. The full dashboard\nUI can be restored once routing compiles cleanly.',    super.initState();

              textAlign: TextAlign.center,    _loadTeacherData();
    _runMigrationOnce();

              style: TextStyle(color: Colors.grey[600]),  }
  
  Future<void> _runMigrationOnce() async {
    try {
      await FirestoreService().migrateLegacyTestResultsStudentIds();
    } catch (e) {
      print('⚠️ Migration error: $e');
    }
  }

            ),

            const SizedBox(height: 24),  Future<void> _loadTeacherData() async {

            ElevatedButton.icon(    try {

              onPressed: () {      setState(() {

                Navigator.pushNamed(context, '/classes');        _isLoading = true;

              },        _error = null;

              icon: const Icon(Icons.class_outlined),      });

              label: const Text('Go to Classes'),

            ),      final authProvider = Provider.of<AuthProvider>(context, listen: false);

          ],      final currentUser = authProvider.currentUser;

        ),

      ),      if (currentUser == null || currentUser.email == null) {

    );        setState(() {

  }          _error = 'No user logged in';

}          _isLoading = false;

        });
        return;
      }

      // Fetch teacher data
      final teacherData = await _teacherService.getTeacherByEmail(currentUser.email!);

      if (teacherData == null) {
        setState(() {
          _error = 'Teacher data not found';
          _isLoading = false;
        });
        return;
      }

      // Format classes for dropdown (pass sections field separately)
      final classes = _teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        teacherData['sections'] ?? teacherData['section'], // Try 'sections' first, then 'section'
        classAssignments: teacherData['classAssignments'], // Fallback to classAssignments
      );

      // Fetch students (supports both classesHandled and classAssignments)
      final students = await _teacherService.getStudentsByTeacher(
        currentUser.instituteId ?? teacherData['schoolCode'] ?? '',
        teacherData['classesHandled'],
        teacherData['sections'] ?? teacherData['section'], // sections
        classAssignments: teacherData['classAssignments'],
      );

      setState(() {
        _teacherData = teacherData;
        _classes = classes;
        _students = students;
        selectedClass = classes.isNotEmpty ? classes[0] : null;
        
          // Calculate student count per class (add Map<String, int> _classStudentCounts = {}; as class variable)
          final classStudentCounts = <String, int>{};
          for (var className in classes) {
            final parts = className.split(' - ');
            if (parts.length == 2) {
              final selectedGrade = parts[0].trim();
              final selectedSection = parts[1].trim();
            
              final count = students.where((student) {
                final studentClassName = student['className']?.toString() ?? '';
                final studentGrade = studentClassName
                    .replaceAll('Grade ', '')
                    .replaceAll('grade ', '')
                    .trim();
                final studentSection = student['section']?.toString() ?? '';
              
                return studentGrade == selectedGrade &&
                    studentSection == selectedSection;
              }).length;
            
              classStudentCounts[className] = count;
            }
          }
          _classStudentCounts = classStudentCounts;
        
        _isLoading = false;
      });
    } catch (e) {
      print('� Error loading teacher data: $e');
      setState(() {
        _error = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadTeacherData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildQuickActions(),
                  const SizedBox(height: 24),
                  _buildClassSummary(),
                  const SizedBox(height: 24),
                  _buildAlerts(),
                  const SizedBox(height: 24),
                  _buildRecentActivity(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHeader() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.menu,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hello, ${_teacherData?['teacherName'] ?? currentUser?.name ?? 'Teacher'}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.groups),
                        color: const Color(0xFF6366F1),
                        tooltip: 'Group Chats',
                        onPressed: () {
                          Navigator.pushNamed(context, '/teacher-groups');
                        },
                      ),
                      Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined),
                            color: Colors.grey[600],
                            onPressed: () {},
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Color(0xFF6366F1),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButtonFormField<String>(
                  value: selectedClass,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: _classes.map((String className) {
                      final count = _classStudentCounts[className] ?? 0;
                      return DropdownMenuItem<String>(
                        value: className,
                        child: Text('$className ($count students)'),
                      );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        selectedClass = newValue;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/create-test');
                      },
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Create Test'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/ai-test-generator');
                      },
                      icon: const Icon(Icons.auto_awesome, size: 20),
                      label: const Text('Generate with AI'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(color: Color(0xFF6366F1)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildActionTile(
                icon: Icons.bar_chart,
                title: 'View Class Performance',
                onTap: () {},
                isFirst: true,
              ),
              Divider(height: 1, color: Colors.grey[200]),
              _buildActionTile(
                icon: Icons.group,
                title: 'Manage Students',
                onTap: () {},
              ),
              Divider(height: 1, color: Colors.grey[200]),
              _buildActionTile(
                icon: Icons.quiz,
                title: 'View Test Results',
                onTap: () {},
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(12) : Radius.zero,
        bottom: isLast ? const Radius.circular(12) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: const Color(0xFF6366F1),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2D3748),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassSummary() {
    List<Map<String, dynamic>> filteredStudents = _students;

    if (selectedClass != null && selectedClass!.isNotEmpty) {
      final parts = selectedClass!.split(' - ');
      if (parts.length == 2) {
        final selectedGrade = parts[0].trim();
        final selectedSection = parts[1].trim();

        filteredStudents = _students.where((student) {
          final studentClassName = student['className']?.toString() ?? '';
          final studentGrade = studentClassName.replaceAll('Grade ', '').replaceAll('grade ', '').trim();
          final studentSection = student['section']?.toString() ?? '';

          return studentGrade == selectedGrade && studentSection == selectedSection;
        }).toList();
      }
    }

    final totalStudents = filteredStudents.length;
    final totalAllStudents = _students.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Class Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.people,
                iconColor: Colors.green,
                iconBgColor: Colors.green.withOpacity(0.1),
                value: '$totalStudents',
                label: 'Students in Class',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.school,
                iconColor: Colors.orange,
                iconBgColor: Colors.orange.withOpacity(0.1),
                value: '$totalAllStudents',
                label: 'Total Students',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A202C),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '0',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  'No pending alerts',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.history,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  'No recent activity',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.dashboard,
                label: 'Dashboard',
                index: 0,
              ),
              _buildNavItem(
                icon: Icons.school,
                label: 'Classes',
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.quiz,
                label: 'Tests',
                index: 2,
              ),
              _buildNavItem(
                icon: Icons.leaderboard,
                label: 'Leaderboard',
                index: 3,
              ),
              _buildNavItem(
                icon: Icons.person,
                label: 'Profile',
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = selectedNavIndex == index;
    final color = isSelected ? const Color(0xFF6366F1) : Colors.grey[500];

    return InkWell(
      onTap: () {
        setState(() {
          selectedNavIndex = index;
        });
        if (index == 1) {
          Navigator.pushNamed(context, '/classes');
        } else if (index == 2) {
          Navigator.pushNamed(context, '/tests');
        } else if (index == 3) {
          Navigator.pushNamed(context, '/leaderboard');
        } else if (index == 4) {
          Navigator.pushNamed(context, '/profile');
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
*/

import 'package:flutter/material.dart';
import '../../widgets/teacher_bottom_nav.dart';

/// Minimal teacher dashboard screen to restore app routing.
/// You can replace its content later with the full dashboard UI.
class TeacherDashboardScreen extends StatelessWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher Dashboard')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.school, size: 48, color: Color(0xFF6366F1)),
            const SizedBox(height: 12),
            const Text(
              'Teacher Dashboard',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'This is a placeholder screen. The full dashboard\nUI can be restored once routing compiles cleanly.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/classes'),
              icon: const Icon(Icons.class_outlined),
              label: const Text('Go to Classes'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const TeacherBottomNav(selectedIndex: 0),
    );
  }
}
