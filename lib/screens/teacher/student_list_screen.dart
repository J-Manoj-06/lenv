import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../services/app_usage_service.dart';
import '../../services/teacher_service.dart';
import '../../utils/session_manager.dart';
import '../../widgets/student_usage_card.dart';

class StudentListScreen extends StatefulWidget {
  final String className;

  const StudentListScreen({super.key, required this.className});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final TeacherService _teacherService = TeacherService();
  final AppUsageService _appUsageService = AppUsageService();
  bool _isLoading = true;
  bool _isUsageLoading = false;
  String? _error;
  List<Map<String, dynamic>> _students = [];
  final Map<String, int> _attendanceCache =
      {}; // Cache for calculated attendance
  Map<String, TeacherStudentUsageSummary> _usageByStudent = {};
  bool _isSearchFocused = false;

  // Teacher brand + dark palette (UI only; no logic changes)
  static const Color _teacherPrimary = Color(0xFF355872);
  static const Color _bgDark = Color(0xFF120F23);
  static const Color _mutedPurple = Color(0xFF978DCE);

  // Parsed from widget.className (e.g., "Grade 4 - A")
  late final String _classNameForQuery; // e.g., "Grade 4"
  late final String _sectionForQuery; // e.g., "A"

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
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
      var currentUser = authProvider.currentUser;
      // Retry auth init if user is null (offline)
      if (currentUser == null) {
        await authProvider.initializeAuth();
        currentUser = authProvider.currentUser;
      }

      String? schoolId = currentUser?.instituteId;

      // Try network fetch first
      List<Map<String, dynamic>>? students;
      if (currentUser != null) {
        try {
          students = await _teacherService.getStudentsByTeacher(
            schoolId ?? '',
            [_classNameForQuery],
            _sectionForQuery,
          );
        } catch (_) {
          students = null;
        }
      }

      // Fallback: try leaderboard prefs cache filtered by class/section
      if (students == null || students.isEmpty) {
        students = await _loadStudentsFromCache();
      }

      if (students == null) {
        setState(() {
          _error = currentUser == null
              ? 'No user logged in'
              : 'Failed to load students';
          _isLoading = false;
        });
        return;
      }

      // Drop any records without a usable name/id to avoid blank tiles in the list
      final sanitized = students.where((s) {
        final name = _displayName(s);
        final id = (s['id'] ?? s['uid'] ?? '').toString().trim();
        return name.isNotEmpty && id.isNotEmpty;
      }).toList();

