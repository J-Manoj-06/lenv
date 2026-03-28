import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../services/teacher_service.dart';
import '../../utils/session_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final TeacherService _teacherService = TeacherService();

  String? _selectedClass;
  List<String> _classes = [];
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  // ── Prefs cache helpers ─────────────────────────────────────────────────────────
  static String _prefKey(String userId) => 'leaderboard_data_$userId';

  Future<bool> _loadFromCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey(userId));
      if (raw == null || raw.isEmpty) return false;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final classes = List<String>.from(data['classes'] ?? []);
      final students = (data['students'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (classes.isEmpty && students.isEmpty) return false;
      if (mounted) {
        setState(() {
          _classes = classes;
          _students = students;
          _selectedClass = classes.isNotEmpty ? classes[0] : null;
          _isLoading = false;
          _error = null;
        });
      }
      debugPrint(
        '💾 [LEADERBOARD] Loaded ${students.length} students from cache',
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ [LEADERBOARD] Cache read error: $e');
      return false;
    }
  }

  Future<void> _saveToCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Students may contain non-serialisable values; keep only safe keys
      final safeStudents = _students.map((s) {
        return Map<String, dynamic>.from(s)..removeWhere(
          (k, v) =>
              v != null &&
              v is! String &&
              v is! num &&
              v is! bool &&
              v is! List<dynamic> &&
              v is! Map<String, dynamic>,
        );
      }).toList();
      await prefs.setString(
        _prefKey(userId),
        jsonEncode({'classes': _classes, 'students': safeStudents}),
      );
      debugPrint(
        '💾 [LEADERBOARD] Saved ${_students.length} students to cache',
      );
    } catch (e) {
      debugPrint('⚠️ [LEADERBOARD] Cache write error: $e');
    }
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initAndLoad() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.ensureInitialized();
    await _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      String? email = currentUser?.email;

      if (email == null) {
        // ✅ OFFLINE FALLBACK: load from prefs cache using cached userId
        final session = await SessionManager.getLoginSession();
        final userId = session['userId'] as String? ?? '';
        if (userId.isNotEmpty) {
          final loaded = await _loadFromCache(userId);
          if (loaded) return;
        }
        // Cache miss or no session — show empty
        if (mounted) {
          setState(() {
            _error = authProvider.isInitialized ? null : null; // silently empty
            _isLoading = false;
          });
        }
        return;
      }

      // Fetch teacher data
      final teacherData = await _teacherService.getTeacherByEmail(email);

      if (teacherData == null) {
        setState(() {
          _error = 'Teacher data not found';
          _isLoading = false;
        });
        return;
      }

      // Get formatted classes
      final classes = _teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        teacherData['sections'] ?? teacherData['section'],
        classAssignments: teacherData['classAssignments'],
      );

      // Add "All Classes" option
      classes.insert(0, 'All Classes');

      // Fetch all students for all classes
      final schoolId =
          currentUser?.instituteId ?? teacherData['schoolCode'] ?? '';
      final allStudents = await _teacherService.getStudentsByTeacher(
        schoolId,
        teacherData['classesHandled'],
        teacherData['sections'] ?? teacherData['section'],
        classAssignments: teacherData['classAssignments'],
      );

      // Enrich points for each student with canonical available points
      // and de-duplicate by uid (fallback docId/name), keeping the highest points
      final Map<String, Map<String, dynamic>> deduped = {};
      for (final s in allStudents) {
        final copy = Map<String, dynamic>.from(s);
        final docId = (copy['id'] ?? copy['docId'])?.toString() ?? '';
        final uid = (copy['uid'] ?? copy['studentId'])?.toString() ?? '';

        final points = await _getCanonicalPointsForStudent(copy);

        copy['aggregatedRewardPoints'] = points;

        final nameKey = (copy['studentName'] ?? copy['name'] ?? '')
            .toString()
            .toLowerCase();
        final key = uid.isNotEmpty
            ? 'uid:$uid'
            : (docId.isNotEmpty ? 'doc:$docId' : 'name:$nameKey');

        final existing = deduped[key];
        if (existing == null ||
            _getStudentPoints(copy) > _getStudentPoints(existing)) {
          deduped[key] = copy;
        }

        // Debug print to verify
        // ignore: avoid_print
      }

      final enriched = deduped.values.toList();

      // Sort students by points (descending)
      enriched.sort((a, b) {
        final aPoints = _getStudentPoints(a);
        final bPoints = _getStudentPoints(b);
        return bPoints.compareTo(aPoints);
      });

      setState(() {
        _classes = classes;
        _students = enriched;
        _selectedClass = classes.isNotEmpty ? classes[0] : null;
        _isLoading = false;
      });

      // ✅ Persist to prefs cache for offline access
      final userId = currentUser?.uid ?? '';
      if (userId.isNotEmpty) {
        await _saveToCache(userId);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_selectedClass == null || _selectedClass == 'All Classes') {
      return _students;
    }

    final parts = _selectedClass!.split(' - ');
    if (parts.length != 2) return _students;

    final selectedGrade = parts[0].trim();
    final selectedSection = parts[1].trim();

    return _students.where((student) {
      final studentClassName = student['className']?.toString() ?? '';
      final studentGrade = studentClassName
          .replaceAll('Grade ', '')
          .replaceAll('grade ', '')
          .trim();
      final studentSection = student['section']?.toString() ?? '';

      return studentGrade == selectedGrade && studentSection == selectedSection;
    }).toList();
  }

  List<Map<String, dynamic>> get _sortedFilteredStudents {
    final list = List<Map<String, dynamic>>.from(_filteredStudents);
    list.sort((a, b) => _getStudentPoints(b).compareTo(_getStudentPoints(a)));
    return list;
  }

  String _studentKey(Map<String, dynamic> student) {
    final uid = (student['uid'] ?? student['studentId'])?.toString() ?? '';
    final docId = (student['id'] ?? student['docId'])?.toString() ?? '';
    final nameKey = (student['studentName'] ?? student['name'] ?? '')
        .toString()
        .toLowerCase();
    if (uid.isNotEmpty) return 'uid:$uid';
    if (docId.isNotEmpty) return 'doc:$docId';
    return 'name:$nameKey';
  }

  // Helper method to get student points
  int _getStudentPoints(Map<String, dynamic> student) {
    final rewardPoints = student['rewardPoints'];
    final totalPoints = student['totalPoints'];
    final points = student['points'];
    final aggregated = student['aggregatedRewardPoints'];
    final available = student['available_points'];

    int? parse(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    // Deterministic priority: aggregatedRewardPoints (fresh total earned) > available > legacy
    final ordered = <int?>[
      parse(aggregated),
      parse(available),
      parse(rewardPoints),
      parse(totalPoints),
      parse(points),
    ];

    for (final value in ordered) {
      if (value != null) return value;
    }
    return 0;
  }

  Future<int> _getCanonicalPointsForStudent(
    Map<String, dynamic> student,
  ) async {
    final uid = (student['uid'] ?? student['studentId'])?.toString() ?? '';

    int? parse(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    // Calculate TOTAL EARNED POINTS (not available/deducted) for consistency
    // with dashboard and leaderboard
    if (uid.isNotEmpty) {
      try {
        final rewardsSnap = await FirebaseFirestore.instance
            .collection('student_rewards')
            .where('studentId', isEqualTo: uid)
            .get();

        int earned = 0;
        for (final d in rewardsSnap.docs) {
          final val = d.data()['pointsEarned'];
          if (val is num) earned += val.toInt();
        }

        // Return TOTAL EARNED (not available/deducted)
        return earned.clamp(0, 1 << 30);
      } catch (_) {}
    }

    // Fallback: try from available_points if earned calculation fails
    if (student.containsKey('available_points')) {
      return (parse(student['available_points']) ?? 0).clamp(0, 1 << 30);
    }

    return _getStudentPoints(student);
  }

  // Helper method to format grade and section
  String _formatGradeSection(Map<String, dynamic> student) {
    final className = student['className']?.toString() ?? '';
    final section = student['section']?.toString() ?? '';

    final grade = className
        .replaceAll('Grade ', '')
        .replaceAll('grade ', '')
        .trim();

    if (grade.isEmpty || section.isEmpty) {
      return className.isNotEmpty ? className : 'Unknown';
    }

    return 'Grade $grade - $section';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

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
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopPerformersSection(),
                  _buildFilters(),
                  _buildStudentRankings(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 48),
              Text(
                'Leaderboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
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

  Widget _buildTopPerformersSection() {
    final topStudents = _sortedFilteredStudents.take(3).toList();

    if (topStudents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No students found',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Top Performers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 2nd place
              if (topStudents.length > 1)
                _buildTopPerformer(
                  rank: 2,
                  name: _getShortName(
                    topStudents[1]['studentName'] ??
                        topStudents[1]['name'] ??
                        'Student',
                  ),
                  gradeSection: _formatGradeSection(topStudents[1]),
                  points: _getStudentPoints(topStudents[1]),
                  borderColor: const Color(0xFFC0C0C0), // Silver
                  badgeColor: const Color(0xFFC0C0C0),
                  size: 80,
                  marginTop: 16,
                )
              else
                const SizedBox(width: 80),
              // 1st place
              _buildTopPerformer(
                rank: 1,
                name: _getShortName(
                  topStudents[0]['studentName'] ??
                      topStudents[0]['name'] ??
                      'Student',
                ),
                gradeSection: _formatGradeSection(topStudents[0]),
                points: _getStudentPoints(topStudents[0]),
                borderColor: const Color(0xFFFFD700), // Gold
                badgeColor: const Color(0xFFFFD700),
                size: 96,
                marginTop: 0,
              ),
              // 3rd place
              if (topStudents.length > 2)
                _buildTopPerformer(
                  rank: 3,
                  name: _getShortName(
                    topStudents[2]['studentName'] ??
                        topStudents[2]['name'] ??
                        'Student',
                  ),
                  gradeSection: _formatGradeSection(topStudents[2]),
                  points: _getStudentPoints(topStudents[2]),
                  borderColor: const Color(0xFFCD7F32), // Bronze
                  badgeColor: const Color(0xFFCD7F32),
                  size: 80,
                  marginTop: 16,
                )
              else
                const SizedBox(width: 80),
            ],
          ),
        ),
      ],
    );
  }

  String _getShortName(String fullName) {
    final parts = fullName.split(' ');
    if (parts.length == 1) return fullName;
    return '${parts[0]} ${parts[1].substring(0, 1)}.';
  }

  Widget _buildTopPerformer({
    required int rank,
    required String name,
    required String gradeSection,
    required int points,
    required Color borderColor,
    required Color badgeColor,
    required double size,
    required double marginTop,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(top: marginTop),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 4),
                  color: isDark ? Colors.grey[800] : Colors.grey[300],
                ),
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.7),
                ),
              ),
              Positioned(
                bottom: -8,
                left: size / 2 - 16,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            gradeSection,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '$points pts',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Class',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1.5,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedClass,
                isExpanded: true,
                icon: Icon(
                  Icons.expand_more,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.7),
                ),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
                items: _classes.map((className) {
                  return DropdownMenuItem<String>(
                    value: className,
                    child: Text(
                      className == 'All Classes'
                          ? className
                          : 'Grade $className',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedClass = value ?? 'All Classes';
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRankings() {
    final topList = _sortedFilteredStudents.take(3).toList();
    final topKeys = topList.map(_studentKey).toSet();
    final topCount = topList.length;
    final filteredStudents = _sortedFilteredStudents
        .where((s) => !topKeys.contains(_studentKey(s)))
        .toList();

    if (filteredStudents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No students found',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: filteredStudents.asMap().entries.map((entry) {
          final index = entry.key;
          final student = entry.value;
          final rank = topCount + index + 1;
          final studentName =
              student['studentName'] ??
              student['name'] ??
              'Student ${index + 1}';
          final points = _getStudentPoints(student);
          final gradeSection = _formatGradeSection(student);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]
                          : Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      size: 24,
                      color: Theme.of(
                        context,
                      ).iconTheme.color?.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          gradeSection,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color?.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$points pts',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
