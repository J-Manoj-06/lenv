import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import './institute_announcement_target_screen.dart';
import './principal_announcement_viewer.dart';
import './attendance_history_screen.dart';
import '../attendance_details_page.dart';
import '../messages/staff_room_chat_page.dart';
import '../../providers/auth_provider.dart';
import '../../models/institute_announcement_model.dart';
import '../../services/media_repository.dart';
import '../../services/institute_announcement_service.dart';
import '../../services/attendance_service.dart';
import '../../services/institute_announcement_cleanup_service.dart';
import '../../widgets/attendance_speedometer_gauge.dart';

class InstituteDashboardScreen extends StatefulWidget {
  const InstituteDashboardScreen({super.key});

  @override
  State<InstituteDashboardScreen> createState() =>
      _InstituteDashboardScreenState();
}

class _InstituteDashboardScreenState extends State<InstituteDashboardScreen> {
  final MediaRepository _mediaRepository = MediaRepository();
  final InstituteAnnouncementService _announcementService =
      InstituteAnnouncementService();
  Set<String> _viewedAnnouncementIds = <String>{};
  String _schoolCode = '';
  bool _cleanupScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadViewedAnnouncements();
    _initSchoolCode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-init school code when auth state changes
    if (_schoolCode.isEmpty) {
      _initSchoolCode();
    }

