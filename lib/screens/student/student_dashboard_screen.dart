import 'package:flutter/material.dart' hide Badge;
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/student_provider.dart';
import '../../providers/daily_challenge_provider.dart';
import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../models/status_model.dart';
import '../../models/institute_announcement_model.dart';
import '../../models/student_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/parent_service.dart';
import '../../utils/cache_manager.dart';
import '../../services/badge_service.dart';
import '../../badges/badge_model.dart';
import '../../badges/badge_master.dart';
import 'daily_challenge_screen.dart';
import 'student_profile_screen.dart';
import 'badge_gallery_screen.dart';
import '../ai/ai_chat_page.dart';
import '../common/announcement_pageview_screen.dart';
import 'dart:math' as math;

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  // Theme helpers
  Color get _primary => const Color(0xFFF2800D);
  Color _surface(BuildContext context) => Theme.of(context).cardColor;
  Color _onSurface(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  Color _muted(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.65) ??
      Colors.grey;

  @override
  void initState() {
    super.initState();
    print('🏠 StudentDashboard: initState called');
    // Pre-load cached data synchronously during initState
    // This ensures student data is available for immediate display
    _preloadCachedData();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      print('🏠 StudentDashboard: Post-frame callback triggered');
      print('🏠 StudentDashboard: Calling _loadDashboardData()');
      await _loadDashboardData();
    });
  }

  void _preloadCachedData() {
    print('🏠 _preloadCachedData: Attempting to load cached student data...');
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );

    final userId =
        authProvider.currentUser?.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      // Load cached data asynchronously and update provider
      CacheManager.getStudentDataCache(studentId: userId)
          .then((cachedStudent) {
            if (cachedStudent != null && mounted) {
              print(
                '🏠 _preloadCachedData: Found cached student, updating provider',
              );
              // Directly update the provider's student to show cached data immediately
              studentProvider.setCurrentStudentFromCache(cachedStudent);
            }
          })
          .catchError((e) {
            print('🏠 _preloadCachedData: Cache load error (non-fatal): $e');
          });
    }
  }

  Future<void> _loadDashboardData() async {
    print('🏠 _loadDashboardData: Starting...');
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    final dailyChallengeProvider = Provider.of<DailyChallengeProvider>(
      context,
      listen: false,
    );

    print(
      '🏠 _loadDashboardData: Auth status - currentUser=${authProvider.currentUser?.uid}, isLoading=${authProvider.isLoading}',
    );
    // Ensure auth is initialized before proceeding
    if (authProvider.currentUser == null && !authProvider.isLoading) {
      print('🏠 _loadDashboardData: Auth not initialized, initializing now...');
      await authProvider.initializeAuth();
    }
    // Resolve UID robustly: prefer provider uid, else FirebaseAuth
    String? userId = authProvider.currentUser?.uid;
    userId ??= FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      print(
        '❌ _loadDashboardData: No authenticated user found (provider and Firebase)',
      );
      return;
    }

    final resolvedUserId = userId;
    print('✅ _loadDashboardData: Loading dashboard for user: $userId');

    try {
      await FirestoreService().processEndedTests();
    } catch (e) {
      print('⚠️ Error processing ended tests: $e');
    }

    // CRITICAL: Initialize daily challenge BEFORE loading student data
    // This ensures challenge state is ready when dashboard renders
    print('🎯 Initializing daily challenge for user: $resolvedUserId');
    await dailyChallengeProvider.initialize(resolvedUserId);
    print(
      '✅ Daily challenge initialized. Has answered: ${dailyChallengeProvider.hasAnsweredToday(resolvedUserId)}',
    );

    // Load student data (with cache integration)
    await studentProvider.loadDashboardData(resolvedUserId);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        final student = studentProvider.currentStudent;
        final authUser = Provider.of<app_auth.AuthProvider>(
          context,
        ).currentUser;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: const Color(0xFFF2800D),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Custom Header
                SliverToBoxAdapter(child: _buildHeader(student, authUser)),

                // Main Content
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Announcements Section (above points)
                      if (student != null) _buildAnnouncementsSection(student),

                      const SizedBox(height: 16),

                      // Points Card
                      _buildPointsCard(student),

                      const SizedBox(height: 24),

                      // Daily Challenge
                      if (student != null) _buildDailyChallengeCard(student),

                      const SizedBox(height: 24),

                      // Assigned Tests
                      _buildAssignedTestsSection(student),

                      const SizedBox(height: 24),

                      // Performance
                      _buildPerformanceSection(student),

                      const SizedBox(height: 24),

                      // Attendance
                      _buildAttendanceSection(student),

                      const SizedBox(height: 24),

                      // Badges
                      _buildBadgesSection(student),

                      const SizedBox(height: 100),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AiChatPage()),
              );
            },
            backgroundColor: _primary,
            elevation: 4,
            child: const Icon(Icons.smart_toy, color: Colors.white),
          ),
        );
      },
    );
  }

  // Header with profile picture and streak
  Widget _buildHeader(StudentModel? student, authUser) {
    String firstName = 'Student';

    try {
      if (student?.name != null && student!.name.isNotEmpty) {
        final nameParts = student.name.trim().split(' ');
        firstName = nameParts.isNotEmpty ? nameParts.first : 'Student';
      } else if (authUser?.email != null && authUser.email.isNotEmpty) {
        final emailParts = authUser.email.split('@');
        firstName = emailParts.isNotEmpty ? emailParts.first : 'Student';
      }
    } catch (e) {
      debugPrint('Error parsing name: $e');
      firstName = 'Student';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          const SizedBox(height: 48),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi, $firstName 👋',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Here's your progress for today",
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? const Color(0xFFE5E5E5)
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildStreakBadge(),
                    const SizedBox(width: 10),
                    _buildProfileIcon(),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildStreakBadge() {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        final student = studentProvider.currentStudent;
        final streakDays = student?.streak ?? 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department,
                color: Color(0xFFF2800D),
                size: 24,
              ),
              const SizedBox(width: 6),
              Text(
                '$streakDays',
                style: const TextStyle(
                  color: Color(0xFFF2800D),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileIcon() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const StudentProfileScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : _surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Icon(
          Icons.person_outline,
          color: isDark ? Colors.white : Colors.black87,
          size: 24,
        ),
      ),
    );
  }

  // Announcements Section (WhatsApp-style)
  Widget _buildAnnouncementsSection(StudentModel student) {
    final authProvider = Provider.of<app_auth.AuthProvider>(
      context,
      listen: false,
    );
    final currentUserId = authProvider.currentUser?.uid ?? '';
    final schoolIdentifier =
        student.schoolCode ?? student.schoolId ?? student.schoolName ?? '';

    if (schoolIdentifier.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<Map<String, String>>(
      future: _parseStudentInfo(student),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final userStandard = snapshot.data!['standard'] ?? '';
        final userSection = snapshot.data!['section'] ?? '';

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _combineAnnouncementStreams(schoolIdentifier),
          builder: (context, announcementSnapshot) {
            if (announcementSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const SizedBox.shrink();
            }

            final combinedDocs = announcementSnapshot.data ?? [];
            final announcements = <Map<String, dynamic>>[];

            // Process teacher announcements
            for (final doc in combinedDocs) {
              if (doc['type'] == 'teacher') {
                final status = StatusModel.fromFirestore(
                  doc['snapshot'] as DocumentSnapshot,
                );
                if (status.teacherId.isNotEmpty &&
                    status.isVisibleTo(
                      userStandard: userStandard,
                      userSection: userSection,
                    )) {
                  announcements.add({'type': 'teacher', 'data': status});
                }
              } else if (doc['type'] == 'principal') {
                final announcement = InstituteAnnouncementModel.fromFirestore(
                  doc['snapshot'] as DocumentSnapshot,
                );
                // Only show school-wide or matching standard announcements
                if (announcement.audienceType == 'school' ||
                    (announcement.audienceType == 'standard' &&
                        announcement.standards.contains(userStandard))) {
                  announcements.add({
                    'type': 'principal',
                    'data': announcement,
                  });
                }
              }
            }

            if (announcements.isEmpty) return const SizedBox.shrink();

            return _buildAnnouncementsRow(announcements, currentUserId);
          },
        );
      },
    );
  }

  Widget _buildAnnouncementsRow(
    List<Map<String, dynamic>> announcements,
    String currentUserId,
  ) {
    // Group announcements by creator
    final Map<String, List<Map<String, dynamic>>> groupedByCreator = {};
    for (final announcement in announcements) {
      final type = announcement['type'];
      final data = announcement['data'];
      final creatorId = type == 'teacher'
          ? (data as StatusModel).teacherId
          : (data as InstituteAnnouncementModel).principalId;

      groupedByCreator.putIfAbsent(creatorId, () => []).add(announcement);
    }

    final creatorGroups = groupedByCreator.entries.map((entry) {
      final list = entry.value;
      list.sort((a, b) {
        final aData = a['data'];
        final bData = b['data'];
        final aTime = a['type'] == 'teacher'
            ? (aData as StatusModel).createdAt
            : (aData as InstituteAnnouncementModel).createdAt;
        final bTime = b['type'] == 'teacher'
            ? (bData as StatusModel).createdAt
            : (bData as InstituteAnnouncementModel).createdAt;
        return bTime.compareTo(aTime);
      });
      return list;
    }).toList();

    creatorGroups.sort((a, b) {
      final aData = a.first['data'];
      final bData = b.first['data'];
      final aTime = a.first['type'] == 'teacher'
          ? (aData as StatusModel).createdAt
          : (aData as InstituteAnnouncementModel).createdAt;
      final bTime = b.first['type'] == 'teacher'
          ? (bData as StatusModel).createdAt
          : (bData as InstituteAnnouncementModel).createdAt;
      return bTime.compareTo(aTime);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: Color(0xFFF2800D), size: 20),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  return Text(
                    '📢 Announcements',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 8),
            scrollDirection: Axis.horizontal,
            itemCount: creatorGroups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final creatorAnnouncements = creatorGroups[index];
              final latest = creatorAnnouncements.first;
              final latestData = latest['data'];
              final latestType = latest['type'];

              if (latestType == 'teacher') {
                // For teacher announcements, check viewedBy array
                final hasUnread = creatorAnnouncements.any(
                  (a) => !(a['data'] as StatusModel).viewedBy.contains(
                    currentUserId,
                  ),
                );

                final name = (latestData as StatusModel).teacherName;

                return _buildAnnouncementAvatar(name, hasUnread, () {
                  _openCrossPersonAnnouncementViewer(
                    creatorGroups,
                    index,
                    currentUserId,
                  );
                }, count: creatorAnnouncements.length);
              } else {
                // For principal announcements, use StreamBuilder for real-time updates
                final principalAnnouncements = creatorAnnouncements
                    .where((a) => a['type'] == 'principal')
                    .map((a) => a['data'] as InstituteAnnouncementModel)
                    .toList();

                return StreamBuilder<List<bool>>(
                  stream: _streamPrincipalAnnouncementsViewStatus(
                    principalAnnouncements,
                    currentUserId,
                  ),
                  builder: (context, snapshot) {
                    final viewStatuses = snapshot.data ?? [];
                    final hasUnread =
                        viewStatuses.isEmpty ||
                        viewStatuses.any((isViewed) => !isViewed);

                    debugPrint(
                      '🎨 STUDENT: Building avatar - Statuses: $viewStatuses, hasUnread: $hasUnread',
                    );

                    return _buildAnnouncementAvatar('Principal', hasUnread, () {
                      _openCrossPersonAnnouncementViewer(
                        creatorGroups,
                        index,
                        currentUserId,
                      );
                    }, count: creatorAnnouncements.length);
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementAvatar(
    String name,
    bool isUnread,
    VoidCallback onTap, {
    int count = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isUnread
                      ? const LinearGradient(
                          colors: [Color(0xFFFFA726), Color(0xFFF2800D)],
                        )
                      : null,
                  border: !isUnread
                      ? Border.all(
                          color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
                          width: 1,
                        )
                      : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _surface(context),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFFFF5EB),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'A',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF2800D),
                      ),
                    ),
                  ),
                ),
              ),
              if (count > 1)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2800D),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            child: Text(
              name.isNotEmpty ? name.split(' ').first : 'Announcement',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                color: isUnread
                    ? const Color(0xFFF2800D)
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Open cross-person announcement viewer - chains through all creators
  /// starting from the tapped one
  Future<void> _openCrossPersonAnnouncementViewer(
    List<List<Map<String, dynamic>>> allCreatorGroups,
    int tappedGroupIndex,
    String currentUserId,
  ) async {
    // Flatten all announcements starting from tapped group
    final flattenedAnnouncements = <Map<String, dynamic>>[];

    // Add tapped group first, then all subsequent groups
    for (int i = tappedGroupIndex; i < allCreatorGroups.length; i++) {
      flattenedAnnouncements.addAll(allCreatorGroups[i]);
    }

    // Convert to PageView format with metadata for tracking
    final announcements = flattenedAnnouncements.map((item) {
      final type = item['type'] as String;
      final data = item['data'];

      if (type == 'teacher') {
        final status = data as StatusModel;
        return {
          'role': 'teacher',
          'title': status.text,
          'subtitle': '',
          'postedByLabel': 'Posted by ${status.teacherName}',
          'avatarUrl': status.imageUrl,
          'postedAt': status.createdAt,
          'expiresAt': status.createdAt.add(const Duration(hours: 24)),
          '_originalData': item, // Keep reference for marking viewed
        };
      } else {
        final principal = data as InstituteAnnouncementModel;
        return {
          'role': 'principal',
          'title': principal.text,
          'subtitle': '',
          'postedByLabel': 'Posted by ${principal.principalName}',
          'avatarUrl': null,
          'postedAt': principal.createdAt,
          'expiresAt': principal.expiresAt,
          '_originalData': item, // Keep reference for marking viewed
        };
      }
    }).toList();

    // Open viewer and await completion
    await openAnnouncementPageView(
      context,
      announcements: announcements,
      initialIndex: 0,
      onAnnouncementViewed: (index) {
        // Mark as viewed (no setState during build)
        if (index < announcements.length) {
          final announcement = announcements[index];
          final originalData =
              announcement['_originalData'] as Map<String, dynamic>?;

          if (originalData != null) {
            final type = originalData['type'] as String;

            if (type == 'teacher') {
              final status = originalData['data'] as StatusModel;
              // Persist view state to Firestore
              FirebaseFirestore.instance
                  .collection('class_highlights')
                  .doc(status.id)
                  .update({
                    'viewedBy': FieldValue.arrayUnion([currentUserId]),
                  })
                  .catchError((e) {
                    debugPrint('Error marking teacher status viewed: $e');
                  });
            } else if (type == 'principal') {
              final principalAnnouncement =
                  originalData['data'] as InstituteAnnouncementModel;
              debugPrint(
                '🔵 STUDENT: Marking principal announcement as viewed',
              );
              debugPrint('   Announcement ID: ${principalAnnouncement.id}');
              debugPrint('   User ID: $currentUserId');
              debugPrint('   Title: ${principalAnnouncement.text}');
              _markPrincipalAnnouncementAsViewed(
                principalAnnouncement.id,
                currentUserId,
              );
            }
          }
        }
      },
    );

    // StreamBuilder will automatically update the UI, no manual refresh needed
  }

  /// Mark a principal announcement as viewed by updating Firestore
  Future<void> _markPrincipalAnnouncementAsViewed(
    String announcementId,
    String userId,
  ) async {
    try {
      debugPrint('🟢 STUDENT: Writing view to Firestore...');
      debugPrint(
        '   Path: institute_announcements/$announcementId/views/$userId',
      );

      // Add user to views subcollection (no instituteId check needed)
      await FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(announcementId)
          .collection('views')
          .doc(userId)
          .set({'viewedAt': FieldValue.serverTimestamp()});

      debugPrint('✅ STUDENT: Successfully wrote view to Firestore');

      // Verify write
      final verify = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(announcementId)
          .collection('views')
          .doc(userId)
          .get();
      debugPrint(
        '🔍 STUDENT: Verification - Document exists: ${verify.exists}',
      );

      // StreamBuilder will automatically update the UI
    } catch (e) {
      debugPrint('❌ STUDENT: Error in _markPrincipalAnnouncementAsViewed: $e');
    }
  }

  /// Stream real-time view status for principal announcements
  Stream<List<bool>> _streamPrincipalAnnouncementsViewStatus(
    List<InstituteAnnouncementModel> announcements,
    String userId,
  ) {
    debugPrint(
      '🔄 STUDENT: Setting up stream for ${announcements.length} principal announcements',
    );
    for (var i = 0; i < announcements.length; i++) {
      debugPrint(
        '   [$i] ID: ${announcements[i].id}, Title: ${announcements[i].text}',
      );
    }

    if (announcements.isEmpty) {
      return Stream.value([]);
    }

    // For single announcement, simple stream
    if (announcements.length == 1) {
      debugPrint('📡 STUDENT: Using single announcement stream');
      return FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(announcements.first.id)
          .collection('views')
          .doc(userId)
          .snapshots()
          .map((doc) {
            debugPrint('📥 STUDENT: Stream update - Exists: ${doc.exists}');
            return [doc.exists];
          })
          .distinct(
            (prev, next) => prev[0] == next[0],
          ); // Prevent duplicate emissions
    }

    // For multiple announcements, use snapshot listener instead of polling
    debugPrint(
      '📡 STUDENT: Using snapshot listener for multiple announcements',
    );
    // Listen to the first announcement and check all when it changes
    return FirebaseFirestore.instance
        .collection('institute_announcements')
        .doc(announcements.first.id)
        .collection('views')
        .doc(userId)
        .snapshots()
        .asyncMap((_) async {
          final results = <bool>[];
          for (final announcement in announcements) {
            final doc = await FirebaseFirestore.instance
                .collection('institute_announcements')
                .doc(announcement.id)
                .collection('views')
                .doc(userId)
                .get();
            results.add(doc.exists);
          }
          debugPrint(
            '📥 STUDENT: Checked ${results.length} announcements - Results: $results',
          );
          return results;
        })
        .distinct((prev, next) {
          // Only emit if the results actually changed
          if (prev.length != next.length) return false;
          for (var i = 0; i < prev.length; i++) {
            if (prev[i] != next[i]) return false;
          }
          return true;
        });
  }

  /// Check if a principal announcement has been viewed by the current user
  // Combine announcements from both teachers and principals
  Stream<List<Map<String, dynamic>>> _combineAnnouncementStreams(
    String instituteId,
  ) async* {
    await for (final teacherSnapshot
        in FirebaseFirestore.instance
            .collection('class_highlights')
            .where('instituteId', isEqualTo: instituteId)
            .where('expiresAt', isGreaterThan: Timestamp.now())
            .snapshots()) {
      // Get principal announcements with expiry filter
      final now = Timestamp.now();
      final principalSnapshot = await FirebaseFirestore.instance
          .collection('institute_announcements')
          .where('instituteId', isEqualTo: instituteId)
          .where('expiresAt', isGreaterThan: now)
          .get();

      final combined = <Map<String, dynamic>>[];

      // Add teacher announcements
      for (final doc in teacherSnapshot.docs) {
        combined.add({'type': 'teacher', 'snapshot': doc});
      }

      // Add principal announcements (already filtered by expiry)
      for (final doc in principalSnapshot.docs) {
        combined.add({'type': 'principal', 'snapshot': doc});
      }

      yield combined;
    }
  }

  Future<Map<String, String>> _parseStudentInfo(StudentModel student) async {
    String userStandard = '';
    String userSection = '';

    if (student.section != null && student.section!.isNotEmpty) {
      userSection = student.section!.trim();
    }

    if (student.className != null && student.className!.isNotEmpty) {
      final className = student.className!;
      if (className.contains('-')) {
        final parts = className.split('-').map((e) => e.trim()).toList();
        if (parts.length == 2) {
          userStandard = parts[0].replaceAll(RegExp(r'[Gg]rade\s*'), '').trim();
          userSection = parts[1].trim();
        }
      } else if (className.toLowerCase().contains('grade')) {
        userStandard = className.replaceAll(RegExp(r'[Gg]rade\s*'), '').trim();
      } else {
        final match = RegExp(r'^(\d+)([A-Z])$').firstMatch(className);
        if (match != null) {
          userStandard = match.group(1) ?? '';
          userSection = match.group(2) ?? '';
        } else {
          userStandard = className.trim();
        }
      }
    }

    if (userSection.isEmpty && student.uid.isNotEmpty) {
      try {
        final studentDoc = await FirebaseFirestore.instance
            .collection('students')
            .doc(student.uid)
            .get();
        if (studentDoc.exists) {
          userSection =
              (studentDoc.data()?['section'] as String?)?.trim() ?? '';
        }
      } catch (e) {
        print('⚠️ Error fetching section: $e');
      }
    }

    return {'standard': userStandard, 'section': userSection};
  }

  // Points Card with circular progress
  Widget _buildPointsCard(StudentModel? student) {
    if (student == null) {
      return _buildEmptyPointsCard();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('student_rewards')
          .where('studentId', isEqualTo: student.uid)
          .snapshots(),
      builder: (context, rewardsSnapshot) {
        int studentPoints = 0;

        if (rewardsSnapshot.hasData) {
          for (final doc in rewardsSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null) {
              final points = data['pointsEarned'];
              if (points is int) {
                studentPoints += points;
              } else if (points is num) {
                studentPoints += points.toInt();
              }
            }
          }
        }

        // Get topper points from class
        return FutureBuilder<int>(
          future: _getTopperPoints(student),
          builder: (context, topperSnapshot) {
            final topperPoints = topperSnapshot.data ?? 0;
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
              decoration: BoxDecoration(
                color: _surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.4),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Circular Comparison Chart
                  _buildCircularComparison(studentPoints, topperPoints),
                  const SizedBox(height: 20),

                  // Points Info
                  Text(
                    'Your Points: $studentPoints',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Topper: $topperPoints pts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFFBBBBBB)
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCircularComparison(int studentPoints, int topperPoints) {
    // Calculate percentage
    double percentage = 0.0;
    if (topperPoints > 0) {
      percentage = (studentPoints / topperPoints).clamp(0.0, 1.0);
    } else if (studentPoints > 0) {
      percentage = 1.0;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: percentage),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutQuart,
      builder: (context, animatedValue, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Background circle
            SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(
                painter: _CircularComparisonPainter(
                  progress: animatedValue,
                  strokeWidth: 10,
                ),
              ),
            ),
            // Center content
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$studentPoints',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    shadows: isDark
                        ? [Shadow(color: Colors.white24, blurRadius: 8)]
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'POINTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFFBBBBBB)
                        : Colors.grey.shade600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<int> _getTopperPoints(StudentModel student) async {
    try {
      // OPTIMIZATION: Check cache first (5-minute expiration)
      // This reduces Firestore reads from 20-40 docs to 0 reads per dashboard load
      final cachedPoints = await CacheManager.getTopperPointsCache(
        schoolId: student.schoolId ?? '',
        className: student.className ?? '',
      );

      if (cachedPoints != null) {
        return cachedPoints; // ✅ Return cached value (no Firestore read needed)
      }

      // Cache miss or expired - fetch from Firestore
      debugPrint('🔍 Fetching topper points from Firestore (cache miss)');

      Query query = FirebaseFirestore.instance.collection('users');

      if (student.schoolId != null) {
        query = query.where('schoolId', isEqualTo: student.schoolId);
      }
      if (student.className != null) {
        query = query.where('className', isEqualTo: student.className);
      }

      query = query.where('role', isEqualTo: 'student');

      final snapshot = await query.get();
      debugPrint(
        '📊 Fetched ${snapshot.docs.length} students for topper calculation',
      );

      int maxPoints = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final points = data['rewardPoints'];
          if (points is int && points > maxPoints) {
            maxPoints = points;
          } else if (points is num && points.toInt() > maxPoints) {
            maxPoints = points.toInt();
          }
        }
      }

      // Cache the result for 5 minutes
      await CacheManager.cacheTopperPoints(
        schoolId: student.schoolId ?? '',
        className: student.className ?? '',
        points: maxPoints,
      );

      return maxPoints;
    } catch (e) {
      debugPrint('❌ Error getting topper points: $e');
      return 0;
    }
  }

  Widget _buildEmptyPointsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.35),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.stars, size: 52, color: _primary.withOpacity(0.35)),
          const SizedBox(height: 10),
          Text(
            'No points yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _onSurface(context).withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  // Daily Challenge Card
  Widget _buildDailyChallengeCard(StudentModel student) {
    return Consumer2<DailyChallengeProvider, StudentProvider>(
      builder: (context, dailyChallengeProvider, studentProvider, child) {
        final hasAnswered = dailyChallengeProvider.hasAnsweredToday(
          student.uid,
        );
        final result = dailyChallengeProvider.getTodayResult(student.uid);
        final isCorrect = result == 'correct';

        return GestureDetector(
          onTap: hasAnswered
              ? null
              : () async {
                  // Navigate to challenge screen
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DailyChallengeScreen(
                        studentId: student.uid,
                        studentEmail: student.email,
                      ),
                    ),
                  );
                  // Refresh state after returning from challenge
                  if (mounted) {
                    // Small delay to ensure database write has completed
                    await Future.delayed(const Duration(milliseconds: 300));
                    // Re-check if student answered today (provider will fetch fresh state)
                    await dailyChallengeProvider.initialize(student.uid);
                    // Also refresh student data to get updated streak
                    await studentProvider.refreshStudentStreak(student.uid);
                  }
                },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: hasAnswered
                  ? (isCorrect
                        ? const Color(0xFF4CAF50).withOpacity(0.08)
                        : const Color(0xFFEF5350).withOpacity(0.08))
                  : _surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasAnswered
                    ? (isCorrect
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFEF5350))
                    : Theme.of(context).dividerColor.withOpacity(0.35),
                width: hasAnswered ? 1.2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  hasAnswered
                      ? (isCorrect
                            ? 'Challenge Completed!'
                            : 'Challenge Attempted')
                      : 'Daily Challenge',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: hasAnswered
                        ? (isCorrect
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFEF5350))
                        : Theme.of(context).textTheme.bodyLarge?.color,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                // Subtitle
                Text(
                  hasAnswered
                      ? (isCorrect
                            ? 'You earned +5 points!'
                            : 'Try again tomorrow!')
                      : "Answer today's MCQ to earn points",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: hasAnswered
                        ? (isCorrect
                              ? const Color(0xFF4CAF50).withOpacity(0.7)
                              : const Color(0xFFEF5350).withOpacity(0.7))
                        : _muted(context),
                  ),
                ),
                // Button
                if (!hasAnswered) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _primary,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text(
                      'Take Challenge',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                // Status icon for completed
                if (hasAnswered) ...[
                  const SizedBox(height: 12),
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFEF5350),
                    size: 32,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // Assigned Tests Section
  Widget _buildAssignedTestsSection(StudentModel? student) {
    if (student == null) return const SizedBox.shrink();

    final resultsStream = FirestoreService().getTestResultsByStudent(
      student.uid,
    );

    return StreamBuilder<List<TestResultModel>>(
      stream: resultsStream,
      builder: (context, resultsSnap) {
        final completedTestIds = <String>{
          if (resultsSnap.hasData) ...resultsSnap.data!.map((r) => r.testId),
        };

        return StreamBuilder<List<TestModel>>(
          stream: FirestoreService().getAvailableTestsForStudent(
            student.uid,
            studentEmail: student.email,
          ),
          builder: (context, testsSnap) {
            if (resultsSnap.connectionState == ConnectionState.waiting ||
                testsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final tests = testsSnap.data ?? [];
            final now = DateTime.now();
            final liveTests = tests.where((t) {
              final inWindow =
                  !t.startDate.isAfter(now) && !t.endDate.isBefore(now);
              final notAttempted = !completedTestIds.contains(t.id);
              return inWindow && notAttempted;
            }).toList();

            if (liveTests.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Text(
                      'Assigned Test',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                        height: 1.2,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                ...liveTests.take(3).map((test) => _buildTestCard(test)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTestCard(TestModel test) {
    final now = DateTime.now();
    final isDueToday =
        test.endDate.year == now.year &&
        test.endDate.month == now.month &&
        test.endDate.day == now.day;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with Due Today badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  test.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.3,
                  ),
                ),
              ),
              if (isDueToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Due Today',
                    style: TextStyle(
                      color: Color(0xFFF2800D),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Due date
          Row(
            children: [
              Icon(
                Icons.access_time,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Due Today, ${_formatTime(test.endDate)}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Questions count
          Row(
            children: [
              Icon(
                Icons.article_outlined,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${test.questions.length} Questions',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Start Test Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(
                context,
                '/student-tests',
                arguments: test,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Start Test',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  // Performance Section
  Widget _buildPerformanceSection(StudentModel? student) {
    if (student == null) return const SizedBox.shrink();

    return StreamBuilder<List<TestResultModel>>(
      stream: FirestoreService().getTestResultsByStudent(student.uid),
      builder: (context, snapshot) {
        int testsTaken = 0;
        double avgScore = 0.0;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final results = snapshot.data!;
          testsTaken = results.length;
          double totalScore = 0.0;
          for (var result in results) {
            totalScore += result.score;
          }
          avgScore = testsTaken > 0 ? totalScore / testsTaken : 0.0;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Text(
                  'Performance',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.2,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _surface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withOpacity(0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Circular score
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 110,
                            height: 110,
                            child: CustomPaint(
                              painter: CircularProgressPainter(
                                progress: avgScore / 100,
                                strokeWidth: 9,
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${avgScore.toInt()}%',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : Colors.black87,
                                  shadows: isDark
                                      ? [
                                          Shadow(
                                            color: Colors.white24,
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              Text(
                                'Avg. Score',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Tests taken
                      Column(
                        children: [
                          Text(
                            '$testsTaken',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black87,
                              shadows: isDark
                                  ? [
                                      Shadow(
                                        color: Colors.white24,
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          Text(
                            'Tests Taken',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // Attendance Section
  Widget _buildAttendanceSection(StudentModel? student) {
    if (student == null) return const SizedBox.shrink();

    return FutureBuilder<Map<String, int>>(
      future: ParentService().getStudentAttendanceBreakdown(student.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;
        final presentDays = data['present'] ?? 0;
        final absentDays = data['absent'] ?? 0;
        final totalDays = presentDays + absentDays;

        final attendancePct = totalDays > 0
            ? (presentDays / totalDays * 100).clamp(0.0, 100.0)
            : 0.0;

        if (totalDays == 0) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _onSurface(context),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _surface(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Circular attendance
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CustomPaint(
                          painter: CircularProgressPainter(
                            progress: attendancePct / 100,
                            strokeWidth: 10,
                            color: const Color(0xFF4CAF50),
                            backgroundColor: const Color(
                              0xFFEF5350,
                            ).withOpacity(0.2),
                          ),
                        ),
                      ),
                      Text(
                        '${attendancePct.toInt()}%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _onSurface(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // Legend
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$presentDays Days Present',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _onSurface(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF5350).withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$absentDays Days Absent',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _onSurface(context).withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Badges Section
  Widget _buildBadgesSection(StudentModel? student) {
    if (student == null) return const SizedBox.shrink();

    print('🎯 Building badges section for student: ${student.uid}');

    return FutureBuilder<List<Badge>>(
      future: BadgeService().fetchEarnedBadges(student.uid),
      builder: (context, snapshot) {
        print('🎯 Badge FutureBuilder state: ${snapshot.connectionState}');

        if (snapshot.hasError) {
          print('❌ Badge fetch error: ${snapshot.error}');
        }

        final earnedBadges = snapshot.data ?? [];
        final earnedIds = earnedBadges.map((b) => b.id).toSet();

        print('🎯 Earned badges count: ${earnedBadges.length}');
        print('🎯 Earned badge IDs: $earnedIds');

        // Prioritize earned badges first, then fill with locked badges
        final displayBadges = <Badge>[];

        // Add earned badges first
        displayBadges.addAll(earnedBadges.take(6));

        // Fill remaining slots with unearned badges
        if (displayBadges.length < 6) {
          final unearnedBadges = badgeMasterList
              .where((badge) => !earnedIds.contains(badge.id))
              .take(6 - displayBadges.length);
          displayBadges.addAll(unearnedBadges);
        }

        print(
          '🎯 Displaying ${displayBadges.length} badges in dashboard (${earnedBadges.length} earned)',
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Badges Earned',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _onSurface(context),
                    height: 1.2,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BadgeGalleryScreen(studentId: student.uid),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Text(
                        'View All (${earnedBadges.length}/${badgeMasterList.length})',
                        style: const TextStyle(
                          color: Color(0xFFFF8800),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Color(0xFFFF8800),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Premium Badge Grid with staggered animations
            LayoutBuilder(
              builder: (context, constraints) {
                // Responsive grid: 3 columns on larger screens, 2 on small
                final crossAxisCount = constraints.maxWidth > 400 ? 3 : 2;
                final childAspectRatio = constraints.maxWidth > 400 ? 0.9 : 1.0;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: childAspectRatio,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: displayBadges.length,
                  itemBuilder: (context, index) {
                    final badge = displayBadges[index];
                    final isEarned = earnedIds.contains(badge.id);
                    // Staggered animation delay
                    final delay = Duration(milliseconds: 100 * index);
                    return _PremiumBadgeTile(
                      badge: badge,
                      isUnlocked: isEarned,
                      animationDelay: delay,
                      onTap: () => _showRotatingBadgeDialog(badge, isEarned),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showRotatingBadgeDialog(Badge badge, bool earned) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RotatingBadgeWidget(badge: badge, earned: earned),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    badge.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    badge.description,
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: earned ? const Color(0xFF28A745) : Colors.white12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      earned ? '✓ Earned' : '🔒 Locked',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Color(0xFFFF8800),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Premium Badge Tile with Elegant Glow and Animations
class _PremiumBadgeTile extends StatefulWidget {
  final Badge badge;
  final bool isUnlocked;
  final Duration animationDelay;
  final VoidCallback onTap;

  const _PremiumBadgeTile({
    required this.badge,
    required this.isUnlocked,
    required this.animationDelay,
    required this.onTap,
  });

  @override
  State<_PremiumBadgeTile> createState() => _PremiumBadgeTileState();
}

class _PremiumBadgeTileState extends State<_PremiumBadgeTile>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    // Shimmer animation for unlocked badges
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.isUnlocked) {
      _shimmerController.repeat();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        // Clamp opacity value to ensure it stays within valid range [0.0, 1.0]
        final clampedOpacity = value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: 0.85 + (0.15 * value),
          child: Opacity(opacity: clampedOpacity, child: child),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.identity()..scale(_isPressed ? 0.98 : 1.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.isUnlocked
                    ? (Theme.of(context).brightness == Brightness.dark
                          ? [const Color(0xFF1A1C1F), const Color(0xFF252729)]
                          : [Colors.white, const Color(0xFFFAFAFA)])
                    : (Theme.of(context).brightness == Brightness.dark
                          ? [
                              const Color(0xFF1A1C1F).withValues(alpha: 0.5),
                              const Color(0xFF1A1C1F).withValues(alpha: 0.3),
                            ]
                          : [
                              const Color(0xFFE0E0E0).withValues(alpha: 0.5),
                              const Color(0xFFE0E0E0).withValues(alpha: 0.3),
                            ]),
              ),
              border: Border.all(
                color: widget.isUnlocked
                    ? const Color(0xFFFF8800)
                    : (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF303236)
                          : const Color(0xFFD0D0D0)),
                width: widget.isUnlocked ? 2 : 1,
              ),
              boxShadow: [
                // Outer glow for unlocked badges
                if (widget.isUnlocked)
                  BoxShadow(
                    color: const Color(0xFFFFA726).withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                // Subtle shadow for depth
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
                // Inner shadow effect
                BoxShadow(
                  color: widget.isUnlocked
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: -4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  // Shimmer effect for unlocked badges
                  if (widget.isUnlocked)
                    AnimatedBuilder(
                      animation: _shimmerController,
                      builder: (context, child) {
                        return Positioned(
                          left:
                              -100 +
                              (MediaQuery.of(context).size.width *
                                  _shimmerController.value),
                          top: -50,
                          child: Container(
                            width: 100,
                            height: 200,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: 0.1),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  // Main content
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Badge emoji - centered
                        Center(
                          child: Text(
                            widget.badge.emoji,
                            style: TextStyle(
                              fontSize: 48,
                              color: widget.isUnlocked
                                  ? null
                                  : Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Badge title
                        Text(
                          widget.badge.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: widget.isUnlocked
                                ? (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : const Color(0xFF1A1C1F))
                                : (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white.withValues(alpha: 0.4)
                                      : Colors.black.withValues(alpha: 0.4)),
                            fontWeight: widget.isUnlocked
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Earned tick icon
                  if (widget.isUnlocked)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF28A745), Color(0xFF20C997)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF28A745,
                              ).withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),

                  // Locked overlay for locked badges
                  if (!widget.isUnlocked)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.lock_rounded,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Rotating Badge Widget with 3D effect
class _RotatingBadgeWidget extends StatefulWidget {
  final Badge badge;
  final bool earned;

  const _RotatingBadgeWidget({required this.badge, required this.earned});

  @override
  State<_RotatingBadgeWidget> createState() => _RotatingBadgeWidgetState();
}

class _RotatingBadgeWidgetState extends State<_RotatingBadgeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft glow behind badge
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                widget.earned
                    ? const Color(0x33FF8800)
                    : const Color(0x11FFFFFF),
                const Color(0x00000000),
              ],
            ),
          ),
        ),

        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final angle = _controller.value * 2 * math.pi;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle)
                ..scale(1 + 0.05 * math.sin(angle)),
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.earned
                        ? const Color(0xFFFF8800)
                        : Colors.white24,
                    width: 4,
                  ),
                  boxShadow: widget.earned
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFFFF8800,
                            ).withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    widget.badge.emoji,
                    style: TextStyle(
                      fontSize: 80,
                      color: widget.earned
                          ? null
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// Custom Circular Comparison Painter
class _CircularComparisonPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;

  _CircularComparisonPainter({required this.progress, this.strokeWidth = 14});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track (dark grey)
    final bgPaint = Paint()
      ..color = const Color(0xFF2E2E2E)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc (orange)
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFA726), Color(0xFFF2800D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularComparisonPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// Custom Circular Progress Painter
class CircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;

  CircularProgressPainter({
    required this.progress,
    this.strokeWidth = 12,
    this.color = const Color(0xFFF2800D),
    this.backgroundColor = const Color(0x1AFFFFFF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
