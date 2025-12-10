import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/teacher_service.dart';

class StudentListScreen extends StatefulWidget {
  final String className;

  const StudentListScreen({super.key, required this.className});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final _searchController = TextEditingController();

  final TeacherService _teacherService = TeacherService();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _students = [];
  Map<String, int> _attendanceCache = {}; // Cache for calculated attendance

  // Teacher brand + dark palette (UI only; no logic changes)
  static const Color _teacherPrimary = Color(0xFF8B5CF6);
  static const Color _bgDark = Color(0xFF120F23);
  static const Color _tileDark = Color(0xFF1E1E2D);
  static const Color _mutedPurple = Color(0xFF978DCE);

  // Parsed from widget.className (e.g., "Grade 4 - A")
  late final String _classNameForQuery; // e.g., "Grade 4"
  late final String _sectionForQuery; // e.g., "A"

  @override
  void initState() {
    super.initState();
    _parseArgs();
    _loadStudents();
  }

  void _parseArgs() {
    // Expect formats like: "Grade 4 - A" or "Grade 4-A"
    final raw = widget.className.trim();
    final parts = raw.split(' - ');
    if (parts.length == 2) {
      _classNameForQuery = parts[0].trim(); // keep "Grade 4" exactly
      _sectionForQuery = parts[1].trim();
    } else {
      // Fallback: try removing leading "Grade " and take last token as section
      _sectionForQuery = raw.split('-').last.trim();
      final gradePart = raw.split('-').first.trim();
      _classNameForQuery = gradePart.startsWith('Grade')
          ? gradePart
          : 'Grade $gradePart';
    }
  }

  Future<void> _loadStudents() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        setState(() {
          _error = 'No user logged in';
          _isLoading = false;
        });
        return;
      }

      // We only need school id and to pass a single class (e.g., ["Grade 4"]) and a single section (e.g., "A")
      final schoolId = currentUser.instituteId ?? '';
      final students = await _teacherService.getStudentsByTeacher(schoolId, [
        _classNameForQuery,
      ], _sectionForQuery);

      setState(() {
        _students = students;
        _isLoading = false;
      });

      // Calculate attendance for each student in the background
      _calculateAttendanceForStudents(schoolId);
    } catch (e) {
      setState(() {
        _error = 'Failed to load students: $e';
        _isLoading = false;
      });
    }
  }

  /// Calculate attendance percentage for all students efficiently
  Future<void> _calculateAttendanceForStudents(String schoolCode) async {
    try {
      // Parse grade from className
      final gradeMatch = RegExp(
        r'Grade\s+(\d+)',
      ).firstMatch(_classNameForQuery);
      final grade = gradeMatch?.group(1);
      if (grade == null) return;

      // ✅ OPTIMIZED: Fetch attendance records ONCE for entire class
      final attendanceDocs = await _teacherService.getAttendanceRecordsForClass(
        schoolCode,
        grade,
        _sectionForQuery,
      );

      // Calculate attendance for each student from the same data set
      for (final student in _students) {
        // ✅ Use auth UID (not document ID) for lookup
        final studentUid = student['uid']?.toString();
        final studentDocId = student['id']?.toString();
        if (studentUid == null || studentDocId == null) continue;

        int totalDays = 0;
        int presentDays = 0;

        for (final doc in attendanceDocs) {
          final studentsData = doc['students'] as Map<String, dynamic>?;
          if (studentsData == null) continue;

          final studentInfo = studentsData[studentUid] as Map<String, dynamic>?;
          if (studentInfo == null) continue;

          totalDays++;
          final status =
              studentInfo['status']?.toString().toLowerCase() ?? 'present';
          if (status == 'present') {
            presentDays++;
          }
        }

        final percentage = totalDays > 0
            ? ((presentDays / totalDays) * 100).round().clamp(0, 100)
            : 0;

        // Update cache with document ID as key (for UI lookup)
        if (mounted) {
          setState(() {
            _attendanceCache[studentDocId] = percentage;
          });
        }
      }
    } catch (e) {
      print('Error calculating attendance: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _students;

    return _students.where((s) {
      final name = _displayName(s).toLowerCase();
      return name.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? _bgDark : theme.colorScheme.surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(_error!),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadStudents,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildHeader(theme),
                // Center the content area on wide screens
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        children: [
                          _buildSearchBar(theme),
                          Expanded(child: _buildStudentList(theme)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? _bgDark : theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                    onPressed: () => Navigator.pop(context),
                    color: Colors.white,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.className.replaceAll('-', '–'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 4,
                          width: 48,
                          decoration: BoxDecoration(
                            color: _teacherPrimary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: isDark ? _tileDark : theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search, color: isDark ? _mutedPurple : theme.hintColor),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: isDark ? Colors.white : theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search for a student',
                  hintStyle: TextStyle(
                    color: isDark
                        ? _mutedPurple
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentList(ThemeData theme) {
    final students = _filteredStudents;

    if (students.isEmpty) {
      final isDark = theme.brightness == Brightness.dark;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_search,
                size: 72,
                color: _teacherPrimary.withOpacity(0.6),
              ),
              const SizedBox(height: 16),
              Text(
                'No students found',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Try adjusting your search to find a student.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? _mutedPurple : theme.hintColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _buildStudentCard(theme, students[index]),
    );
  }

  String _displayName(Map<String, dynamic> s) {
    final first = (s['firstName'] ?? '').toString().trim();
    final last = (s['lastName'] ?? '').toString().trim();
    final fallback = [first, last].where((e) => e.isNotEmpty).join(' ').trim();
    return (s['name'] ?? s['studentName'] ?? s['fullName'] ?? fallback)
        .toString()
        .trim();
  }

  int _score(Map<String, dynamic> s) {
    final v = s['score'] ?? s['averageScore'] ?? 0;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  int _getAttendancePercentage(Map<String, dynamic> s) {
    final studentId = s['id']?.toString();

    // First check calculated attendance cache
    if (studentId != null && _attendanceCache.containsKey(studentId)) {
      return _attendanceCache[studentId]!;
    }

    // Fallback to static field (will be 0 if not calculated yet)
    final attendance =
        s['attendance'] ??
        s['attendancePercentage'] ??
        s['attendancePercent'] ??
        0;
    if (attendance is int) return attendance;
    if (attendance is double) return attendance.round();
    return int.tryParse(attendance.toString()) ?? 0;
  }

  String? _avatar(Map<String, dynamic> s) {
    return (s['imageUrl'] ?? s['photoUrl'] ?? s['avatar'])?.toString();
  }

  Widget _buildStudentCard(ThemeData theme, Map<String, dynamic> student) {
    final isDark = theme.brightness == Brightness.dark;
    final name = _displayName(student);
    final avatarUrl = _avatar(student);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? _tileDark : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: InkWell(
        onTap: () => _viewStudentDetails(student),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildAvatarOrInitials(avatarUrl, name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Attendance: ${_getAttendancePercentage(student)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? _mutedPurple
                            : theme.colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, color: _teacherPrimary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarOrInitials(String? url, String name) {
    final initials = _initials(name);
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsBlock(initials),
        ),
      );
    }
    return _initialsBlock(initials);
  }

  Widget _initialsBlock(String initials) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _teacherPrimary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: _teacherPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _viewStudentDetails(Map<String, dynamic> student) {
    Navigator.pushNamed(
      context,
      '/student-performance',
      arguments: {
        'name': _displayName(student),
        'class': widget.className,
        'imageUrl': _avatar(student) ?? '',
        'score': _score(student),
        'studentId': (student['id'] ?? '').toString(),
      },
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r"\s+"))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