    // Run cleanup ONCE after first successful load (in background)
    if (_schoolCode.isNotEmpty && !_cleanupScheduled) {
      _cleanupScheduled = true;
      // Delay cleanup by 5 seconds to not interfere with initial load
      Future.delayed(const Duration(seconds: 5), () {
        InstituteAnnouncementCleanupService.cleanupExpiredAnnouncements();
      });
    }
  }

  Future<void> _initSchoolCode() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    print('🔍 DEBUG: Current User = ${currentUser?.name}');
    print('🔍 DEBUG: User Role = ${currentUser?.role}');
    print('🔍 DEBUG: User instituteId = ${currentUser?.instituteId}');
    final code = currentUser?.instituteId ?? '';
    print('🔍 DEBUG: School Code set to: "$code" (isEmpty: ${code.isEmpty})');
    if (mounted && code.isNotEmpty) {
      setState(() {
        _schoolCode = code;
      });
    }
  }

  Future<void> _loadViewedAnnouncements() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUser?.uid;
    if (userId == null || userId.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collectionGroup('views')
          .where(FieldPath.documentId, isEqualTo: userId)
          .get();

      final viewedIds = snap.docs
          .map((d) => d.reference.parent.parent?.id)
          .whereType<String>()
          .toSet();

      if (mounted) {
        setState(() {
          _viewedAnnouncementIds = viewedIds;
        });
      }
    } catch (_) {
      // Silently fail
    }
  }

  // Get real-time student count stream
  Stream<int> _getStudentCountStream(String schoolCode) {
    print('📊 DEBUG: Getting students for schoolCode="$schoolCode"');
    if (schoolCode.isEmpty) {
      print('⚠️ DEBUG: schoolCode is EMPTY, returning 0');
      return Stream.value(0);
    }

    return FirebaseFirestore.instance
        .collection('students')
        .where('schoolCode', isEqualTo: schoolCode)
        .snapshots()
        .map((snapshot) {
          print('📊 DEBUG: Students query returned ${snapshot.size} documents');
          if (snapshot.docs.isNotEmpty) {
            print(
              '📊 DEBUG: First student schoolCode: ${snapshot.docs.first.data()['schoolCode']}',
            );
          }
          return snapshot.size;
        });
  }

  // Get real-time staff count stream
  Stream<int> _getStaffCountStream(String schoolCode) {
    print('👥 DEBUG: Getting staff for schoolCode="$schoolCode"');
    if (schoolCode.isEmpty) {
      print('⚠️ DEBUG: schoolCode is EMPTY, returning 0');
      return Stream.value(0);
    }

    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .where('schoolCode', isEqualTo: schoolCode)
        .snapshots()
        .map((snapshot) {
          print('👥 DEBUG: Staff query returned ${snapshot.size} documents');
          if (snapshot.docs.isNotEmpty) {
            print(
              '👥 DEBUG: First staff schoolCode: ${snapshot.docs.first.data()['schoolCode']}',
            );
          }
          return snapshot.size;
        });
  }

  // Get real-time student attendance stream for today
  Stream<Map<String, dynamic>> _getStudentAttendanceStream(String schoolCode) {
    print('📅 DEBUG: Getting attendance for schoolCode="$schoolCode"');
    if (schoolCode.isEmpty) {
      print('⚠️ DEBUG: schoolCode is EMPTY for attendance');
      return Stream.value({'present': 0, 'total': 0, 'percent': 0.0});
    }

    // Get today's date in format: yyyy-MM-dd
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    print('📅 DEBUG: Looking for attendance date: $dateStr');

    // Combine attendance stream with total student count
    return FirebaseFirestore.instance
        .collection('students')
        .where('schoolCode', isEqualTo: schoolCode)
        .snapshots()
        .asyncMap((studentSnapshot) async {
          final totalStudents = studentSnapshot.size;
          print('📅 DEBUG: Total students in school: $totalStudents');

          // Get attendance records for today
          final attendanceSnapshot = await FirebaseFirestore.instance
              .collection('attendance')
              .where('schoolCode', isEqualTo: schoolCode)
              .where('date', isEqualTo: dateStr)
              .get();

          print(
            '📅 DEBUG: Attendance docs found: ${attendanceSnapshot.docs.length}',
          );
          int presentCount = 0;

          for (final doc in attendanceSnapshot.docs) {
            final data = doc.data();
            print(
              '📅 DEBUG: Doc ID: ${doc.id}, section: ${data['section']}, standard: ${data['standard']}',
            );
            final students = data['students'] as Map<String, dynamic>?;
            if (students == null) {
              print('⚠️ DEBUG: No students field in doc ${doc.id}');
              continue;
            }

            print(
              '📅 DEBUG: Processing ${students.length} students in doc ${doc.id}',
            );
            for (final studentEntry in students.entries) {
              final studentData = studentEntry.value as Map<String, dynamic>?;
              if (studentData == null) continue;

              final status =
                  studentData['status']?.toString().toLowerCase() ?? 'present';
              if (status == 'present') {
                presentCount++;
              }
            }
          }

          final percent = totalStudents > 0
              ? (presentCount / totalStudents * 100)
              : 0.0;

          print(
            '📅 DEBUG: Final attendance - Present: $presentCount, Total: $totalStudents, Percent: ${percent.toStringAsFixed(1)}%',
          );
          return {
            'present': presentCount,
            'total': totalStudents,
            'percent': percent,
          };
        });
  }

  // Format count with commas for readability
  String _formatCount(int count) {
    if (count == 0) return '0';
    final str = count.toString();
    final buffer = StringBuffer();
    var counter = 0;
    for (var i = str.length - 1; i >= 0; i--) {
      if (counter > 0 && counter % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
      counter++;
    }
    return buffer.toString().split('').reversed.join();
  }

  @override
  Widget build(BuildContext context) {
    print('====================================');
    print('DEBUG: InstituteDashboardScreen build method called');
    print('====================================');

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Update school code when auth provider has user data
        if (_schoolCode.isEmpty && authProvider.currentUser != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _schoolCode = authProvider.currentUser?.instituteId ?? '';
                print(
                  '🔄 DEBUG: School code updated from Consumer: $_schoolCode',
                );
              });
            }
          });
        }

        // Theme detection
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC);
        final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
        final subtitleColor = isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B);
        final tealColor = const Color(0xFF146D7A);
        final progressBgColor = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0);
        final borderColor = isDark
            ? Colors.transparent
            : const Color(0xFFE2E8F0);

        return Scaffold(
          backgroundColor: bgColor,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(
                    teal: tealColor,
                    textColor: textColor,
                    bgColor: bgColor,
                  ),
                  _SectionHeader(title: 'Announcements', textColor: textColor),
                  _buildAnnouncementsSection(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _schoolCode.isEmpty
                              ? _SkeletonStatCard(
                                  icon: Icons.school,
                                  label: 'Total Students',
                                  cardColor: cardColor,
                                  subtitleColor: subtitleColor,
                                  iconColor: tealColor,
                                  borderColor: borderColor,
                                )
                              : StreamBuilder<int>(
                                  stream: _getStudentCountStream(_schoolCode),
                                  builder: (context, snapshot) {
                                    // Show skeleton while loading
                                    if (snapshot.connectionState ==
                                            ConnectionState.waiting ||
                                        !snapshot.hasData) {
                                      return _SkeletonStatCard(
                                        icon: Icons.school,
                                        label: 'Total Students',
                                        cardColor: cardColor,
                                        subtitleColor: subtitleColor,
                                        iconColor: tealColor,
                                        borderColor: borderColor,
                                      );
                                    }

                                    final count = snapshot.data ?? 0;
                                    return _StatCard(
                                      icon: Icons.school,
                                      label: 'Total Students',
                                      value: _formatCount(count),
                                      cardColor: cardColor,
                                      textColor: textColor,
                                      subtitleColor: subtitleColor,
                                      iconColor: tealColor,
                                      borderColor: borderColor,
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _schoolCode.isEmpty
                              ? _SkeletonStatCard(
                                  icon: Icons.group,
                                  label: 'Total Staff',
                                  cardColor: cardColor,
                                  subtitleColor: subtitleColor,
                                  iconColor: tealColor,
                                  borderColor: borderColor,
                                )
                              : StreamBuilder<int>(
                                  stream: _getStaffCountStream(_schoolCode),
                                  builder: (context, snapshot) {
                                    // Show skeleton while loading
                                    if (snapshot.connectionState ==
                                            ConnectionState.waiting ||
                                        !snapshot.hasData) {
                                      return _SkeletonStatCard(
                                        icon: Icons.group,
                                        label: 'Total Staff',
                                        cardColor: cardColor,
                                        subtitleColor: subtitleColor,
                                        iconColor: tealColor,
                                        borderColor: borderColor,
                                      );
                                    }

                                    final count = snapshot.data ?? 0;
                                    return _StatCard(
                                      icon: Icons.group,
                                      label: 'Total Staff',
                                      value: _formatCount(count),
                                      cardColor: cardColor,
                                      textColor: textColor,
                                      subtitleColor: subtitleColor,
                                      iconColor: tealColor,
                                      borderColor: borderColor,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Attendance History Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const AttendanceHistoryScreen(),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF146D7A).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFF146D7A).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.event_note,
                                color: Color(0xFF146D7A),
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Attendance History',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Select date to view attendance',
                                    style: TextStyle(
                                      color: subtitleColor,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: subtitleColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Broadcast Message Card
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    child: _QuickActionCard(
                      cardColor: cardColor,
                      textColor: textColor,
                      subtitleColor: subtitleColor,
                      tealColor: tealColor,
                      iconBgColor: progressBgColor,
                      borderColor: borderColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Student Attendance Card with Real Data
                  _schoolCode.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _SkeletonAttendanceCard(
                            cardColor: cardColor,
                            subtitleColor: subtitleColor,
                          ),
                        )
                      : StreamBuilder<Map<String, dynamic>>(
                          stream: _getStudentAttendanceStream(_schoolCode),
                          builder: (context, snapshot) {
                            // Show skeleton while loading
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting ||
                                !snapshot.hasData) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: _SkeletonAttendanceCard(
                                  cardColor: cardColor,
                                  subtitleColor: subtitleColor,
                                ),
                              );
                            }

                            final data =
                                snapshot.data ??
                                {'present': 0, 'total': 0, 'percent': 0.0};
                            final presentCount = data['present'] as int;
                            final totalCount = data['total'] as int;
                            final attendancePercent = data['percent'] as double;

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: AttendanceSpeedometerGauge(
                                attendancePercent: attendancePercent,
                                presentCount: presentCount,
                                totalCount: totalCount,
                                cardColor: cardColor,
                                textColor: textColor,
                                subtitleColor: subtitleColor,
                                title: 'Student Attendance (Today)',
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Build announcements section with real Firestore data
  Widget _buildAnnouncementsSection() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final currentUserId = currentUser?.uid;
    final instituteId = currentUser?.instituteId ?? '';

    // Get theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    // Show skeleton if no instituteId yet
    if (instituteId.isEmpty) {
      return SizedBox(
        height: 110,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          scrollDirection: Axis.horizontal,
          itemCount: 5,
          itemBuilder: (_, __) => _buildShimmerCircle(),
          separatorBuilder: (_, __) => const SizedBox(width: 12),
        ),
      );
    }

    return SizedBox(
      height: 110,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('institute_announcements')
            .where('instituteId', isEqualTo: instituteId)
            .snapshots(),
        builder: (context, snapshot) {
          // Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (_, __) => _buildShimmerCircle(),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
            );
          }

          // Error state
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Error loading announcements',
                  style: TextStyle(color: subtitleColor),
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // Convert docs to InstituteAnnouncementModel and filter valid ones
          final allAnnouncements =
              docs
                  .map((d) => InstituteAnnouncementModel.fromFirestore(d))
                  .where((a) => a.instituteId == instituteId)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          // DEBUG: Log announcements data
          print('📢 Institute Dashboard - Announcements Debug:');
          print('  Total announcements: ${allAnnouncements.length}');
          for (var ann in allAnnouncements) {
            print('  - ID: ${ann.id}');
            print('    Principal: ${ann.principalName}');
            print('    hasImage: ${ann.hasImage}');
            print('    hasText: ${ann.hasText}');
            print('    text: "${ann.text}"');
            print('    imageUrl: ${ann.imageUrl}');
            print('    imageCaptions: ${ann.imageCaptions}');
            if (ann.imageCaptions != null) {
              print('    imageCaptions count: ${ann.imageCaptions!.length}');
            }
          }

          // Segregate: My announcements vs Other Principals
          final myAnnouncements = allAnnouncements
              .where((a) => a.principalId == currentUserId)
              .toList();

          // Group other principals' announcements by principalId
          final otherPrincipalsMap =
              <String, List<InstituteAnnouncementModel>>{};
          for (final announcement in allAnnouncements) {
            if (announcement.principalId != currentUserId) {
              otherPrincipalsMap
                  .putIfAbsent(announcement.principalId, () => [])
                  .add(announcement);
            }
          }

          // Sort each principal's announcements by timestamp
          otherPrincipalsMap.forEach((key, value) {
            value.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          });

          // Create list of other principals (sorted by latest post)
          final otherPrincipals = otherPrincipalsMap.entries.toList()
            ..sort(
              (a, b) =>
                  b.value.first.createdAt.compareTo(a.value.first.createdAt),
            );

          // Build horizontal list: My Announcement + Other Principals
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            itemCount: 2 + otherPrincipals.length,
            addRepaintBoundaries: true,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                // My Announcement (always first)
                return _buildMyAnnouncementAvatar(myAnnouncements, currentUser);
              } else if (index == 1) {
                // Teacher Announcements (second)
                return _buildTeacherAnnouncementsAvatar(instituteId);
              } else {
                // Other Principals
                final principalEntry = otherPrincipals[index - 2];
                final announcements = principalEntry.value;
                final latestAnnouncement = announcements.first;
                return _buildOtherPrincipalAvatar(
                  latestAnnouncement,
                  announcements,
                );
              }
            },
          );
        },
      ),
    );
  }

  // Shimmer loading circle
  Widget _buildShimmerCircle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cardColor.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 40,
          height: 10,
          decoration: BoxDecoration(
            color: cardColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  // My Announcement Avatar (First item with + button)
  Widget _buildMyAnnouncementAvatar(
    List<InstituteAnnouncementModel> myAnnouncements,
    dynamic currentUser,
  ) {
    final hasAnnouncement = myAnnouncements.isNotEmpty;
    final latestAnnouncement = hasAnnouncement ? myAnnouncements.first : null;

    // Get theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    const tealColor = Color(0xFF146D7A);

    return GestureDetector(
      onTap: () {
        if (hasAnnouncement) {
          // Open announcement viewer with delete option
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrincipalAnnouncementViewer(
                announcements: myAnnouncements,
                initialIndex: 0,
                currentUserId: currentUser?.uid ?? '',
              ),
            ),
          ).then((_) {
            // Refresh dashboard after returning from viewer
            if (mounted) {
              setState(() {});
            }
          });
        } else {
          _openAnnouncementTargetSelection();
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
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasAnnouncement ? tealColor : cardColor,
                  border: Border.all(
                    color: hasAnnouncement ? tealColor : tealColor,
                    width: 2,
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAnnouncement
                        ? (latestAnnouncement!.hasImage
                              ? Colors.transparent
                              : tealColor)
                        : cardColor,
                  ),
                  child: ClipOval(
                    child: hasAnnouncement && latestAnnouncement!.hasImage
                        ? _buildCachedAvatarImage(
                            latestAnnouncement.imageUrl!,
                            'announcement_${latestAnnouncement.id}.jpg',
                            currentUser?.name ?? 'Principal',
                          )
                        : _buildDefaultAvatar(currentUser?.name ?? 'Principal'),
                  ),
                ),
              ),

              // Add (+) Icon Overlay (Small, bottom-right)
              Positioned(
                right: -2,
                bottom: -2,
                child: GestureDetector(
                  onTap: _openAnnouncementTargetSelection,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tealColor,
                      border: Border.all(color: bgColor, width: 2.5),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Label
          SizedBox(
            width: 70,
            child: Text(
              'Add',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: subtitleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build Teacher Announcements Avatar
  Widget _buildTeacherAnnouncementsAvatar(String instituteId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    const purpleColor = Color(0xFF7A5CFF);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('class_highlights')
          .where('instituteId', isEqualTo: instituteId)
          .where('expiresAt', isGreaterThan: Timestamp.now())
          .snapshots(),
      builder: (context, snapshot) {
        final hasTeacherAnnouncements =
            snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return GestureDetector(
          onTap: () {
            if (hasTeacherAnnouncements) {
              // Navigate to teacher announcements view
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Teacher announcements coming soon'),
                ),
              );
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: purpleColor, width: 2),
                  color: cardColor,
                ),
                child: const Icon(Icons.school, color: purpleColor, size: 28),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 68,
                child: Text(
                  'Teachers',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: subtitleColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDefaultAvatar(String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
    );
  }

  // Other Principal Avatar
  Widget _buildOtherPrincipalAvatar(
    InstituteAnnouncementModel latestAnnouncement,
    List<InstituteAnnouncementModel> allAnnouncements,
  ) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUser?.uid ?? '';

    // Check if any of this principal's announcements are unviewed
    final hasUnviewed = allAnnouncements.any(
      (a) => !_hasBeenViewedSync(a.id, currentUserId),
    );

    // Get theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    const tealColor = Color(0xFF146D7A);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _openOtherPrincipalAnnouncements(allAnnouncements),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar with simple border
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasUnviewed ? const Color(0xFFF27F0D) : Colors.grey,
                border: Border.all(
                  color: hasUnviewed ? const Color(0xFFF27F0D) : Colors.grey,
                  width: 3,
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: latestAnnouncement.hasImage
                      ? Colors.transparent
                      : tealColor,
                ),
                child: ClipOval(
                  child: latestAnnouncement.hasImage
                      ? Image.network(
                          latestAnnouncement.imageUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                          cacheHeight: 200,
                          errorBuilder: (_, __, ___) => _buildPrincipalInitial(
                            latestAnnouncement.principalName,
                          ),
                        )
                      : _buildPrincipalInitial(
                          latestAnnouncement.principalName,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            // Principal Name
            SizedBox(
              width: 70,
              child: Text(
                latestAnnouncement.principalName.split(' ').first,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subtitleColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrincipalInitial(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
    );
  }

  // Synchronous check for viewed status (simplified for now)
  bool _hasBeenViewedSync(String announcementId, String userId) {
    if (userId.isEmpty) return false;
    return _viewedAnnouncementIds.contains(announcementId);
  }

  Future<void> _markAnnouncementsViewed(
    List<InstituteAnnouncementModel> announcements,
    String userId,
  ) async {
    await Future.wait(
      announcements.map(
        (a) => _announcementService.markAnnouncementAsViewed(a.id, userId),
      ),
    );

    if (mounted) {
      setState(() {
        _viewedAnnouncementIds.addAll(announcements.map((a) => a.id));
      });
    }
  }

  Future<void> _openOtherPrincipalAnnouncements(
    List<InstituteAnnouncementModel> announcements,
  ) async {
    if (announcements.isEmpty) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.currentUser?.uid ?? '';
    if (userId.isEmpty) return;

    await _markAnnouncementsViewed(announcements, userId);

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrincipalAnnouncementViewer(
          announcements: announcements,
          currentUserId: userId,
          allowDelete: false,
        ),
      ),
    );
  }

  void _openAnnouncementTargetSelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InstituteAnnouncementTargetScreen(),
      ),
    );
  }

  /// Build cached avatar image - downloads and caches announcement images
  Widget _buildCachedAvatarImage(
    String imageUrl,
    String fileName,
    String fallbackName,
  ) {
    const tealColor = Color(0xFF146D7A);

    return FutureBuilder<String?>(
      future: _getAnnouncementImagePath(imageUrl, fileName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show simple placeholder while checking cache/downloading
          return Container(
            color: tealColor.withOpacity(0.3),
            child: Center(child: _buildDefaultAvatar(fallbackName)),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          // Show fallback avatar if download failed
          return _buildDefaultAvatar(fallbackName);
        }

        // Show cached image with size constraints
        return Image.file(
          File(snapshot.data!),
          fit: BoxFit.cover,
          cacheWidth: 200,
          cacheHeight: 200,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar(fallbackName);
          },
        );
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.textColor});

  final String title;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.teal,
    required this.textColor,
    required this.bgColor,
  });

  final Color teal;
  final Color textColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Good Morning, Principal',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.cardColor,
    required this.textColor,
    required this.subtitleColor,
    required this.iconColor,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color cardColor;
  final Color textColor;
  final Color subtitleColor;
  final Color iconColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: subtitleColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// Yesterday Attendance Card Widget
class _YesterdayAttendanceCard extends StatefulWidget {
  const _YesterdayAttendanceCard({
    required this.cardColor,
    required this.textColor,
    required this.subtitleColor,
  });

  final Color cardColor;
  final Color textColor;
  final Color subtitleColor;

  @override
  State<_YesterdayAttendanceCard> createState() =>
      _YesterdayAttendanceCardState();
}

class _YesterdayAttendanceCardState extends State<_YesterdayAttendanceCard> {
  final AttendanceService _attendanceService = AttendanceService();
  late Future<dynamic> _attendanceFuture;

  @override
  void initState() {
    super.initState();
    print('✅ DEBUG: _YesterdayAttendanceCard initState called');
    _loadAttendance();
  }

  void _loadAttendance() {
    final yesterday = _getYesterdayDate();
    print('✅ DEBUG: Loading attendance for date: $yesterday');
    _attendanceFuture = _attendanceService.getAttendanceSummary(yesterday);
  }

  DateTime _getYesterdayDate() {
    final now = DateTime.now();
    return now.subtract(const Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    print('✅ DEBUG: Building Yesterday Attendance Card Widget');
    final yesterday = _getYesterdayDate();

    return FutureBuilder(
      future: _attendanceFuture,
      builder: (context, snapshot) {
        print(
          '✅ DEBUG: FutureBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}',
        );
        if (snapshot.hasError) {
          print('❌ DEBUG: Error in snapshot: ${snapshot.error}');
        }
        // Always show the card, just change the content based on state
        return InkWell(
          onTap: snapshot.hasData
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          AttendanceDetailsPage(date: yesterday),
                    ),
                  );
                }
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF146D7A).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: snapshot.connectionState == ConnectionState.waiting
                ? _buildLoadingState()
                : snapshot.hasError || !snapshot.hasData
                ? _buildErrorState()
                : _buildContentState(snapshot.data!),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    // Debug: Print to console
    print('DEBUG: Yesterday Attendance Card - Loading State');
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF146D7A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF146D7A)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yesterday Attendance',
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading...',
                style: TextStyle(color: widget.subtitleColor, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    // Debug: Print to console
    print('DEBUG: Yesterday Attendance Card - Error State');
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF146D7A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.calendar_today,
            color: Color(0xFF146D7A),
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Yesterday Attendance',
                style: TextStyle(
                  color: widget.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No data available',
                style: TextStyle(color: widget.subtitleColor, fontSize: 13),
              ),
            ],
          ),
        ),
        Icon(Icons.arrow_forward_ios, size: 14, color: widget.subtitleColor),
      ],
    );
  }

  Widget _buildContentState(dynamic summary) {
    // Debug: Print to console
    print(
      'DEBUG: Yesterday Attendance Card - Content State: ${summary.percentage}%',
    );
    final statusColor = summary.statusColor;

    return Row(
      children: [
        // Icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF146D7A).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.calendar_today,
            color: Color(0xFF146D7A),
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Yesterday Attendance',
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${summary.percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.people, size: 16, color: widget.subtitleColor),
                  const SizedBox(width: 6),
                  Text(
                    '${summary.totalPresent}/${summary.totalStudents} students present',
                    style: TextStyle(color: widget.subtitleColor, fontSize: 13),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: widget.subtitleColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.cardColor,
    required this.textColor,
    required this.subtitleColor,
    required this.tealColor,
    required this.iconBgColor,
    required this.borderColor,
  });

  final Color cardColor;
  final Color textColor;
  final Color subtitleColor;
  final Color tealColor;
  final Color iconBgColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final instituteId = authProvider.currentUser?.instituteId ?? '';
        final instituteName = authProvider.currentUser?.name ?? 'Institute';

        if (instituteId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StaffRoomChatPage(
                instituteId: instituteId,
                instituteName: instituteName,
                isTeacher: false, // Principal uses teal color
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
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
              child: Icon(Icons.business, color: tealColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Staff Room',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chat with all teachers',
                    style: TextStyle(color: subtitleColor, fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: subtitleColor, size: 24),
          ],
        ),
      ),
    );
  }
}

