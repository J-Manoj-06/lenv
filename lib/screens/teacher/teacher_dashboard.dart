import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../utils/feedback_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../config/cloudflare_config.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../utils/chat_type_config.dart';
import '../../widgets/teacher_bottom_nav.dart';
import '../../services/teacher_service.dart';
import '../../services/firestore_service.dart';
import '../../models/status_model.dart';
import '../../models/institute_announcement_model.dart';
import '../../services/parent_teacher_group_service.dart';
import '../../models/parent_teacher_group.dart';
import 'attendance_screen.dart';
import '../common/announcement_pageview_screen.dart';
import '../../services/media_repository.dart';
import 'teacher_announcement_target_screen.dart';
import '../../widgets/auto_scroll_announcement.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  String? selectedClass;
  int selectedNavIndex = 0;

  final TeacherService _teacherService = TeacherService();
  Map<String, dynamic>? _teacherData;
  List<Map<String, dynamic>> _students = [];
  List<String> _classes = [];
  Map<String, int> _classStudentCounts = {};
  // Maps "<Grade> - <Section>" to list of subjects handled
  Map<String, List<String>> _classSubjectMap = <String, List<String>>{};
  final ParentTeacherGroupService _ptGroupService = ParentTeacherGroupService();
  ParentTeacherGroup? _sectionGroup;
  bool _isLoadingSectionGroup = false;
  String? _sectionGroupError;
  int _sectionGroupUnreadCount = 0;
  bool _isLoading = true;
  String? _error;
  // Cache viewed principal announcement ids to avoid re-marking and stale badges
  final Set<String> _viewedPrincipalAnnouncements = <String>{};
  // Cache for instant viewed status display (both teacher and principal)
  final Map<String, bool> _viewedCache = {};
  final MediaRepository _mediaRepository = MediaRepository();

  // Offline cache flag
  bool _isOfflineMode = false;

  // Highlights: best-effort cleanup on load
  Future<void> _cleanupExpiredHighlights() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final uid = auth.currentUser?.uid;
      if (uid == null) return;
      final now = DateTime.now();

      // Check class_highlights
      final highlightsQs = await FirebaseFirestore.instance
          .collection('class_highlights')
          .where('teacherId', isEqualTo: uid)
          .get();
      final expiredHighlights = highlightsQs.docs.where((d) {
        final ts = (d.data()['expiresAt'] as Timestamp?)?.toDate();
        return ts != null && !ts.isAfter(now);
      }).toList();

      if (expiredHighlights.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in expiredHighlights) {
          final data = doc.data();
          final imageUrl = data['imageUrl'] as String?;

          // Delete image from Cloudflare R2
          if (imageUrl != null && imageUrl.isNotEmpty) {
            try {
              final r2Key = _extractR2KeyFromUrl(imageUrl);
              if (r2Key.isNotEmpty) {
                final r2Service = CloudflareR2Service(
                  accountId: CloudflareConfig.accountId,
                  bucketName: CloudflareConfig.bucketName,
                  accessKeyId: CloudflareConfig.accessKeyId,
                  secretAccessKey: CloudflareConfig.secretAccessKey,
                  r2Domain: CloudflareConfig.r2Domain,
                );
                await r2Service.deleteFile(key: r2Key);
              }
            } catch (e) {}
          }

          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      // silent best-effort
    }
  }

  /// Clean up expired principal announcements (24-hour TTL)
  Future<void> _cleanupExpiredPrincipalAnnouncements() async {
    try {
      final now = DateTime.now();

      // Query all expired announcements
      final announcementsQs = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .where('expiresAt', isLessThan: Timestamp.fromDate(now))
          .limit(50) // Process in batches to avoid timeout
          .get();

      if (announcementsQs.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in announcementsQs.docs) {
          final data = doc.data();
          final imageUrl = data['imageUrl'] as String?;

          // Delete image from Cloudflare R2
          if (imageUrl != null && imageUrl.isNotEmpty) {
            try {
              final r2Key = _extractR2KeyFromUrl(imageUrl);
              if (r2Key.isNotEmpty) {
                final r2Service = CloudflareR2Service(
                  accountId: CloudflareConfig.accountId,
                  bucketName: CloudflareConfig.bucketName,
                  accessKeyId: CloudflareConfig.accessKeyId,
                  secretAccessKey: CloudflareConfig.secretAccessKey,
                  r2Domain: CloudflareConfig.r2Domain,
                );
                await r2Service.deleteFile(key: r2Key);
              }
            } catch (e) {}
          }

          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      // silent best-effort
    }
  }

  @override
  void initState() {
    super.initState();
    // ✅ NEW: Ensure auth is initialized before loading data
    _initializeAndLoad();
    // Defer non-critical cleanup to after page loads
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _cleanupExpiredHighlights();
        _cleanupExpiredPrincipalAnnouncements();
        _autoPublishTests();
      }
    });
  }

  /// Preload all viewed statuses at startup for instant display
  Future<void> _preloadViewedStatus() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUser?.uid;

      if (userId == null) return;

      final instituteId = _teacherData?['instituteId'] as String?;
      if (instituteId == null) return;

      // Preload teacher highlights viewed status
      final highlightsSnapshot = await FirebaseFirestore.instance
          .collection('class_highlights')
          .where('instituteId', isEqualTo: instituteId)
          .get();

      for (final doc in highlightsSnapshot.docs) {
        final viewedBy =
            (doc.data()['viewedBy'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        if (viewedBy.contains(userId)) {
          _viewedCache[doc.id] = true;
        }
      }

      // Preload principal announcements viewed status
      final announcementsSnapshot = await FirebaseFirestore.instance
          .collection('institutes')
          .doc(instituteId)
          .collection('institute_announcements')
          .get();

      for (final doc in announcementsSnapshot.docs) {
        final viewDoc = await doc.reference
            .collection('views')
            .doc(userId)
            .get();

        if (viewDoc.exists) {
          _viewedCache[doc.id] = true;
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error preloading viewed status: $e');
    }
  }

  /// Initialize auth and load teacher data
  Future<void> _initializeAndLoad() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // ✅ CRITICAL: Wait for auth to initialize on app start
      await authProvider.ensureInitialized();

      // Now load teacher data after auth is ready
      await _loadTeacherData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _autoPublishTests() async {
    try {
      await FirestoreService().autoPublishExpiredTests();
    } catch (_) {
      // Silent fail for background task
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadTeacherData() async {
    try {
      if (!mounted) return;

      setState(() {
        _isLoading = true;
        _error = null;
        _isOfflineMode = false;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      // Check if user is logged in
      if (currentUser == null) {
        // Try to initialize auth from Firebase
        await authProvider.initializeAuth();
        final retryUser = authProvider.currentUser;

        if (retryUser == null) {
          // No user logged in - try to load from offline cache first
          final cachedData = await _loadFromOfflineCache();

          if (cachedData != null && mounted) {
            // Show cached data in offline mode
            setState(() {
              _teacherData = cachedData['teacherData'];
              _classes = List<String>.from(cachedData['classes'] ?? []);
              _students = List<Map<String, dynamic>>.from(
                cachedData['students'] ?? [],
              );
              _isOfflineMode = true;
              _isLoading = false;
            });
            return;
          }

          // No cached data and no user - redirect to login
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/teacher-login');
            });
          }
          return;
        }
      }

      final user = authProvider.currentUser!;

      // Fetch teacher data and students in parallel for faster loading
      final results = await Future.wait([
        _teacherService.getTeacherByEmail(user.email),
        // We'll fetch students after we have teacher data
        Future.value(null),
      ]);

      final teacherData = results[0];

      if (teacherData == null) {
        setState(() {
          _error = 'Teacher data not found';
          _isLoading = false;
        });
        return;
      }

      // Determine sections field (supports 'sections' array or 'section' string)
      final dynamic sections =
          teacherData['sections'] ?? teacherData['section'];

      // Format classes for dropdown using sections
      final classes = _teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        sections,
        classAssignments: teacherData['classAssignments'], // Fallback
      );

      // Show UI immediately with classes, then fetch students in background
      setState(() {
        _teacherData = teacherData;
        _classes = classes;
        _isLoading = false;

        // Build subject mapping from classAssignments
        _buildSubjectMapping(teacherData, classes);

        // Set initial selected class
        if (classes.isNotEmpty) {
          final firstClass = classes.first;
          final subjects = _classSubjectMap[firstClass] ?? const <String>[];
          selectedClass = subjects.isNotEmpty
              ? '$firstClass::${subjects.first}'
              : firstClass;
        }
      });

      // Load section group for initial selection
      await _loadSectionGroupForSelection();

      // Preload viewed status for instant orange border updates
      await _preloadViewedStatus();

      // Save to offline cache for future offline access
      _saveToOfflineCache(teacherData, classes, []);

      // Fetch students in background after UI is shown
      _fetchStudentsInBackground(user, teacherData, sections, classes);
    } catch (e) {
      // Try to load from offline cache on error
      final cachedData = await _loadFromOfflineCache();

      if (cachedData != null && mounted) {
        setState(() {
          _teacherData = cachedData['teacherData'];
          _classes = List<String>.from(cachedData['classes'] ?? []);
          _students = List<Map<String, dynamic>>.from(
            cachedData['students'] ?? [],
          );
          _isOfflineMode = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error =
              'Failed to load data. Please check your internet connection.';
          _isLoading = false;
        });
      }
    }
  }

  /// Save teacher data to offline cache
  Future<void> _saveToOfflineCache(
    Map<String, dynamic> teacherData,
    List<String> classes,
    List<Map<String, dynamic>> students,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'teacherData': teacherData,
        'classes': classes,
        'students': students,
        'cachedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('teacher_dashboard_cache', jsonEncode(cacheData));
    } catch (e) {
      debugPrint('Error saving offline cache: $e');
    }
  }

  /// Load teacher data from offline cache
  Future<Map<String, dynamic>?> _loadFromOfflineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheString = prefs.getString('teacher_dashboard_cache');

      if (cacheString == null) return null;

      final cacheData = jsonDecode(cacheString) as Map<String, dynamic>;
      final cachedAt = DateTime.parse(cacheData['cachedAt'] as String);

      // Cache valid for 7 days
      if (DateTime.now().difference(cachedAt).inDays > 7) {
        await prefs.remove('teacher_dashboard_cache');
        return null;
      }

      return cacheData;
    } catch (e) {
      debugPrint('Error loading offline cache: $e');
      return null;
    }
  }

  void _buildSubjectMapping(
    Map<String, dynamic> teacherData,
    List<String> classes,
  ) {
    _classSubjectMap = <String, List<String>>{};
    final assignments = teacherData['classAssignments'];
    if (assignments is List) {
      for (final assignment in assignments) {
        final assignmentStr = assignment.toString();
        final colonParts = assignmentStr.split(':');
        if (colonParts.length < 2) continue;
        final gradeRaw = colonParts[0].trim();
        final rightSide = colonParts[1];
        final commaParts = rightSide.split(',');
        if (commaParts.isEmpty) continue;
        final sectionPart = commaParts[0].trim();
        String? subjectPart;
        if (commaParts.length > 1) {
          subjectPart = commaParts[1].trim();
        }
        final grade = gradeRaw
            .replaceAll('Grade ', '')
            .replaceAll('grade ', '')
            .trim();
        final key = '$grade - $sectionPart';
        if (subjectPart != null && subjectPart.isNotEmpty) {
          _classSubjectMap.putIfAbsent(key, () => <String>[]);
          if (!_classSubjectMap[key]!.contains(subjectPart)) {
            _classSubjectMap[key]!.add(subjectPart);
          }
        }
      }
    }
    // Fallback: if no mapping derived but subjectsHandled exists
    if (_classSubjectMap.isEmpty) {
      final subjectsHandled = teacherData['subjectsHandled'];
      if (subjectsHandled is List && subjectsHandled.isNotEmpty) {
        final fallbackSubject = subjectsHandled.first.toString();
        for (final c in classes) {
          _classSubjectMap[c] = [fallbackSubject];
        }
      }
    }
  }

  Future<void> _fetchStudentsInBackground(
    dynamic user,
    Map<String, dynamic> teacherData,
    dynamic sections,
    List<String> classes,
  ) async {
    try {
      // Fetch students in background
      final students = await _teacherService.getStudentsByTeacher(
        user.instituteId ?? teacherData['schoolCode'] ?? '',
        teacherData['classesHandled'],
        sections,
        classAssignments: teacherData['classAssignments'],
      );

      if (!mounted) return;

      setState(() {
        _students = students;

        // Calculate student count per class
        _classStudentCounts = {};
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

            _classStudentCounts[className] = count;
          }
        }
      });

      // Update offline cache with student data
      if (_teacherData != null && _classes.isNotEmpty) {
        _saveToOfflineCache(_teacherData!, _classes, students);
      }
    } catch (e) {
      // Don't show error, just leave students empty
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : theme.scaffoldBackgroundColor,
      body: _isLoading
          ? _buildLoadingSkeleton()
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please check your internet connection',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _initializeAndLoad,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7961FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_isOfflineMode)
                  Container(
                    width: double.infinity,
                    color: Colors.orange[700],
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.cloud_off, size: 16, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Offline Mode - Showing cached data',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGradientStatsBanner(),
                        const SizedBox(height: 24),
                        _buildClassroomHighlights(),
                        const SizedBox(height: 24),
                        _buildSectionGroupCard(),
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
    );
  }

  Widget _buildHeader() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Hello, ${_teacherData?['teacherName'] ?? currentUser?.name ?? 'Teacher'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  Row(
                    children: [
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
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: DropdownButtonFormField<String>(
                  initialValue: selectedClass,
                  isExpanded: true,
                  dropdownColor: Theme.of(context).cardColor,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: _buildClassSubjectItems(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        selectedClass = newValue;
                      });
                      _loadSectionGroupForSelection();
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

  // Build dropdown items: for each class, emit one item per subject as
  // value = '<class>::<subject>' and label '<class> - <subject>'.
  List<DropdownMenuItem<String>> _buildClassSubjectItems() {
    final items = <DropdownMenuItem<String>>[];
    for (final className in _classes) {
      final subjects = _classSubjectMap[className] ?? const <String>[];
      if (subjects.isEmpty) {
        items.add(
          DropdownMenuItem<String>(value: className, child: Text(className)),
        );
      } else {
        for (final subj in subjects) {
          final value = '$className::$subj';
          final label = '$className - $subj';
          items.add(DropdownMenuItem<String>(value: value, child: Text(label)));
        }
      }
    }
    return items;
  }

  Widget _buildSectionGroupCard() {
    final parsed = _parseClassSection(selectedClass);
    final classLabel = parsed != null
        ? '${parsed['className'] ?? ''}${(parsed['section'] ?? '').isNotEmpty ? ' - ${parsed['section']}' : ''}'
        : 'Class - Section';

    return InkWell(
      onTap:
          _sectionGroup == null ||
              _isLoadingSectionGroup ||
              _sectionGroupError != null
          ? null
          : () async {
              await Navigator.pushNamed(
                context,
                '/parent/section-group-chat',
                arguments: {
                  'groupId': _sectionGroup!.id,
                  'groupName': _sectionGroup!.name,
                  'className': _sectionGroup!.className,
                  'section': _sectionGroup!.section,
                  'schoolCode': _sectionGroup!.schoolCode,
                  'childName': '',
                  'childId': '',
                  'senderRole': 'teacher',
                },
              );
              // Refresh unread count after returning from chat
              _loadSectionGroupUnreadCount();
            },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _sectionGroup?.name.isNotEmpty == true
                            ? _sectionGroup!.name
                            : '$classLabel Parents & Teachers',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.people_outline,
                            color: Colors.white70,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Connect with parents',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_sectionGroupUnreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _sectionGroupUnreadCount > 99
                          ? '99+'
                          : _sectionGroupUnreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 4),
              ],
            ),
            if (_isLoadingSectionGroup)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Preparing group…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              )
            else if (_sectionGroupError != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Unable to load group',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loadSectionGroupForSelection,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<String, String>? _parseClassSection(String? value) {
    if (value == null || value.isEmpty) return null;
    final base = value.split('::').first;
    final parts = base.split(' - ');
    if (parts.isEmpty) return null;
    final cls = parts[0].trim();
    final sec = parts.length > 1 ? parts[1].trim() : '';
    if (cls.isEmpty) return null;
    return {'className': cls, 'section': sec};
  }

  Future<void> _loadSectionGroupForSelection() async {
    final parsed = _parseClassSection(selectedClass);
    if (parsed == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final schoolCode =
        authProvider.currentUser?.instituteId ??
        _teacherData?['schoolCode'] ??
        '';
    if (schoolCode.isEmpty) {
      setState(() {
        _sectionGroup = null;
        _sectionGroupError = 'Missing school code';
      });
      return;
    }

    setState(() {
      _isLoadingSectionGroup = true;
      _sectionGroupError = null;
    });

    try {
      final group = await _ptGroupService.ensureGroupForClassSection(
        schoolCode: schoolCode,
        className: parsed['className'] ?? '',
        section: parsed['section'] ?? '',
      );
      if (!mounted) return;
      setState(() {
        _sectionGroup = group;
      });

      // Load unread count for this group
      _loadSectionGroupUnreadCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sectionGroupError = 'Failed to load section group: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSectionGroup = false;
        });
      }
    }
  }

  /// Load unread count for the parent-teacher section group
  Future<void> _loadSectionGroupUnreadCount() async {
    if (_sectionGroup == null) {
      setState(() => _sectionGroupUnreadCount = 0);
      return;
    }

    try {
      final unreadProvider = Provider.of<UnreadCountProvider>(
        context,
        listen: false,
      );
      await unreadProvider.loadUnreadCount(
        chatId: _sectionGroup!.id,
        chatType: ChatTypeConfig.ptGroupChat,
      );

      if (!mounted) return;
      setState(() {
        _sectionGroupUnreadCount = unreadProvider.getUnreadCount(
          _sectionGroup!.id,
        );
      });
    } catch (e) {
      setState(() => _sectionGroupUnreadCount = 0);
    }
  }

  // (Announcements removed) — merged into Classroom Highlights as 24h status

  // ========== Take Attendance Card ==========
  Widget _buildGradientStatsBanner() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AttendanceScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7A5CFF), Color(0xFF9D8BFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7A5CFF).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.how_to_reg,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Take Attendance',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Mark student attendance for today',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  // ========== Classroom Highlights (WhatsApp-style Single Horizontal List) ==========
  Widget _buildClassroomHighlights() {
    final theme = Theme.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final currentUserId = currentUser?.uid;
    final instituteId =
        currentUser?.instituteId ?? _teacherData?['schoolCode'] ?? '';

    // Check if instituteId is available
    if (instituteId.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Announcements',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Unable to load announcements. Please check your connection.',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'Announcements',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),

        // Single Horizontal List (WhatsApp-style)
        SizedBox(
          height: 100,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _combineAnnouncementStreams(instituteId),
            builder: (context, snapshot) {
              // Loading state
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  itemBuilder: (_, __) => _buildShimmerCircle(theme),
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                );
              }

              // Error state
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Error loading announcements',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                );
              }

              final combinedDocs = snapshot.data ?? [];

              // Convert to unified announcement objects
              final allAnnouncements = <_AnnouncementItem>[];

              for (final doc in combinedDocs) {
                if (doc['type'] == 'teacher') {
                  // Teacher announcement (StatusModel)
                  final status = StatusModel.fromFirestore(
                    doc['snapshot'] as DocumentSnapshot,
                  );
                  if (status.isValid && status.instituteId == instituteId) {
                    // Check cache first for instant status, fallback to viewedBy
                    final isViewed =
                        _viewedCache[status.id] == true ||
                        status.hasBeenViewedBy(currentUserId ?? '');
                    allAnnouncements.add(
                      _AnnouncementItem(
                        id: status.id,
                        creatorId: status.teacherId,
                        creatorName: status.teacherName,
                        createdAt: status.createdAt,
                        hasImage: status.hasImage,
                        imageUrl: status.imageUrl,
                        type: 'teacher',
                        isViewed: isViewed,
                        data: status,
                      ),
                    );
                  }
                } else if (doc['type'] == 'principal') {
                  // Principal announcement (InstituteAnnouncementModel)
                  final snapshot = doc['snapshot'] as DocumentSnapshot;
                  final announcement = InstituteAnnouncementModel.fromFirestore(
                    snapshot,
                  );
                  final data =
                      (snapshot.data() as Map<String, dynamic>?) ?? const {};
                  final viewedBy =
                      (data['viewedBy'] as List<dynamic>?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      const <String>[];
                  // Check cache first for instant status
                  final isViewed =
                      _viewedCache[announcement.id] == true ||
                      viewedBy.contains(currentUserId) ||
                      _viewedPrincipalAnnouncements.contains(announcement.id);
                  if (announcement.instituteId == instituteId) {
                    allAnnouncements.add(
                      _AnnouncementItem(
                        id: announcement.id,
                        creatorId: announcement.principalId,
                        creatorName: announcement.principalName,
                        createdAt: announcement.createdAt,
                        hasImage: announcement.hasImage,
                        imageUrl: announcement.imageUrl,
                        type: 'principal',
                        isViewed: isViewed,
                        data: announcement,
                      ),
                    );
                  }
                }
              }

              // Sort by timestamp
              allAnnouncements.sort(
                (a, b) => b.createdAt.compareTo(a.createdAt),
              );

              // Segregate: My announcements vs Others
              final myAnnouncements = allAnnouncements
                  .where(
                    (a) => a.creatorId == currentUserId && a.type == 'teacher',
                  )
                  .toList();

              // Group others by creatorId
              final othersMap = <String, List<_AnnouncementItem>>{};
              for (final announcement in allAnnouncements) {
                if (announcement.creatorId != currentUserId ||
                    announcement.type != 'teacher') {
                  othersMap
                      .putIfAbsent(announcement.creatorId, () => [])
                      .add(announcement);
                }
              }

              // Sort each creator's announcements by timestamp
              othersMap.forEach((key, value) {
                value.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              });

              // Create list of others (sorted by latest post)
              final others = othersMap.entries.toList()
                ..sort(
                  (a, b) => b.value.first.createdAt.compareTo(
                    a.value.first.createdAt,
                  ),
                );

              // Build single horizontal list: My Announcement + Others
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: 1 + others.length, // 1 for "My Announcement"
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // My Announcement (always first)
                    return _buildMyAnnouncementAvatar(
                      theme,
                      myAnnouncements,
                      currentUser,
                    );
                  } else {
                    // Others (Teachers + Principals)
                    final creatorEntry = others[index - 1];
                    final announcements = creatorEntry.value;
                    final latestAnnouncement = announcements.first;
                    return _buildOtherAnnouncementAvatar(
                      theme,
                      latestAnnouncement,
                      announcements,
                      currentUserId ?? '',
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // My Announcement Avatar (First item in horizontal list)
  Widget _buildMyAnnouncementAvatar(
    ThemeData theme,
    List<_AnnouncementItem> myAnnouncements,
    dynamic currentUser,
  ) {
    final hasAnnouncement = myAnnouncements.isNotEmpty;
    final latestAnnouncement = hasAnnouncement ? myAnnouncements.first : null;

    return GestureDetector(
      onTap: () {
        if (hasAnnouncement) {
          // Convert to StatusModel list for viewer
          final statusList = myAnnouncements
              .where((a) => a.type == 'teacher')
              .map((a) => a.data as StatusModel)
              .toList();
          if (statusList.isNotEmpty) {
            _openStatusViewer(statusList, 0);
          }
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TeacherAnnouncementTargetScreen(
                teacherClasses: _classes,
                teacherData: _teacherData,
              ),
            ),
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Main Avatar Circle
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasAnnouncement
                      ? const LinearGradient(
                          colors: [Color(0xFFA78BFA), Color(0xFF7B61FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: !hasAnnouncement
                      ? Border.all(
                          color:
                              theme.textTheme.bodyMedium?.color ?? Colors.grey,
                          width: 2,
                        )
                      : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAnnouncement
                        ? (latestAnnouncement!.hasImage
                              ? Colors.transparent
                              : Colors.black)
                        : theme.cardColor,
                  ),
                  child: ClipOval(
                    child: hasAnnouncement && latestAnnouncement!.hasImage
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              // Background image
                              _buildCachedAnnouncementAvatar(
                                latestAnnouncement.imageUrl!,
                                'announcement_${latestAnnouncement.id}.jpg',
                                currentUser?.name ?? 'Teacher',
                                theme,
                                null,
                              ),
                              // Text overlay at bottom with gradient
                              if (latestAnnouncement.data is StatusModel &&
                                  (latestAnnouncement.data as StatusModel)
                                      .text
                                      .isNotEmpty)
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withOpacity(0.7),
                                          Colors.black.withOpacity(0.9),
                                        ],
                                      ),
                                    ),
                                    child: Text(
                                      (latestAnnouncement.data as StatusModel)
                                          .text,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : hasAnnouncement &&
                              latestAnnouncement!.data is StatusModel &&
                              (latestAnnouncement.data as StatusModel)
                                  .text
                                  .isNotEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                (latestAnnouncement.data as StatusModel).text,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          )
                        : _buildDefaultAvatar(
                            currentUser?.name ?? 'Teacher',
                            theme,
                          ),
                  ),
                ),
              ),

              // Count badge (top-right)
              if (myAnnouncements.length > 1)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B61FF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      '${myAnnouncements.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),

              // Add (+) Icon Overlay
              Positioned(
                right: -2,
                bottom: -2,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TeacherAnnouncementTargetScreen(
                          teacherClasses: _classes,
                          teacherData: _teacherData,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7E57C2), Color(0xFFB388FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7E57C2).withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Label
          SizedBox(
            width: 70,
            child: Text(
              'My\nAnnouncement',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(String name, ThemeData theme) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'T',
        style: TextStyle(
          color: theme.brightness == Brightness.dark
              ? Colors.white
              : const Color(0xFF7E57C2),
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
    );
  }

  /// Build cached announcement avatar - downloads and caches images
  Widget _buildCachedAnnouncementAvatar(
    String imageUrl,
    String fileName,
    String fallbackName,
    ThemeData? theme,
    ColorFilter? colorFilter,
  ) {
    return FutureBuilder<String?>(
      future: _getAnnouncementImagePath(imageUrl, fileName),
      builder: (context, snapshot) {
        // Show fallback immediately instead of loading indicator
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.hasError ||
            snapshot.data == null) {
          if (theme != null) {
            return _buildDefaultAvatar(fallbackName, theme);
          } else {
            return _buildTeacherInitial(fallbackName);
          }
        }

        // Show cached image
        final imageWidget = Image.file(
          File(snapshot.data!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            if (theme != null) {
              return _buildDefaultAvatar(fallbackName, theme);
            } else {
              return _buildTeacherInitial(fallbackName);
            }
          },
        );

        // Apply color filter if provided
        if (colorFilter != null) {
          return ColorFiltered(colorFilter: colorFilter, child: imageWidget);
        }

        return imageWidget;
      },
    );
  }

  /// Get announcement image path - from cache or download if needed
  Future<String?> _getAnnouncementImagePath(
    String imageUrl,
    String fileName,
  ) async {
    try {
      // Extract R2 key from URL
      String r2Key;
      if (imageUrl.contains('files.lenv1.tech')) {
        final uri = Uri.parse(imageUrl);
        r2Key = uri.path.substring(1); // Remove leading /
      } else {
        r2Key = 'announcements/${imageUrl.hashCode}_$fileName';
      }

      // Check if already cached
      final localPath = await _mediaRepository.getLocalFilePath(r2Key);
      if (localPath != null) {
        return localPath;
      }

      // Download and cache
      final result = await _mediaRepository.downloadMedia(
        r2Key: r2Key,
        fileName: fileName,
        mimeType: 'image/jpeg',
      );

      if (result.success && result.localPath != null) {
        return result.localPath;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Other Announcement Avatar (Teachers + Principals)
  Widget _buildOtherAnnouncementAvatar(
    ThemeData theme,
    _AnnouncementItem latestAnnouncement,
    List<_AnnouncementItem> allAnnouncements,
    String currentUserId,
  ) {
    final teacherUnread = allAnnouncements.any(
      (a) => a.type == 'teacher' && !a.isViewed,
    );
    final principalUnread = allAnnouncements.any(
      (a) => a.type == 'principal' && !a.isViewed,
    );
    final bool hasUnviewed = teacherUnread || principalUnread;

    return _buildOtherAnnouncementAvatarBody(
      theme: theme,
      latestAnnouncement: latestAnnouncement,
      allAnnouncements: allAnnouncements,
      hasUnviewed: hasUnviewed,
    );
  }

  Widget _buildOtherAnnouncementAvatarBody({
    required ThemeData theme,
    required _AnnouncementItem latestAnnouncement,
    required List<_AnnouncementItem> allAnnouncements,
    required bool hasUnviewed,
  }) {
    final containsPrincipal = allAnnouncements.any(
      (a) => a.type == 'principal',
    );

    return GestureDetector(
      onTap: () {
        _openCombinedAnnouncementViewer(allAnnouncements);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasUnviewed
                      ? const LinearGradient(
                          colors: [Color(0xFFF27F0D), Color(0xFFFF9F40)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            Colors.grey.withOpacity(
                              containsPrincipal ? 0.25 : 0.4,
                            ),
                            Colors.grey.withOpacity(
                              containsPrincipal ? 0.2 : 0.3,
                            ),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  boxShadow: hasUnviewed
                      ? [
                          BoxShadow(
                            color: const Color(0xFFF27F0D).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: latestAnnouncement.hasImage
                        ? Colors.transparent
                        : const Color(0xFF7E57C2),
                  ),
                  child: ClipOval(
                    child: latestAnnouncement.hasImage
                        ? _buildCachedAnnouncementAvatar(
                            latestAnnouncement.imageUrl!,
                            'announcement_${latestAnnouncement.id}.jpg',
                            latestAnnouncement.creatorName,
                            null,
                            hasUnviewed
                                ? const ColorFilter.mode(
                                    Colors.transparent,
                                    BlendMode.multiply,
                                  )
                                : ColorFilter.mode(
                                    Colors.grey.withOpacity(0.5),
                                    BlendMode.saturation,
                                  ),
                          )
                        : _buildTeacherInitial(latestAnnouncement.creatorName),
                  ),
                ),
              ),
              // Count badge
              if (allAnnouncements.length > 1)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: hasUnviewed
                          ? const Color(0xFFF27F0D)
                          : Colors.grey[600],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      '${allAnnouncements.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 70,
            child: Text(
              latestAnnouncement.type == 'principal'
                  ? 'Principal'
                  : latestAnnouncement.creatorName.split(' ').first,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeacherInitial(String teacherName) {
    return Center(
      child: Text(
        teacherName.isNotEmpty ? teacherName[0].toUpperCase() : 'T',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
    );
  }

  /// Stream principal announcement view status for the current user
  Stream<List<bool>> _streamPrincipalAnnouncementsViewStatus(
    List<_AnnouncementItem> announcements,
    String userId,
  ) {
    if (userId.isEmpty || announcements.isEmpty) {
      return Stream.value(const <bool>[]);
    }

    return Stream.periodic(const Duration(seconds: 4))
        .asyncMap((_) async {
          final results = <bool>[];
          for (final item in announcements) {
            final announcement = item.data as InstituteAnnouncementModel;
            final doc = await FirebaseFirestore.instance
                .collection('institute_announcements')
                .doc(announcement.id)
                .collection('views')
                .doc(userId)
                .get();
            results.add(doc.exists);
          }
          return results;
        })
        .distinct((prev, next) {
          if (prev.length != next.length) return false;
          for (var i = 0; i < prev.length; i++) {
            if (prev[i] != next[i]) return false;
          }
          return true;
        });
  }

  void _openStatusViewer(List<StatusModel> statuses, int initialIndex) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUser?.uid ?? '';

    // Convert statuses to announcement format for PageView
    final announcements = statuses
        .map(
          (status) => {
            'role': 'teacher',
            'title': status.text,
            'subtitle': '',
            'postedByLabel': 'Posted by ${status.teacherName}',
            'avatarUrl': status.imageUrl,
            'imageCaptions': status
                .imageCaptions, // ✅ Add imageCaptions for multi-image support
            'postedAt': status.createdAt,
            'expiresAt': status.createdAt.add(const Duration(hours: 24)),
            'creatorId': status.teacherId,
          },
        )
        .toList();

    openAnnouncementPageView(
      context,
      announcements: announcements,
      initialIndex: initialIndex,
      currentUserId: currentUserId,
      onAnnouncementViewed: (index) {
        // Status viewing is tracked separately in Firestore
        // This callback just logs the viewed announcement
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
      },
      onDelete: (index) {
        if (index < statuses.length) {
          final status = statuses[index];
          final item = _AnnouncementItem(
            id: status.id,
            creatorId: status.teacherId,
            creatorName: status.teacherName,
            createdAt: status.createdAt,
            hasImage: status.imageUrl != null && status.imageUrl!.isNotEmpty,
            imageUrl: status.imageUrl,
            type: 'teacher',
            isViewed: false,
            data: status,
          );
          _deleteAnnouncement(item);
        }
      },
    );
  }

  /// Note: This method is kept for future implementation but currently unused
  /// To use: uncomment and call from announcement handling code
  /*
  void _showPrincipalAnnouncement(InstituteAnnouncementModel announcement) {
    // Use unified role-themed viewer instead of custom dialog
    openAnnouncementView(
      context,
      role: 'principal',
      title: announcement.text.isNotEmpty
          ? announcement.text
          : 'Principal Announcement',
      subtitle: '',
      postedByLabel: 'Posted by Principal',
      avatarUrl: null,
      postedAt: announcement.createdAt,
      expiresAt: announcement.expiresAt,
    );
  }
  */

  /// Open combined viewer with ALL announcements (teacher + principal)
  void _openCombinedAnnouncementViewer(
    List<_AnnouncementItem> allAnnouncements,
  ) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Convert all announcements to PageView format
    final announcements = allAnnouncements.map((item) {
      String role;
      String postedByLabel;
      String title;
      String? imageUrl;
      List<Map<String, String>>? imageCaptions;
      DateTime createdAt;
      DateTime expiresAt;
      String creatorId;

      if (item.type == 'teacher') {
        final status = item.data as StatusModel;
        role = 'teacher';
        postedByLabel = 'Posted by ${status.teacherName}';
        title = status.text;
        imageUrl = status.imageUrl;
        imageCaptions = status.imageCaptions;
        createdAt = status.createdAt;
        expiresAt = status.createdAt.add(const Duration(hours: 24));
        creatorId = status.teacherId;
      } else {
        final principal = item.data as InstituteAnnouncementModel;
        role = 'principal';
        postedByLabel = 'Posted by ${principal.principalName}';

        // Get image URL - prefer imageCaptions[0] if available, fallback to imageUrl
        String? displayImageUrl;
        String displayText;

        if (principal.imageCaptions != null &&
            principal.imageCaptions!.isNotEmpty) {
          final urlFromCaptions = principal.imageCaptions![0]['url'];
          // Validate URL is not empty
          displayImageUrl =
              (urlFromCaptions != null && urlFromCaptions.isNotEmpty)
              ? urlFromCaptions
              : null;
          final caption = principal.imageCaptions![0]['caption'];
          displayText = (caption != null && caption.isNotEmpty)
              ? caption
              : (principal.text.isNotEmpty
                    ? principal.text
                    : 'Principal Announcement');
        } else if (principal.imageUrl != null &&
            principal.imageUrl!.isNotEmpty) {
          displayImageUrl = principal.imageUrl;
          displayText = principal.text.isNotEmpty
              ? principal.text
              : 'Principal Announcement';
        } else {
          displayImageUrl = null;
          displayText = principal.text.isNotEmpty
              ? principal.text
              : 'Principal Announcement';
        }

        title = displayText;
        imageUrl = displayImageUrl;
        imageCaptions = principal.imageCaptions;
        createdAt = principal.createdAt;
        expiresAt = principal.expiresAt;
        creatorId = principal.principalId;
      }

      return {
        'role': role,
        'title': title,
        'subtitle': '',
        'postedByLabel': postedByLabel,
        'avatarUrl': imageUrl,
        'imageCaptions': imageCaptions, // Add imageCaptions
        'postedAt': createdAt,
        'expiresAt': expiresAt,
        'creatorId': creatorId,
      };
    }).toList();

    // Sort by timestamp (newest first)
    announcements.sort((a, b) {
      final dateA = a['postedAt'] as DateTime;
      final dateB = b['postedAt'] as DateTime;
      return dateB.compareTo(dateA);
    });

    openAnnouncementPageView(
      context,
      announcements: announcements,
      initialIndex: 0,
      currentUserId: authProvider.currentUser?.uid,
      onAnnouncementViewed: (index) {
        // Mark announcements as viewed
        if (index < allAnnouncements.length) {
          final item = allAnnouncements[index];

          // Update cache immediately for instant UI update
          _viewedCache[item.id] = true;

          if (item.type == 'principal') {
            final authProvider = Provider.of<AuthProvider>(
              context,
              listen: false,
            );
            final userId = authProvider.currentUser?.uid ?? '';
            if (userId.isNotEmpty) {
              final principal = item.data as InstituteAnnouncementModel;
              _markPrincipalAnnouncementAsViewed(principal.id, userId);
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _viewedPrincipalAnnouncements.add(principal.id);
                  });
                }
              });
            }
          } else if (item.type == 'teacher') {
            // Mark teacher announcement as viewed
            final status = item.data as StatusModel;
            final authProvider = Provider.of<AuthProvider>(
              context,
              listen: false,
            );
            final userId = authProvider.currentUser?.uid ?? '';
            if (userId.isNotEmpty) {
              FirebaseFirestore.instance
                  .collection('class_highlights')
                  .doc(status.id)
                  .update({
                    'viewedBy': FieldValue.arrayUnion([userId]),
                  })
                  .catchError((e) {});

              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {});
                }
              });
            }
          }
        }
      },
      onDelete: (index) {
        if (index < allAnnouncements.length) {
          final item = allAnnouncements[index];
          _deleteAnnouncement(item);
        }
      },
    );
  }

  /// Mark a principal announcement as viewed by updating Firestore
  Future<void> _markPrincipalAnnouncementAsViewed(
    String announcementId,
    String userId,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(announcementId)
          .collection('views')
          .doc(userId)
          .set({
            'viewedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Also store a quick array flag for fast badge checks
      await FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(announcementId)
          .update({
            'viewedBy': FieldValue.arrayUnion([userId]),
          });

      // Debug log for visibility badge issues
    } catch (e) {}
  }

  /// Delete an announcement (including image from Cloudflare R2)
  Future<void> _deleteAnnouncement(_AnnouncementItem item) async {
    try {
      // Check if user is the creator
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;

      if (item.type == 'teacher') {
        final status = item.data as StatusModel;
        if (status.teacherId != currentUserId) {
          showErrorSnackbar(
            context,
            'You can only delete your own announcements.',
            role: 'teacher',
          );
          return;
        }
      } else if (item.type == 'principal') {
        final principal = item.data as InstituteAnnouncementModel;
        if (principal.principalId != currentUserId) {
          showErrorSnackbar(
            context,
            'You can only delete your own announcements.',
            role: 'principal',
          );
          return;
        }
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Announcement'),
          content: const Text(
            'Are you sure you want to delete this announcement? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      try {
        String? imageUrl;
        String docId;
        String role;

        // Extract info based on type
        if (item.type == 'teacher') {
          final status = item.data as StatusModel;
          docId = status.id;
          imageUrl = status.imageUrl;
          role = 'teacher';

          // Delete from Firestore
          await FirebaseFirestore.instance
              .collection('class_highlights')
              .doc(docId)
              .delete();
        } else if (item.type == 'principal') {
          final principal = item.data as InstituteAnnouncementModel;
          docId = principal.id;
          imageUrl = principal.imageUrl;
          role = 'principal';

          // Delete from Firestore
          await FirebaseFirestore.instance
              .collection('institute_announcements')
              .doc(docId)
              .delete();
        } else {
          throw Exception('Unknown announcement type: ${item.type}');
        }

        // Delete image from Cloudflare R2 if it exists
        if (imageUrl != null && imageUrl.isNotEmpty) {
          try {
            final r2Key = _extractR2KeyFromUrl(imageUrl);

            if (r2Key.isNotEmpty) {
              final r2Service = CloudflareR2Service(
                accountId: CloudflareConfig.accountId,
                bucketName: CloudflareConfig.bucketName,
                accessKeyId: CloudflareConfig.accessKeyId,
                secretAccessKey: CloudflareConfig.secretAccessKey,
                r2Domain: CloudflareConfig.r2Domain,
              );

              await r2Service.deleteFile(key: r2Key);
            } else {}
          } catch (r2Error) {
            // Continue anyway - metadata is already deleted
          }
        } else {}

        if (mounted) {
          showSuccessSnackbar(
            context,
            'Announcement deleted successfully.',
            role: role,
          );

          // Close the viewer
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackbar(
            context,
            'Failed to delete announcement: $e',
            role: item.type == 'teacher' ? 'teacher' : 'principal',
          );
        }
      }
    } catch (e) {}
  }

  /// Extract R2 key from public URL
  /// URL format: https://files.lenv1.tech/media/{timestamp}/{filename}
  /// or https://files.lenv1.tech/class_highlights/{timestamp}/{filename}
  String _extractR2KeyFromUrl(String? url) {
    try {
      // Validate input
      if (url == null || url.isEmpty) {
        return '';
      }

      // Remove any whitespace
      url = url.trim();

      // If URL doesn't start with http, it might already be a key
      if (!url.startsWith('http')) {
        return url;
      }

      // Handle full URLs with files.lenv1.tech domain
      if (url.contains('files.lenv1.tech')) {
        try {
          final uri = Uri.parse(url);
          var path = uri.path;

          // Remove leading slash if present
          if (path.startsWith('/')) {
            path = path.substring(1);
          }

          if (path.isNotEmpty) {
            return path;
          }
        } catch (parseError) {
          // Fallback: extract using string split
          final parts = url.split('files.lenv1.tech/');
          if (parts.length > 1) {
            final key = parts[1];
            if (key.isNotEmpty) {
              return key;
            }
          }
        }
      } else {
        // Not a files.lenv1.tech URL, try parsing anyway
        try {
          final uri = Uri.parse(url);
          var path = uri.path;

          if (path.startsWith('/')) {
            path = path.substring(1);
          }

          if (path.isNotEmpty) {
            return path;
          }
        } catch (parseError) {}
      }

      return '';
    } catch (e) {
      return '';
    }
  }

  /// Note: This method is kept for future implementation but currently unused
  /// To use: uncomment and call from announcement formatting code
  /*
  String _formatAnnouncementTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
  */

  // Old bottom sheet method - REMOVED
  // Now using TeacherAnnouncementTargetScreen and TeacherAnnouncementComposeScreen
  /*
  Future<void> _showCreateHighlightSheet() async {
    final textController = TextEditingController();
    List<Map<String, dynamic>> previewImages = []; // Multiple images with bytes and mime
    bool posting = false;

    // Audience selection state
    String selectedAudience = 'school'; // 'school', 'standard', 'section'
    Set<String> selectedStandards = {};
    Set<String> selectedSections = {};
    bool allStandards = false;
    bool allSections = false;

    // Available standards (fetch from school's students)
    final availableStandards = <String>[];
    // bool standardsLoaded = false; // not used

    // Teacher's assigned sections (extract from _classes or _teacherData)
    final teacherSections = <String>[];

    // Parse sections from teacher's classes into combined format e.g., "7A"
    for (final className in _classes) {
      final parts = className.split(' - ');
      if (parts.length == 2) {
        final standard = parts[0].replaceAll('Grade ', '').trim();
        final section = parts[1].trim();
        final combinedSection = '$standard$section';
        if (!teacherSections.contains(combinedSection)) {
          teacherSections.add(combinedSection);
        }
      }
    }

    // Sort sections for better display
    teacherSections.sort();

    // Fetch available standards from the school's students
    Future<void> fetchAvailableStandards() async {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final schoolCode =
            authProvider.currentUser?.instituteId ??
            _teacherData?['schoolCode'] ??
            '';

        if (schoolCode.isEmpty) {
          availableStandards.addAll(['6', '7', '8', '9', '10', '11', '12']);
          return;
        }

        // Query students and extract unique standards
        final studentsSnapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('schoolCode', isEqualTo: schoolCode)
            .get();

        final uniqueStandards = <String>{};
        for (final doc in studentsSnapshot.docs) {
          final className = doc.data()['className']?.toString() ?? '';
          // Extract grade number from formats like "Grade 10", "Grade 8", etc.
          final grade = className
              .replaceAll('Grade ', '')
              .replaceAll('grade ', '')
              .trim();

          if (grade.isNotEmpty && RegExp(r'^\d+$').hasMatch(grade)) {
            uniqueStandards.add(grade);
          }
        }

        availableStandards.addAll(uniqueStandards.toList()..sort());

        // Fallback: if no students found, show common grades
        if (availableStandards.isEmpty) {
          availableStandards.addAll(['6', '7', '8', '9', '10', '11', '12']);
        }
      } catch (e) {
        // Fallback on error
        availableStandards.addAll(['6', '7', '8', '9', '10', '11', '12']);
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            // Fetch standards on first build
            if (availableStandards.isEmpty) {
              fetchAvailableStandards().then((_) {
                setSheetState(() {
                  // Trigger rebuild after standards are loaded
                });
              });
            }
            Future<void> pickImage() async {
              final picker = ImagePicker();
              
              // Pick multiple images (max 5)
              List<XFile> pickedFiles = [];
              try {
                pickedFiles = await picker.pickMultiImage(
                  imageQuality: 85,
                  limit: 5,
                );
              } catch (e) {
                // Fallback to single image if pickMultiImage fails
                final x = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                );
                if (x != null) pickedFiles = [x];
              }
              
              if (pickedFiles.isEmpty) return;
              
              for (final x in pickedFiles) {
                try {
                  final bytes = await x.readAsBytes();
                  String? mime;
                  final p = x.path.toLowerCase();
                  if (p.endsWith('.png')) mime = 'image/png';
                  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) {
                    mime = 'image/jpeg';
                  }
                  setSheetState(() {
                    previewImages.add({
                      'bytes': bytes,
                      'mime': mime ?? 'image/jpeg',
                    });
                  });
                } catch (_) {}
              }
            }

            Future<void> removeImage(int index) async {
              setSheetState(() {
                if (index >= 0 && index < previewImages.length) {
                  previewImages.removeAt(index);
                }
              });
            }

            Future<void> post() async {
              if (posting) return;

              // Validate message is not empty
              final messageText = textController.text.trim();
              if (messageText.isEmpty && previewImages.isEmpty) {
                showErrorSnackbar(
                  context,
                  'Please enter a message or add an image',
                  role: 'teacher',
                );
                return;
              }

              // Validate standards selection (mandatory)
              if (selectedAudience == 'standard' && selectedStandards.isEmpty) {
                showErrorSnackbar(
                  context,
                  'Please select at least one standard',
                  role: 'teacher',
                );
                return;
              }

              // Validate sections selection
              if (selectedAudience == 'section' && selectedSections.isEmpty) {
                showErrorSnackbar(
                  context,
                  'Please select at least one section',
                  role: 'teacher',
                );
                return;
              }

              String effectiveAudience = selectedAudience;
              List<String> effectiveStandards = selectedStandards.toList();
              List<String> effectiveSections = selectedSections.toList();

              setSheetState(() => posting = true);
              try {
                await _postHighlight(
                  text: textController.text.trim(),
                  imagesData: previewImages,
                  audienceType: effectiveAudience,
                  standards: effectiveStandards,
                  sections: effectiveSections,
                );
                if (mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  showSuccessSnackbar(
                    context,
                    'Announcement posted for 24 hours.',
                    role: 'teacher',
                  );
                }
              } catch (e) {
                if (mounted) {
                  showErrorSnackbar(
                    context,
                    getFriendlyErrorMessage(e),
                    role: 'teacher',
                  );
                }
              } finally {
                if (mounted) setSheetState(() => posting = false);
              }
            }

            void selectAllStandards(bool value) {
              setSheetState(() {
                allStandards = value;
                if (allStandards) {
                  selectedStandards = availableStandards.toSet();
                } else {
                  selectedStandards.clear();
                }
              });
            }

            void selectAllSections(bool value) {
              setSheetState(() {
                allSections = value;
                if (allSections) {
                  selectedSections = teacherSections.toSet();
                } else {
                  selectedSections.clear();
                }
              });
            }

            final mq = MediaQuery.of(ctx);
            final kbInsets = mq.viewInsets.bottom;
            final maxHeight =
                mq.size.height * 0.88; // cap to 88% of height for compactness

            // Theme-aware colors
            final theme = Theme.of(ctx);
            final isDark = theme.brightness == Brightness.dark;
            final bgColor = isDark ? const Color(0xFF120F23) : Colors.white;
            const primary = Color(0xFF7961FF);
            final cardBg = isDark
                ? const Color(0xFF1A1730)
                : const Color(0xFFF5F5F5);
            final borderColor = isDark
                ? const Color(0xFF2D2640)
                : const Color(0xFFE0E0E0);
            final textMuted = isDark
                ? const Color(0xFF8E8BA3)
                : const Color(0xFF757575);
            final textColor = isDark ? Colors.white : Colors.black87;

            return Padding(
              padding: EdgeInsets.only(bottom: kbInsets),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Grab handle
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Header with title and close button
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [primary, Color(0xFF9D8DFF)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.campaign_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'New Announcement',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Visible for 24 hours',
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                if (posting)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    child: const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                          primary,
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  GestureDetector(
                                    onTap: () => Navigator.of(ctx).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: textMuted,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Audience tabs with underline indicator
                            Container(
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                children: [
                                  for (final item in const [
                                    {
                                      'key': 'school',
                                      'icon': Icons.school_rounded,
                                      'label': 'School',
                                    },
                                    {
                                      'key': 'standard',
                                      'icon': Icons.class_rounded,
                                      'label': 'Standards',
                                    },
                                    {
                                      'key': 'section',
                                      'icon': Icons.groups_rounded,
                                      'label': 'Sections',
                                    },
                                  ])
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setSheetState(() {
                                            final String itemKey =
                                                item['key'] as String;
                                            selectedAudience = itemKey;
                                            // Clear opposing selections when switching
                                            if (selectedAudience == 'school') {
                                              selectedStandards.clear();
                                              selectedSections.clear();
                                              allStandards = false;
                                              allSections = false;
                                            } else if (selectedAudience ==
                                                'standard') {
                                              selectedSections.clear();
                                              allSections = false;
                                            } else if (selectedAudience ==
                                                'section') {
                                              selectedStandards.clear();
                                              allStandards = false;
                                            }
                                          });
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeInOut,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                selectedAudience ==
                                                    (item['key'] as String)
                                                ? primary.withOpacity(0.15)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    item['icon'] as IconData,
                                                    size: 16,
                                                    color:
                                                        selectedAudience ==
                                                            (item['key']
                                                                as String)
                                                        ? primary
                                                        : textMuted,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    item['label'] as String,
                                                    style: TextStyle(
                                                      color:
                                                          selectedAudience ==
                                                              (item['key']
                                                                  as String)
                                                          ? textColor
                                                          : textMuted,
                                                      fontWeight:
                                                          selectedAudience ==
                                                              (item['key']
                                                                  as String)
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              // Underline indicator
                                              AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                height: 3,
                                                width:
                                                    selectedAudience ==
                                                        (item['key'] as String)
                                                    ? 40
                                                    : 0,
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      selectedAudience ==
                                                          (item['key']
                                                              as String)
                                                      ? const LinearGradient(
                                                          colors: [
                                                            primary,
                                                            Color(0xFF9D8DFF),
                                                          ],
                                                        )
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Message input area
                            Container(
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              padding: const EdgeInsets.all(16),
                              child: TextField(
                                controller: textController,
                                minLines: 3,
                                maxLines: 5,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      'Write your announcement here...\nThis will be visible for 24 hours.',
                                  hintStyle: TextStyle(
                                    color: textMuted.withOpacity(0.6),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),

                            // Animated standards/sections panels
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: Column(
                                children: [
                                  if (selectedAudience == 'standard') ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: borderColor),
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: primary.withOpacity(
                                                    0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.class_rounded,
                                                  size: 16,
                                                  color: primary,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                'Select Standards',
                                                style: TextStyle(
                                                  color: textColor,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const Spacer(),
                                              GestureDetector(
                                                onTap: () => selectAllStandards(
                                                  !allStandards,
                                                ),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: allStandards
                                                        ? primary.withOpacity(
                                                            0.15,
                                                          )
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: allStandards
                                                          ? primary
                                                          : borderColor,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    allStandards
                                                        ? 'Deselect All'
                                                        : 'Select All',
                                                    style: TextStyle(
                                                      color: allStandards
                                                          ? primary
                                                          : textMuted,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          availableStandards.isEmpty
                                              ? const Center(
                                                  child: Padding(
                                                    padding: EdgeInsets.all(
                                                      16.0,
                                                    ),
                                                    child:
                                                        CircularProgressIndicator(
                                                          color: primary,
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                )
                                              : Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    for (final std
                                                        in availableStandards)
                                                      GestureDetector(
                                                        onTap: () {
                                                          setSheetState(() {
                                                            if (selectedStandards
                                                                .contains(
                                                                  std,
                                                                )) {
                                                              selectedStandards
                                                                  .remove(std);
                                                            } else {
                                                              selectedStandards
                                                                  .add(std);
                                                            }
                                                            allStandards =
                                                                selectedStandards
                                                                    .length ==
                                                                availableStandards
                                                                    .length;
                                                          });
                                                        },
                                                        child: AnimatedContainer(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    150,
                                                              ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 16,
                                                                vertical: 10,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                selectedStandards
                                                                    .contains(
                                                                      std,
                                                                    )
                                                                ? primary
                                                                : Colors
                                                                      .transparent,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  selectedStandards
                                                                      .contains(
                                                                        std,
                                                                      )
                                                                  ? primary
                                                                  : borderColor,
                                                              width: 1.5,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            'Grade $std',
                                                            style: TextStyle(
                                                              color:
                                                                  selectedStandards
                                                                      .contains(
                                                                        std,
                                                                      )
                                                                  ? Colors.white
                                                                  : (isDark
                                                                        ? textMuted
                                                                        : textColor),
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (selectedAudience == 'section') ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: cardBg,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: borderColor),
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: primary.withOpacity(
                                                    0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.groups_rounded,
                                                  size: 16,
                                                  color: primary,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                'Your Sections',
                                                style: TextStyle(
                                                  color: textColor,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const Spacer(),
                                              if (teacherSections.isNotEmpty)
                                                GestureDetector(
                                                  onTap: () =>
                                                      selectAllSections(
                                                        !allSections,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: allSections
                                                          ? primary.withOpacity(
                                                              0.15,
                                                            )
                                                          : Colors.transparent,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color: allSections
                                                            ? primary
                                                            : borderColor,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      allSections
                                                          ? 'Deselect All'
                                                          : 'Select All',
                                                      style: TextStyle(
                                                        color: allSections
                                                            ? primary
                                                            : textMuted,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          if (teacherSections.isEmpty)
                                            Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFFFF9500,
                                                ).withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFFF9500,
                                                  ).withOpacity(0.3),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFFF9500,
                                                      ).withOpacity(0.15),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons
                                                          .info_outline_rounded,
                                                      color: Color(0xFFFF9500),
                                                      size: 18,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  const Expanded(
                                                    child: Text(
                                                      'No assigned sections found. Please contact admin to assign classes.',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFFFF9500,
                                                        ),
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                for (final sec
                                                    in teacherSections)
                                                  GestureDetector(
                                                    onTap: () {
                                                      setSheetState(() {
                                                        if (selectedSections
                                                            .contains(sec)) {
                                                          selectedSections
                                                              .remove(sec);
                                                        } else {
                                                          selectedSections.add(
                                                            sec,
                                                          );
                                                        }
                                                        allSections =
                                                            selectedSections
                                                                .length ==
                                                            teacherSections
                                                                .length;
                                                      });
                                                    },
                                                    child: AnimatedContainer(
                                                      duration: const Duration(
                                                        milliseconds: 150,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 16,
                                                            vertical: 10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            selectedSections
                                                                .contains(sec)
                                                            ? primary
                                                            : Colors
                                                                  .transparent,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                        border: Border.all(
                                                          color:
                                                              selectedSections
                                                                  .contains(sec)
                                                              ? primary
                                                              : borderColor,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        sec,
                                                        style: TextStyle(
                                                          color:
                                                              selectedSections
                                                                  .contains(sec)
                                                              ? Colors.white
                                                              : (isDark
                                                                    ? textMuted
                                                                    : textColor),
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Image preview area - Multiple images in horizontal scroll
                            if (previewImages.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                height: 120,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: previewImages.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (_, index) {
                                    final imageData = previewImages[index];
                                    return Container(
                                      width: 120,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Stack(
                                          children: [
                                            Image.memory(
                                              imageData['bytes'] as Uint8List,
                                              height: 120,
                                              width: 120,
                                              fit: BoxFit.cover,
                                            ),
                                            Positioned(
                                              right: 4,
                                              top: 4,
                                              child: GestureDetector(
                                                onTap: () => removeImage(index),
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.6),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.close_rounded,
                                                    size: 16,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Image counter badge
                                            Positioned(
                                              left: 4,
                                              bottom: 4,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.6),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '${index + 1}/${previewImages.length}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                            // Action buttons
                            Row(
                              children: [
                                // Add Image button
                                Expanded(
                                  child: GestureDetector(
                                    onTap: pickImage,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_outlined,
                                            color: textMuted,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            previewImages.isEmpty 
                                                ? 'Add Images' 
                                                : 'Add More (${previewImages.length}/5)',
                                            style: TextStyle(
                                              color: textMuted,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Post button
                                Expanded(
                                  flex: 2,
                                  child: GestureDetector(
                                    onTap: posting ? null : post,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [primary, Color(0xFF9D8DFF)],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color: primary.withOpacity(0.3),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (posting) ...[
                                            const SizedBox(
                                              height: 18,
                                              width: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation(
                                                      Colors.white,
                                                    ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            const Text(
                                              'Posting...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ] else ...[
                                            const Icon(
                                              Icons.send_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Post Announcement',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        ],
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
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _postHighlight({
    String? text,
    List<Map<String, dynamic>>? imagesData, // Multiple images with bytes and mime
    required String audienceType,
    required List<String> standards,
    required List<String> sections,
  }) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) throw 'User not logged in';

    // Validate message content
    if ((text == null || text.isEmpty) && 
        (imagesData == null || imagesData.isEmpty)) {
      throw 'Message cannot be empty. Please add text or image.';
    }

    // Validate audience selection (mandatory)
    if (audienceType == 'standard' && standards.isEmpty) {
      throw 'Standards selection is mandatory. Please select at least one standard.';
    }
    if (audienceType == 'section' && sections.isEmpty) {
      throw 'Section selection is mandatory. Please select at least one section.';
    }

    // Upload multiple images to Cloudflare R2
    final List<Map<String, String>> imageCaptions = [];
    
    if (imagesData != null && imagesData.isNotEmpty) {
      try {
        final r2Service = CloudflareR2Service(
          accountId: CloudflareConfig.accountId,
          bucketName: CloudflareConfig.bucketName,
          accessKeyId: CloudflareConfig.accessKeyId,
          secretAccessKey: CloudflareConfig.secretAccessKey,
          r2Domain: CloudflareConfig.r2Domain,
        );

        for (int i = 0; i < imagesData.length; i++) {
          final imageData = imagesData[i];
          final imageBytes = imageData['bytes'] as Uint8List;
          final imageMime = imageData['mime'] as String;
          
          final fileName =
              'highlight_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';

          // Generate signed URL
          final signedData = await r2Service.generateSignedUploadUrl(
            fileName: 'class_highlights/$fileName',
            fileType: imageMime,
          );

          // Upload file
          final imageUrl = await r2Service.uploadFileWithSignedUrl(
            fileBytes: imageBytes,
            signedUrl: signedData['url'],
            contentType: imageMime,
          );
          
          // Add to imageCaptions array
          imageCaptions.add({
            'url': imageUrl,
            'caption': '', // Empty caption for now
          });
        }
      } catch (e) {
        rethrow;
      }
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));
    final instituteId =
        currentUser.instituteId ?? _teacherData?['schoolCode'] ?? '';

    final data = <String, dynamic>{
      'teacherId': currentUser.uid,
      'teacherName':
          _teacherData?['teacherName'] ?? currentUser.name ?? 'Teacher',
      'teacherEmail': currentUser.email,
      'instituteId': instituteId,
      'className': selectedClass ?? 'School-wide',
      'text': text ?? '',
      'imageUrl': imageCaptions.isNotEmpty ? imageCaptions[0]['url'] : '', // Legacy support
      'imageCaptions': imageCaptions, // New multi-image support
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      // Audience targeting
      'audienceType': audienceType,
      'standards': standards,
      'sections': sections,
      // Viewing tracking
      'viewedBy': [], // Initialize empty array
    };

    await FirebaseFirestore.instance.collection('class_highlights').add(data);
  }
  */

  // Old _postHighlight method - REMOVED
  // Now handled by TeacherAnnouncementComposeScreen

  Widget _buildClassSummary() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final instituteId =
        currentUser?.instituteId ?? _teacherData?['schoolCode'] ?? '';
    final sections = _teacherData?['sections'] ?? _teacherData?['section'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Class Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _teacherService.getStudentsByTeacherStream(
            instituteId,
            _teacherData?['classesHandled'],
            sections,
            classAssignments: _teacherData?['classAssignments'],
          ),
          builder: (context, snapshot) {
            final allStudents = snapshot.data ?? _students;

            List<Map<String, dynamic>> filteredStudents = allStudents;

            if (selectedClass != null && selectedClass!.isNotEmpty) {
              // Remove subject if present (format: "10 - A::english")
              final classOnly = selectedClass!.split('::').first;
              final parts = classOnly.split(' - ');
              if (parts.length == 2) {
                final selectedGrade = parts[0].trim();
                final selectedSection = parts[1].trim();

                filteredStudents = allStudents.where((student) {
                  final studentClassName =
                      student['className']?.toString() ?? '';
                  final studentGrade = studentClassName
                      .replaceAll('Grade ', '')
                      .replaceAll('grade ', '')
                      .trim();
                  final studentSection = student['section']?.toString() ?? '';

                  return studentGrade == selectedGrade &&
                      studentSection == selectedSection;
                }).toList();
              }
            }

            final totalStudents = filteredStudents.length;
            final totalAllStudents = allStudents.length;

            return Row(
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
            );
          },
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
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.7),
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
            Text(
              'Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '0',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
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
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No pending alerts',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
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
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(32),
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
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.history,
                  size: 48,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No recent activity',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildBottomNavigationBar() {
    return const TeacherBottomNav(selectedIndex: 0);
  }

  /// Shimmer loading placeholder for highlights
  Widget _buildShimmerCircle(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.grey[300],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 60,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: theme.brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.grey[300],
          ),
        ),
      ],
    );
  }

  /// Fast loading skeleton shown while data loads
  Widget _buildLoadingSkeleton() {
    final theme = Theme.of(context);
    final shimmerColor = theme.brightness == Brightness.dark
        ? Colors.grey[800]
        : Colors.grey[300];

    return Column(
      children: [
        const SizedBox(height: 48),
        // Header skeleton without orange gradient
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 200,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: shimmerColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 150,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: shimmerColor,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Stats banner skeleton
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: shimmerColor,
                  ),
                ),
                const SizedBox(height: 24),
                // Cards skeleton
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: shimmerColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // _buildNavItem removed in favor of shared TeacherBottomNav

  // Combine announcements from both teachers and principals
  Stream<List<Map<String, dynamic>>> _combineAnnouncementStreams(
    String instituteId,
  ) async* {
    final now = Timestamp.now();

    await for (final teacherSnapshot
        in FirebaseFirestore.instance
            .collection('class_highlights')
            .where('instituteId', isEqualTo: instituteId)
            .where('expiresAt', isGreaterThan: now)
            .snapshots()) {
      // Get principal announcements as a one-time fetch (respect expiry)
      final principalSnapshot = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .where('instituteId', isEqualTo: instituteId)
          .where('audienceType', isEqualTo: 'school')
          .where('expiresAt', isGreaterThan: now)
          .get();

      final combined = <Map<String, dynamic>>[];

      // Add teacher announcements
      for (final doc in teacherSnapshot.docs) {
        combined.add({'type': 'teacher', 'snapshot': doc});
      }

      // Add principal announcements
      for (final doc in principalSnapshot.docs) {
        combined.add({'type': 'principal', 'snapshot': doc});
      }

      yield combined;
    }
  }
}

// Helper class to unify teacher and principal announcements
class _AnnouncementItem {
  final String id;
  final String creatorId;
  final String creatorName;
  final DateTime createdAt;
  final bool hasImage;
  final String? imageUrl;
  final String type; // 'teacher' or 'principal'
  final bool isViewed;
  final dynamic data; // StatusModel or InstituteAnnouncementModel

  _AnnouncementItem({
    required this.id,
    required this.creatorId,
    required this.creatorName,
    required this.createdAt,
    required this.hasImage,
    this.imageUrl,
    required this.type,
    required this.isViewed,
    required this.data,
  });
}
