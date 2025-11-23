import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/teacher_service.dart';
import '../../widgets/teacher_bottom_nav.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({Key? key}) : super(key: key);

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  int selectedNavIndex = 1; // Classes is selected

  final TeacherService _teacherService = TeacherService();
  Map<String, dynamic>? _teacherData;
  List<String> _classNames = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // Wait for auth initialization
    await authProvider.ensureInitialized();
    await _loadTeacherData();
  }

  Future<void> _loadTeacherData() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      if (currentUser == null) {
        // If auth still not ready show loading instead of error
        if (!authProvider.isInitialized) {
          setState(() {
            _error = null;
          });
          return;
        }
        setState(() {
          _error = 'No user logged in';
        });
        return;
      }

      // Fetch teacher data
      final teacherData = await _teacherService.getTeacherByEmail(
        currentUser.email,
      );

      if (teacherData == null) {
        setState(() {
          _error = 'Teacher data not found';
        });
        return;
      }

      // Use sections array if present, otherwise fallback to single string
      final dynamic sections =
          teacherData['sections'] ?? teacherData['section'];

      // Get formatted classes (e.g., ["4 - A", "4 - B"])
      final classNames = _teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        sections,
        classAssignments: teacherData['classAssignments'],
      );

      setState(() {
        _teacherData = teacherData;
        _classNames = classNames;
        _error = null;
      });
    } catch (e) {
      print('❌ Error loading teacher data: $e');
      setState(() {
        _error = 'Failed to load teacher data: $e';
      });
    }
  }

  // Get gradient colors based on section
  List<Color> _getSectionColors(String section) {
    switch (section.toUpperCase()) {
      case 'A':
        return [const Color(0xFF667EEA), const Color(0xFF764BA2)];
      case 'B':
        return [const Color(0xFFF093FB), const Color(0xFFF5576C)];
      case 'C':
        return [const Color(0xFF4FACFE), const Color(0xFF00F2FE)];
      case 'D':
        return [const Color(0xFF43E97B), const Color(0xFF38F9D7)];
      default:
        return [const Color(0xFF6366F1), const Color(0xFF8B5CF6)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (_error != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
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
        ),
      );
    }

    final authProviderListen = Provider.of<AuthProvider>(
      context,
    ); // listen to auth changes
    if (!authProviderListen.isInitialized) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_teacherData == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final schoolId =
        currentUser?.instituteId ?? _teacherData?['schoolCode'] ?? '';
    final sections = _teacherData?['sections'] ?? _teacherData?['section'];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _teacherService.getStudentsByTeacherStream(
                schoolId,
                _teacherData?['classesHandled'],
                sections,
                classAssignments: _teacherData?['classAssignments'],
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                final allStudents = snapshot.data ?? [];
                final classes = _buildClassItems(allStudents);

                if (classes.isEmpty) {
                  return const Center(child: Text('No classes found'));
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  child: Column(
                    children: classes.map((classItem) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildClassListItem(classItem),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ClassItem> _buildClassItems(List<Map<String, dynamic>> allStudents) {
    final classes = <ClassItem>[];
    final grade =
        _teacherData?['classesHandled']?[0]
            ?.toString()
            .replaceAll('Grade ', '')
            .replaceAll('grade ', '')
            .trim() ??
        '';

    print('📚 Building class items from ${allStudents.length} total students');
    print('📚 Class names to process: $_classNames');

    for (var className in _classNames) {
      // Extract section from className (e.g., "5 - A" -> "A")
      final section = className.split(' - ').last.trim();
      // Extract grade from className (e.g., "7 - A" -> "7")
      final gradeNum = className.split(' - ').first.trim();

      print(
        '📚 Processing class: $className (Grade: $gradeNum, Section: $section)',
      );

      // Filter students for THIS specific section
      final studentsInSection = allStudents.where((student) {
        final studentSection = student['section']?.toString().trim() ?? '';
        final studentClassName = student['className']?.toString() ?? '';
        final studentGrade = studentClassName
            .replaceAll('Grade ', '')
            .replaceAll('grade ', '')
            .trim();

        final matches = studentGrade == gradeNum && studentSection == section;

        if (matches) {
          print(
            '   ✅ Matched student: ${student['studentName']} (Grade: $studentGrade, Section: $studentSection)',
          );
        }

        return matches;
      }).toList();

      print('   📊 Found ${studentsInSection.length} students in $className');

      classes.add(
        ClassItem(
          name: 'Grade $className',
          studentCount: studentsInSection.length,
          averageScore: 0,
          section: section,
          grade: grade,
        ),
      );
    }

    return classes;
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.menu, size: 28),
                onPressed: () {
                  // Handle menu
                },
                color: Theme.of(context).iconTheme.color,
              ),
              Expanded(
                child: Text(
                  'My Classes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: () {
                  _showAddClassDialog();
                },
                color: Theme.of(context).iconTheme.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassListItem(ClassItem classItem) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Gradient section indicator
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: Container(
              width: 100,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getSectionColors(classItem.section),
                ),
              ),
              child: Center(
                child: Text(
                  classItem.section,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    classItem.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.group,
                        size: 14,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${classItem.studentCount} Students',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 100,
                    child: ElevatedButton(
                      onPressed: () {
                        _enterClass(classItem);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Enter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return const TeacherBottomNav(selectedIndex: 1);
  }

  void _showAddClassDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Class'),
        content: const Text(
          'This feature will allow you to create a new class.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add class feature coming soon!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _enterClass(ClassItem classItem) {
    Navigator.pushNamed(context, '/student-list', arguments: classItem.name);
  }
}

// Class model
class ClassItem {
  final String name;
  final int studentCount;
  final int averageScore;
  final String section;
  final String grade;

  ClassItem({
    required this.name,
    required this.studentCount,
    required this.averageScore,
    required this.section,
    required this.grade,
  });
}
