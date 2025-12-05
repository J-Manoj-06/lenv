import 'package:flutter/material.dart';
import '../../utils/feedback_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/teacher_bottom_nav.dart';
import '../../services/teacher_service.dart';
import '../../services/firestore_service.dart';
import '../../models/status_model.dart';
import 'status_view_screen.dart';
import 'attendance_screen.dart';

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
  bool _isLoading = true;
  String? _error;

  // Highlights: best-effort cleanup on load
  Future<void> _cleanupExpiredHighlights() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final uid = auth.currentUser?.uid;
      if (uid == null) return;
      final now = DateTime.now();
      final qs = await FirebaseFirestore.instance
          .collection('class_highlights')
          .where('teacherId', isEqualTo: uid)
          .get();
      final expired = qs.docs.where((d) {
        final ts = (d.data()['expiresAt'] as Timestamp?)?.toDate();
        return ts != null && !ts.isAfter(now);
      }).toList();
      if (expired.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in expired) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } catch (_) {
      // silent best-effort
    }
  }

  @override
  void initState() {
    super.initState();
    // Load data immediately to show UI faster
    _loadTeacherData();
    // Defer non-critical cleanup to after page loads
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _cleanupExpiredHighlights();
        _autoPublishTests();
      }
    });
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
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;

      // Skip expensive re-initialization - user is already logged in
      if (currentUser == null) {
        // Only initialize if truly not logged in
        await authProvider.initializeAuth();
        final retryUser = authProvider.currentUser;
        if (retryUser == null) {
          setState(() {
            _error = 'No user logged in';
            _isLoading = false;
          });
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

      final teacherData = results[0] as Map<String, dynamic>?;

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

      // Fetch students in background after UI is shown
      _fetchStudentsInBackground(user, teacherData, sections, classes);
    } catch (e) {
      print('Error loading teacher data: $e');
      setState(() {
        _error = 'Failed to load data';
        _isLoading = false;
      });
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
    } catch (e) {
      print('Error fetching students: $e');
      // Don't show error, just leave students empty
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? _buildLoadingSkeleton()
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
                        _buildGradientStatsBanner(),
                        const SizedBox(height: 24),
                        _buildClassroomHighlights(),
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
                  IconButton(
                    icon: const Icon(Icons.person_outline),
                    color: Theme.of(context).iconTheme.color,
                    onPressed: () {
                      Navigator.pushNamed(context, '/profile');
                    },
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
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('class_highlights')
                .where('instituteId', isEqualTo: instituteId)
                .snapshots(),
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

              final docs = snapshot.data?.docs ?? [];

              // Convert docs to StatusModel and filter valid ones
              final allStatuses =
                  docs
                      .map((d) => StatusModel.fromFirestore(d))
                      .where((s) => s.isValid && s.instituteId == instituteId)
                      .toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              // Segregate: My announcements vs Other Teachers
              final myStatuses = allStatuses
                  .where((s) => s.teacherId == currentUserId)
                  .toList();

              // Group other teachers' announcements by teacherId
              final otherTeachersMap = <String, List<StatusModel>>{};
              for (final status in allStatuses) {
                if (status.teacherId != currentUserId) {
                  otherTeachersMap
                      .putIfAbsent(status.teacherId, () => [])
                      .add(status);
                }
              }

              // Sort each teacher's announcements by timestamp
              otherTeachersMap.forEach((key, value) {
                value.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              });

              // Create list of other teachers (sorted by latest post)
              final otherTeachers = otherTeachersMap.entries.toList()
                ..sort(
                  (a, b) => b.value.first.createdAt.compareTo(
                    a.value.first.createdAt,
                  ),
                );

              // Build single horizontal list: My Announcement + Other Teachers
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: 1 + otherTeachers.length, // 1 for "My Announcement"
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // My Announcement (always first)
                    return _buildMyAnnouncementAvatar(
                      theme,
                      myStatuses,
                      currentUser,
                    );
                  } else {
                    // Other Teachers
                    final teacherEntry = otherTeachers[index - 1];
                    final statuses = teacherEntry.value;
                    final latestStatus = statuses.first;
                    return _buildOtherTeacherAvatar(
                      theme,
                      latestStatus,
                      statuses,
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
    List<StatusModel> myStatuses,
    dynamic currentUser,
  ) {
    final hasAnnouncement = myStatuses.isNotEmpty;
    final latestStatus = hasAnnouncement ? myStatuses.first : null;

    return GestureDetector(
      onTap: () {
        if (hasAnnouncement) {
          _openStatusViewer(myStatuses, 0);
        } else {
          _showCreateHighlightSheet();
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
                        ? (latestStatus!.hasImage
                              ? Colors.transparent
                              : const Color(0xFF7E57C2))
                        : theme.cardColor,
                  ),
                  child: ClipOval(
                    child: hasAnnouncement && latestStatus!.hasImage
                        ? Image.network(
                            latestStatus.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildDefaultAvatar(
                              currentUser?.name ?? 'Teacher',
                              theme,
                            ),
                          )
                        : _buildDefaultAvatar(
                            currentUser?.name ?? 'Teacher',
                            theme,
                          ),
                  ),
                ),
              ),

              // Add (+) Icon Overlay
              Positioned(
                right: -2,
                bottom: -2,
                child: GestureDetector(
                  onTap: _showCreateHighlightSheet,
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

  // Other Teacher Avatar (Subsequent items in horizontal list)
  Widget _buildOtherTeacherAvatar(
    ThemeData theme,
    StatusModel latestStatus,
    List<StatusModel> allStatuses,
  ) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUser?.uid ?? '';

    // Check if any of this teacher's announcements are unviewed
    final hasUnviewed = allStatuses.any(
      (s) => !s.hasBeenViewedBy(currentUserId),
    );

    return GestureDetector(
      onTap: () => _openStatusViewer(allStatuses, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with gradient border
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
                        Colors.grey.withOpacity(0.4),
                        Colors.grey.withOpacity(0.3),
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
                color: latestStatus.hasImage
                    ? Colors.transparent
                    : const Color(0xFF7E57C2),
              ),
              child: ClipOval(
                child: latestStatus.hasImage
                    ? ColorFiltered(
                        colorFilter: hasUnviewed
                            ? const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.multiply,
                              )
                            : ColorFilter.mode(
                                Colors.grey.withOpacity(0.5),
                                BlendMode.saturation,
                              ),
                        child: Image.network(
                          latestStatus.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _buildTeacherInitial(latestStatus.teacherName),
                        ),
                      )
                    : Opacity(
                        opacity: hasUnviewed ? 1.0 : 0.5,
                        child: _buildTeacherInitial(latestStatus.teacherName),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Teacher Name
          SizedBox(
            width: 70,
            child: Text(
              latestStatus.teacherName.split(' ').first,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: hasUnviewed ? FontWeight.w600 : FontWeight.w500,
                color: hasUnviewed
                    ? theme.textTheme.bodyMedium?.color
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
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

  void _openStatusViewer(List<StatusModel> statuses, int initialIndex) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUser?.uid;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusViewScreen(
          statuses: statuses,
          initialIndex: initialIndex,
          currentUserId: currentUserId,
          onStatusDeleted: () {
            // Refresh is handled automatically by StreamBuilder
            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
    );
  }

  Future<void> _showCreateHighlightSheet() async {
    final textController = TextEditingController();
    Uint8List? previewBytes;
    String? imageMime;
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
              final x = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (x != null) {
                try {
                  final bytes = await x.readAsBytes();
                  String? mime;
                  final p = x.path.toLowerCase();
                  if (p.endsWith('.png')) mime = 'image/png';
                  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) {
                    mime = 'image/jpeg';
                  }
                  setSheetState(() {
                    previewBytes = bytes;
                    imageMime = mime ?? 'image/jpeg';
                  });
                } catch (_) {}
              }
            }

            Future<void> removeImage() async {
              setSheetState(() {
                previewBytes = null;
                imageMime = null;
              });
            }

            Future<void> post() async {
              if (posting) return;

              // Validate message is not empty
              final messageText = textController.text.trim();
              if (messageText.isEmpty && previewBytes == null) {
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
                  imageBytes: previewBytes,
                  imageMime: imageMime,
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

            // Dark theme constants
            const bgDark = Color(0xFF120F23);
            const primary = Color(0xFF7961FF);
            const cardBg = Color(0xFF1A1730);
            const borderColor = Color(0xFF2D2640);
            const textMuted = Color(0xFF8E8BA3);

            return Padding(
              padding: EdgeInsets.only(bottom: kbInsets),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Container(
                  decoration: const BoxDecoration(
                    color: bgDark,
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
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'New Announcement',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
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
                                      child: const Icon(
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
                                                          ? Colors.white
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
                                style: const TextStyle(
                                  color: Colors.white,
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
                                              const Text(
                                                'Select Standards',
                                                style: TextStyle(
                                                  color: Colors.white,
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
                                                                  : textMuted,
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
                                              const Text(
                                                'Your Sections',
                                                style: TextStyle(
                                                  color: Colors.white,
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
                                                              : textMuted,
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

                            // Image preview area
                            if (previewBytes != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    children: [
                                      Image.memory(
                                        previewBytes!,
                                        height: 120,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: GestureDetector(
                                          onTap: removeImage,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(
                                                0.6,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_outlined,
                                            color: textMuted,
                                            size: 20,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Add Image',
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
    Uint8List? imageBytes,
    String? imageMime,
    required String audienceType,
    required List<String> standards,
    required List<String> sections,
  }) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) throw 'User not logged in';

    // Validate message content
    if ((text == null || text.isEmpty) && imageBytes == null) {
      throw 'Message cannot be empty. Please add text or image.';
    }

    // Validate audience selection (mandatory)
    if (audienceType == 'standard' && standards.isEmpty) {
      throw 'Standards selection is mandatory. Please select at least one standard.';
    }
    if (audienceType == 'section' && sections.isEmpty) {
      throw 'Section selection is mandatory. Please select at least one section.';
    }

    String? imageUrl;
    if (imageBytes != null) {
      try {
        final fileName =
            'highlight_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        // Simplified path to avoid nested folder issues
        final ref = FirebaseStorage.instance.ref().child(
          'class_highlights/$fileName',
        );
        final metadata = SettableMetadata(
          contentType: imageMime ?? 'image/jpeg',
          customMetadata: {
            'teacherId': currentUser.uid,
            'className': selectedClass ?? 'School-wide',
            'instituteId':
                currentUser.instituteId ?? _teacherData?['schoolCode'] ?? '',
          },
        );
        final task = await ref.putData(imageBytes, metadata);
        imageUrl = await task.ref.getDownloadURL();
      } catch (e) {
        // ignore: avoid_print
        print('❌ Storage upload error: $e');
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
      'imageUrl': imageUrl ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      // also store client timestamps for queries without server latency
      'createdAtClient': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      // Audience targeting
      'audienceType': audienceType,
      'standards': standards,
      'sections': sections,
      // Viewing tracking
      'viewedBy': [], // Initialize empty array
    };

    // Debug: Print what's being saved
    print('📢 TEACHER DEBUG: Posting announcement with:');
    print('   instituteId: "$instituteId"');
    print('   audienceType: "$audienceType"');
    print('   standards: $standards');
    print('   sections: $sections');
    print('   text: "${text ?? ''}"');

    await FirebaseFirestore.instance.collection('class_highlights').add(data);
  }

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
        // Header skeleton
        Container(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).primaryColor.withOpacity(0.3),
                Theme.of(context).primaryColor.withOpacity(0.1),
              ],
            ),
          ),
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
}
