import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/offline_cache_manager.dart';
import '../../services/teacher_service.dart';
import 'export_attendance_page.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

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
      var currentUser = authProvider.currentUser;

      // If user is null, retry auth initialization once
      if (currentUser == null) {
        await authProvider.initializeAuth();
        currentUser = authProvider.currentUser;
      }

      // Try Hive cache first when offline (user may be null or teacher fetch may fail)
      Map<String, dynamic>? teacherData;

      if (currentUser != null) {
        teacherData = await _teacherService.getTeacherByEmail(
          currentUser.email,
        );
      }

      // Fallback to offline Hive cache when network is unavailable or user is null
      teacherData ??= await _loadTeacherDataFromHiveCache(
          currentUser?.uid ?? '',
        );

      if (teacherData == null) {
        setState(() {
          _error = currentUser == null
              ? 'No user logged in'
              : 'Teacher data not found';
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
      setState(() {
        _error = 'Failed to load teacher data: $e';
      });
    }
  }

  /// Load teacher data from the Hive cache populated by the dashboard
  Future<Map<String, dynamic>?> _loadTeacherDataFromHiveCache(
    String userId,
  ) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.initialize();
      Map<String, dynamic>? cached;
      if (userId.isNotEmpty) {
        cached = cacheManager.getCachedDashboard(
          userId: userId,
          role: 'teacher',
        );
      }
      cached ??= cacheManager.getLastCachedTeacherDashboard();
      if (cached != null) {
        final rawTeacherData = cached['teacherData'];
        if (rawTeacherData is Map) {
          return Map<String, dynamic>.from(rawTeacherData);
        }
      }
    } catch (_) {}
    return null;
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
        return [const Color(0xFF355872), const Color(0xFF4A7A99)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;

    if (_error != null) {
      return Scaffold(
        backgroundColor: bgColor,
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
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_teacherData == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final schoolId =
        currentUser?.instituteId ?? _teacherData?['schoolCode'] ?? '';
    final sections = _teacherData?['sections'] ?? _teacherData?['section'];

    return Scaffold(
      backgroundColor: bgColor,
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
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // On error, show cached data silently instead of showing error UI
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'classes_export_fab',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExportAttendancePage()),
          );
        },
        backgroundColor: const Color(0xFF355872),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.file_download),
        label: const Text('Export'),
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

    for (var className in _classNames) {
      // Extract section from className (e.g., "5 - A" -> "A")
      final section = className.split(' - ').last.trim();
      // Extract grade from className (e.g., "7 - A" -> "7")
      final gradeNum = className.split(' - ').first.trim();

      // Filter students for THIS specific section
      final studentsInSection = allStudents.where((student) {
        final studentSection = student['section']?.toString().trim() ?? '';
        final studentClassName = student['className']?.toString() ?? '';
        final studentGrade = studentClassName
            .replaceAll('Grade ', '')
            .replaceAll('grade ', '')
            .trim();

        final matches = studentGrade == gradeNum && studentSection == section;

        if (matches) {}

        return matches;
      }).toList();

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
              const SizedBox(width: 48),
              Text(
                'My Classes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline),
                color: Theme.of(context).iconTheme.color,
                tooltip: 'Profile',
                onPressed: () {
                  Navigator.pushNamed(context, '/profile');
                },
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
                        backgroundColor: const Color(0xFF355872),
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