      // Deduplicate by stable identity (uid > id > name) to avoid duplicate tiles like repeating "Uma Nair"
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final s in sanitized) {
        final uidKey = (s['uid'] ?? '').toString().trim().toLowerCase();
        final idKey = (s['id'] ?? '').toString().trim().toLowerCase();
        final nameKey = _displayName(s).toLowerCase();
        final key = uidKey.isNotEmpty
            ? 'uid:$uidKey'
            : (idKey.isNotEmpty ? 'id:$idKey' : 'name:$nameKey');
        if (seen.contains(key)) continue;
        seen.add(key);
        deduped.add(s);
      }

      setState(() {
        _students = deduped;
        _isLoading = false;
      });

      await _loadClassUsageData();

      // Calculate attendance for each student in the background
      _calculateAttendanceForStudents(schoolId ?? '');
    } catch (e) {
      setState(() {
        _error = 'Failed to load students: $e';
        _isLoading = false;
      });
    }
  }

  /// Load students from leaderboard prefs cache, filtered by class/section
  Future<List<Map<String, dynamic>>?> _loadStudentsFromCache() async {
    try {
      final session = await SessionManager.getLoginSession();
      final userId = session['userId'] as String? ?? '';
      if (userId.isEmpty) return null;

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('leaderboard_data_$userId');
      if (raw == null || raw.isEmpty) return null;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      final allStudents = (data['students'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Filter to only students in this class/section
      final filtered = allStudents.where((s) {
        final cn = (s['className'] ?? '').toString();
        final sec = (s['section'] ?? '').toString().trim().toUpperCase();
        return cn == _classNameForQuery &&
            sec == _sectionForQuery.trim().toUpperCase();
      }).toList();

      // If no exact match, return all (teacher might only teach one class)
      return filtered.isNotEmpty ? filtered : allStudents;
    } catch (_) {
      return null;
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
    } catch (e) {}
  }

  List<Map<String, dynamic>> get _filteredStudents {
    final query = _searchController.text.trim().toLowerCase();
    final source = query.isEmpty
        ? List<Map<String, dynamic>>.from(_students)
        : _students.where((s) {
            final name = _displayName(s).toLowerCase();
            return name.contains(query);
          }).toList();

    source.sort((a, b) {
      final aSummary = _usageByStudent[_usageLookupId(a)];
      final bSummary = _usageByStudent[_usageLookupId(b)];

      int rank(TeacherStudentUsageSummary? s) {
        if (s == null || !s.hasData || s.permissionEnabled != true) return 3;
        switch (s.priority) {
          case UsagePriority.high:
            return 0;
          case UsagePriority.medium:
            return 1;
          case UsagePriority.low:
            return 2;
          case UsagePriority.unknown:
            return 3;
        }
      }

      final r = rank(aSummary).compareTo(rank(bSummary));
      if (r != 0) return r;

      final usageCompare = (bSummary?.totalUsageMinutes ?? -1).compareTo(
        aSummary?.totalUsageMinutes ?? -1,
      );
      if (usageCompare != 0) return usageCompare;

      return _displayName(
        a,
      ).toLowerCase().compareTo(_displayName(b).toLowerCase());
    });

    return source;
  }

  String _usageLookupId(Map<String, dynamic> s) {
    final uid = (s['uid'] ?? '').toString().trim();
    if (uid.isNotEmpty) return uid;
    final studentId = (s['studentId'] ?? '').toString().trim();
    if (studentId.isNotEmpty) return studentId;
    return (s['id'] ?? '').toString().trim();
  }

  Future<void> _loadClassUsageData() async {
    final ids = _students
        .map(_usageLookupId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) {
      if (mounted) {
        setState(() {
          _usageByStudent = {};
          _isUsageLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isUsageLoading = true);
    }

    try {
      final batch = await _appUsageService.getClassTodayUsage(
        classId: widget.className,
        studentIds: ids,
      );
      if (!mounted) return;
      setState(() {
        _usageByStudent = batch;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _usageByStudent = {};
      });
    } finally {
      if (mounted) {
        setState(() => _isUsageLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : theme.colorScheme.surface,
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
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      size: 22,
                      color: theme.iconTheme.color,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.className.replaceAll('-', '–'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
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
      child: AnimatedScale(
        scale: _isSearchFocused ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              height: 54,
              decoration: BoxDecoration(
                color: _isSearchFocused
                    ? (isDark
                          ? const Color.fromRGBO(43, 58, 82, 0.72)
                          : Colors.white)
                    : (isDark
                          ? const Color.fromRGBO(30, 41, 59, 0.60)
                          : const Color.fromRGBO(248, 250, 252, 0.95)),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _isSearchFocused
                      ? const Color(0xFF3B82F6)
                      : const Color.fromRGBO(255, 255, 255, 0.08),
                  width: _isSearchFocused ? 1.25 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.26)
                        : Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                  if (_isSearchFocused)
                    const BoxShadow(
                      color: Color.fromRGBO(59, 130, 246, 0.28),
                      blurRadius: 24,
                      spreadRadius: 1,
                      offset: Offset(0, 0),
                    ),
                ],
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF94A3B8),
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (_) => setState(() {}),
                      cursorColor: const Color(0xFF93C5FD),
                      style: const TextStyle(
                        color: Color(0xFFE5E7EB),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                        height: 1.35,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search for a student',
                        hintStyle: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            key: const ValueKey('clear-search'),
                            onTap: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(
                                  148,
                                  163,
                                  184,
                                  0.16,
                                ),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF9CA3AF),
                                size: 16,
                              ),
                            ),
                          )
                        : const SizedBox(width: 10),
                  ),
                ],
              ),
            ),
          ),
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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final student = students[index];
        final usage = _usageByStudent[_usageLookupId(student)];
        final card = _buildStudentCard(theme, student, usage: usage);
        if (index == 0 && _isUsageLoading) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              card,
            ],
          );
        }
        return card;
      },
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

  String? _avatar(Map<String, dynamic> s) {
    return (s['imageUrl'] ?? s['photoUrl'] ?? s['avatar'])?.toString();
  }

  Widget _buildStudentCard(
    ThemeData theme,
    Map<String, dynamic> student, {
    TeacherStudentUsageSummary? usage,
  }) {
    final name = _displayName(student);
    final avatarUrl = _avatar(student);
    return StudentUsageCard(
      studentName: name,
      profileImageUrl: avatarUrl,
      usage: usage,
      onTap: () => _viewStudentDetails(student),
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