/// Skeleton loader for stat cards
class _SkeletonStatCard extends StatefulWidget {
  const _SkeletonStatCard({
    required this.icon,
    required this.label,
    required this.cardColor,
    required this.subtitleColor,
    required this.iconColor,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final Color cardColor;
  final Color subtitleColor;
  final Color iconColor;
  final Color borderColor;

  @override
  State<_SkeletonStatCard> createState() => _SkeletonStatCardState();
}

class _SkeletonStatCardState extends State<_SkeletonStatCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, color: widget.iconColor),
          const SizedBox(height: 8),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.subtitleColor,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Container(
                width: 80,
                height: 28,
                decoration: BoxDecoration(
                  color: widget.subtitleColor.withOpacity(_animation.value),
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Skeleton loader for attendance card
class _SkeletonAttendanceCard extends StatefulWidget {
  const _SkeletonAttendanceCard({
    required this.cardColor,
    required this.subtitleColor,
  });

  final Color cardColor;
  final Color subtitleColor;

  @override
  State<_SkeletonAttendanceCard> createState() =>
      _SkeletonAttendanceCardState();
}

class _SkeletonAttendanceCardState extends State<_SkeletonAttendanceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        children: [
          // Title skeleton
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Container(
                width: 160,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.subtitleColor.withOpacity(_animation.value),
                  borderRadius: BorderRadius.circular(9),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          // Gauge skeleton (circular)
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: widget.subtitleColor.withOpacity(
                    _animation.value * 0.4,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: widget.cardColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 40,
                        decoration: BoxDecoration(
                          color: widget.subtitleColor.withOpacity(
                            _animation.value,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          // Count text skeleton
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Container(
                width: 60,
                height: 16,
                decoration: BoxDecoration(
                  color: widget.subtitleColor.withOpacity(_animation.value),
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Status badge skeleton
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Container(
                width: 100,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.subtitleColor.withOpacity(
                    _animation.value * 0.3,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
