import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../providers/profile_dp_provider.dart';
import '../../services/parent_service.dart';
import '../../utils/cache_manager.dart';
import '../../widgets/stat_ring_card.dart';
import '../../widgets/profile_avatar_widget.dart';
import 'daily_challenge_screen.dart';
import 'student_profile_screen.dart';
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

  // Loading state (same as teacher dashboard)
  bool _isLoading = true;
  String? _error;

  // Cache topper future to avoid re-creating it on every StreamBuilder rebuild
  Future<int>? _topperPointsFuture;
  String? _cachedTopperStudentId;

  // Cache viewed status for immediate UI updates - key: announcementId, value: isViewed
  final Map<String, bool> _viewedCache = {};

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _preloadViewedStatus();
  }

  /// Preload all viewed statuses at startup for instant display
  /// Optimized: Direct query to institute_announcements instead of collectionGroup
  Future<void> _preloadViewedStatus() async {
    try {
      final authProvider = Provider.of<app_auth.AuthProvider>(
        context,
        listen: false,
      );
      final userId = authProvider.currentUser?.uid;

      if (userId == null) return;

      final studentProvider = Provider.of<StudentProvider>(
        context,
        listen: false,
      );
      final instituteId = studentProvider.currentStudent?.schoolId;

      if (instituteId == null) return;

      // Direct query to institute_announcements - much faster
      final announcementsSnapshot = await FirebaseFirestore.instance
          .collection('institutes')
          .doc(instituteId)
          .collection('institute_announcements')
          .get();

      // Check each announcement's views subcollection for this user
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

  Future<void> _loadDashboardData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

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

      // Ensure auth is initialized before proceeding
      if (authProvider.currentUser == null && !authProvider.isLoading) {
        await authProvider.initializeAuth();
      }

      // Resolve UID robustly: prefer provider uid, else FirebaseAuth
      String? userId = authProvider.currentUser?.uid;
      userId ??= FirebaseAuth.instance.currentUser?.uid;

      if (userId == null || userId.isEmpty) {
        setState(() {
          _error = 'No user logged in';
          _isLoading = false;
        });
        return;
      }

      final resolvedUserId = userId;

      // Initialise profile DP provider for real-time avatar updates
      if (mounted) {
        final studentName =
            Provider.of<StudentProvider>(
              context,
              listen: false,
            ).currentStudent?.name ??
            '';
        context.read<ProfileDPProvider>().initForUser(
          resolvedUserId,
          userName: studentName,
        );
      }

      // Force auth token propagation to Firestore SDK before creating any streams.
      // This prevents the "permission denied" race condition where Firestore streams
      // are created before the auth token has been picked up by the Firestore SDK.
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(false);
      } catch (_) {
        // Ignore token refresh errors — best effort
      }

      // Load cached student data instantly (synchronous from SharedPreferences)
      final cachedStudent = await CacheManager.getStudentDataCache(
        studentId: resolvedUserId,
      );

      if (cachedStudent != null) {
        // Has cache - show UI immediately with cached data
        studentProvider.setCurrentStudentFromCache(cachedStudent);
        setState(() {
          _isLoading = false;
        });

        // Refresh in background
        _loadBackgroundData(
          resolvedUserId,
          studentProvider,
          dailyChallengeProvider,
        );
      } else {
        // No cache - load fresh data while showing skeleton
        await studentProvider.loadDashboardData(resolvedUserId);
        setState(() {
          _isLoading = false;
        });

        // Load other background data
        _loadBackgroundData(
          resolvedUserId,
          studentProvider,
          dailyChallengeProvider,
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load dashboard: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // Load other data in background after UI is shown
  void _loadBackgroundData(
    String userId,
    StudentProvider studentProvider,
    DailyChallengeProvider dailyChallengeProvider,
  ) async {
    try {
      // Process ended tests in background
      FirestoreService().processEndedTests().catchError((_) {});

      // Initialize daily challenge in background
      dailyChallengeProvider.initialize(userId).catchError((_) {});
    } catch (e) {
      // Ignore background loading errors
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        final student = studentProvider.currentStudent;
        final authUser = Provider.of<app_auth.AuthProvider>(
          context,
        ).currentUser;

        // Show skeleton loading (same as teacher)
        if (_isLoading) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: _buildLoadingSkeleton(),
          );
        }

        // Show error if data fetch failed (same as teacher)
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
                    onPressed: _loadDashboardData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        // Show dashboard content
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
    return Consumer<ProfileDPProvider>(
      builder: (context, dpProvider, _) {
        final studentProvider = Provider.of<StudentProvider>(
          context,
          listen: false,
        );
        final studentName = studentProvider.currentStudent?.name ?? 'Student';
        final imageUrl = dpProvider.currentUserDP;

        // Show real avatar if we have a DP, otherwise show icon button
        if (imageUrl != null && imageUrl.isNotEmpty) {
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StudentProfileScreen(),
              ),
            ),
            child: ProfileAvatarWidget(
              imageUrl: imageUrl,
              name: studentName,
              size: 44,
              showBorder: true,
              borderColor: const Color(0xFFF2800D),
              borderWidth: 2,
            ),
          );
        }

        // Fallback: initials avatar (no photo yet)
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StudentProfileScreen(),
            ),
          ),
          child: studentName.isNotEmpty
              ? ProfileAvatarWidget(
                  name: studentName,
                  size: 44,
                  showBorder: true,
                  borderColor: const Color(0xFFF2800D),
                  borderWidth: 2,
                  circleBackgroundColor: const Color(0xFF3D3D3D),
                  initialsColor: const Color(0xFFF2800D),
                )
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : _surface(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : Colors.grey.shade300,
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
      },
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
                // Check if announcement is still valid (not expired) and meets visibility criteria
                if (status.teacherId.isNotEmpty &&
                    status.isValid &&
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
                // Only show school-wide or matching standard announcements that haven't expired
                if (announcement.isValid &&
                    (announcement.audienceType == 'school' ||
                        (announcement.audienceType == 'standard' &&
                            announcement.standards.contains(userStandard)))) {
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
            separatorBuilder: (_, _) => const SizedBox(width: 16),
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
                // For principal announcements, check cached viewed status
                final principalAnnouncements = creatorAnnouncements
                    .where((a) => a['type'] == 'principal')
                    .map((a) => a['data'] as InstituteAnnouncementModel)
                    .toList();

                // Check cache immediately - no delay
                final hasUnread = principalAnnouncements.any(
                  (announcement) => _viewedCache[announcement.id] != true,
                );

                return _buildAnnouncementAvatar('Principal', hasUnread, () {
                  _openCrossPersonAnnouncementViewer(
                    creatorGroups,
                    index,
                    currentUserId,
                  );
                }, count: creatorAnnouncements.length);
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

        // DEBUG: Log principal announcement data
        if (principal.imageCaptions != null) {
          for (int i = 0; i < principal.imageCaptions!.length; i++) {}
        }

        // Get image URL - prefer imageCaptions[0] if available, fallback to imageUrl
        String? displayImageUrl;
        String? displayText;

        if (principal.imageCaptions != null &&
            principal.imageCaptions!.isNotEmpty) {
          final urlFromCaptions = principal.imageCaptions![0]['url'];
          // Validate URL is not empty
          displayImageUrl =
              (urlFromCaptions != null && urlFromCaptions.isNotEmpty)
              ? urlFromCaptions
              : null;
          displayText = principal.imageCaptions![0]['caption'];
          // If no caption but has text field, use that
          if (displayText == null || displayText.isEmpty) {
            displayText = principal.text.isNotEmpty
                ? principal.text
                : 'Principal Announcement';
          }
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

        return {
          'role': 'principal',
          'title': displayText,
          'subtitle': '',
          'postedByLabel': 'Posted by ${principal.principalName}',
          'avatarUrl': displayImageUrl, // Now passes the actual image URL
          'postedAt': principal.createdAt,
          'expiresAt': principal.expiresAt,
          '_originalData': item, // Keep reference for marking viewed
          '_principalData': principal, // Pass full principal data
          'imageCaptions': principal
              .imageCaptions, // Pass imageCaptions for multi-image support
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
                  .catchError((e) {});
            } else if (type == 'principal') {
              final principalAnnouncement =
                  originalData['data'] as InstituteAnnouncementModel;

              // Mark as viewed in local cache immediately for instant UI update
              _viewedCache[principalAnnouncement.id] = true;

              // Trigger UI rebuild after current frame to avoid setState during build
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {});
                }
              });

              // Mark in Firestore for persistence
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
      // Add user to views subcollection
      await FirebaseFirestore.instance
          .collection('institute_announcements')
          .doc(announcementId)
          .collection('views')
          .doc(userId)
          .set({'viewedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('Error marking announcement as viewed: $e');
    }
  }

  /// Combine announcements from both teachers and principals
  Stream<List<Map<String, dynamic>>> _combineAnnouncementStreams(
    String instituteId,
  ) async* {
    try {
      await for (final teacherSnapshot
          in FirebaseFirestore.instance
              .collection('class_highlights')
              .where('instituteId', isEqualTo: instituteId)
              .snapshots()) {
        final combined = <Map<String, dynamic>>[];

        // Add teacher announcements
        for (final doc in teacherSnapshot.docs) {
          combined.add({'type': 'teacher', 'snapshot': doc});
        }

        // Get principal announcements — catch permission errors independently
        try {
          final principalSnapshot = await FirebaseFirestore.instance
              .collection('institute_announcements')
              .where('instituteId', isEqualTo: instituteId)
              .get();
          for (final doc in principalSnapshot.docs) {
            combined.add({'type': 'principal', 'snapshot': doc});
          }
        } catch (e) {
          debugPrint('Could not load institute_announcements: $e');
        }

        yield combined;
      }
    } catch (e) {
      debugPrint('_combineAnnouncementStreams error: $e');
      yield [];
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
      } catch (e) {}
    }

    return {'standard': userStandard, 'section': userSection};
  }

  // Points Card with circular progress
  Widget _buildPointsCard(StudentModel? student) {
    if (student == null) {
      return _buildEmptyPointsCard();
    }

    // Cache the future so the FutureBuilder inside the StreamBuilder builder
    // doesn't create a new Future on every stream event.
    if (_topperPointsFuture == null || _cachedTopperStudentId != student.uid) {
      _cachedTopperStudentId = student.uid;
      _topperPointsFuture = _getTopperPoints(student);
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
        } else if (rewardsSnapshot.hasError) {
          // Permission denied or network error — fall back to cached value on student model
          studentPoints = student.rewardPoints;
        }

        // Get topper points from class
        return FutureBuilder<int>(
          future: _topperPointsFuture,
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
                  strokeWidth: 14,
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
      final schoolCode = (student.schoolCode ?? '').trim();
      final className = (student.className ?? '').trim();
      final section = (student.section ?? '').trim();

      if (schoolCode.isEmpty || className.isEmpty) return 0;

      // Section-aware cache key so different sections don't share stale data
      final cacheClassName = section.isNotEmpty
          ? '$className|$section'
          : className;

      final cachedPoints = await CacheManager.getTopperPointsCache(
        schoolId: schoolCode,
        className: cacheClassName,
      );
      if (cachedPoints != null) return cachedPoints;

      // Step 1: Get all student UIDs in this class/section
      var q = FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: className);
      if (section.isNotEmpty) {
        q = q.where('section', isEqualTo: section);
      }
      final studentsSnap = await q.get();
      if (studentsSnap.docs.isEmpty) return 0;

      final uids = studentsSnap.docs
          .map((d) => d.data()['uid'] as String?)
          .whereType<String>()
          .toList();
      if (uids.isEmpty) return 0;

      // Step 2: Aggregate student_rewards pointsEarned for each student.
      // This uses the exact same data source as the studentPoints displayed in the UI,
      // so the topper value is always consistent with what each student sees for themselves.
      int topperPoints = 0;
      for (final uid in uids) {
        final rewardsSnap = await FirebaseFirestore.instance
            .collection('student_rewards')
            .where('studentId', isEqualTo: uid)
            .get();
        int points = 0;
        for (final doc in rewardsSnap.docs) {
          final val = doc.data()['pointsEarned'];
          if (val is int) {
            points += val;
          } else if (val is num) {
            points += val.toInt();
          }
        }
        if (points > topperPoints) topperPoints = points;
      }

      await CacheManager.cacheTopperPoints(
        schoolId: schoolCode,
        className: cacheClassName,
        points: topperPoints,
      );

      return topperPoints;
    } catch (e) {
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
        final challengeData = dailyChallengeProvider.getCachedChallenge(
          student.uid,
        );

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
                // Title with icon
                Row(
                  children: [
                    Icon(
                      hasAnswered
                          ? (isCorrect
                                ? Icons.check_circle
                                : Icons.info_outline)
                          : Icons.emoji_events_outlined,
                      color: hasAnswered
                          ? (isCorrect
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFEF5350))
                          : _primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasAnswered
                            ? (isCorrect
                                  ? 'Challenge Completed! 🎉'
                                  : 'Challenge Attempted')
                            : 'Daily Challenge 🏆',
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
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  hasAnswered
                      ? (isCorrect
                            ? 'Perfect! You earned +5 points! 🌟'
                            : 'Keep trying! Check the correct answer below.')
                      : "Answer today's MCQ to earn points and boost your streak!",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: hasAnswered
                        ? (isCorrect
                              ? const Color(0xFF4CAF50).withOpacity(0.9)
                              : const Color(0xFFEF5350).withOpacity(0.9))
                        : _muted(context),
                  ),
                ),

                // Premium Correct Answer Display (only shown after attempt)
                if (hasAnswered && challengeData != null) ...[
                  const SizedBox(height: 16),
                  _buildCorrectAnswerDisplay(
                    challengeData['correctAnswer'] as String?,
                    challengeData['question'] as String?,
                    isCorrect,
                  ),
                ],

                // Button
                if (!hasAnswered) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_primary, _primary.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_arrow, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Take Challenge',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // Premium Correct Answer Display Widget
  Widget _buildCorrectAnswerDisplay(
    String? correctAnswer,
    String? question,
    bool wasCorrect,
  ) {
    if (correctAnswer == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = const Color(0xFFF2800D);
    final danger = const Color(0xFFE44F4F);
    final cardGradients = [
      isDark ? const Color(0xFF1A1B1F) : const Color(0xFFFBFBFE),
      isDark ? const Color(0xFF111218) : const Color(0xFFF1F2F7),
    ];
    final muted = isDark ? Colors.white70 : Colors.black54;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        // Clamp value to valid range [0.0, 1.0] to prevent animation errors during hot restart
        final clampedValue = value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: 0.96 + (0.04 * clampedValue),
          child: Opacity(
            opacity: clampedValue,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: cardGradients,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.04),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.28 : 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Correct answer header
                  Text(
                    "Keep trying! Check the correct answer below.",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: muted,
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Correct answer highlight block
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.04)
                          : Colors.black.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (wasCorrect ? accent : danger).withOpacity(0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (wasCorrect ? accent : danger).withOpacity(
                              0.12,
                            ),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            color: wasCorrect ? accent : danger,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            correctAnswer,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
          // Start date
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'Starts: ${_formatDateTime(test.startDate)}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
                isDueToday
                    ? 'Due Today, ${_formatTime(test.endDate)}'
                    : 'Due: ${_formatDateTime(test.endDate)}',
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

  String _formatDateTime(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = date.day;
    final month = months[date.month - 1];
    return '$day $month, ${_formatTime(date)}';
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

          // Logging suppressed: performance calculation details

          for (var result in results) {
            // Logging suppressed: individual test scores
            totalScore += result.score;
          }

          avgScore = testsTaken > 0 ? totalScore / testsTaken : 0.0;
          // Logging suppressed: performance summary
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_rounded, size: 24, color: _primary),
                const SizedBox(width: 8),
                Text(
                  'Performance',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StatRingCard(
              percentage: avgScore,
              primaryValue: '${avgScore.toInt()}%',
              primaryLabel: 'Avg. Score',
              accentColor: _primary,
              ringSize: 150,
              details: [
                StatDetail(
                  value: '$testsTaken',
                  label: 'Tests Taken',
                  icon: Icons.assignment_outlined,
                  iconColor: _primary.withOpacity(0.8),
                ),
                StatDetail(
                  value: '${avgScore.toInt()}%',
                  label: 'Average Score',
                  icon: Icons.trending_up_rounded,
                  iconColor: _primary.withOpacity(0.8),
                ),
              ],
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

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 24, color: _primary),
                const SizedBox(width: 8),
                Text(
                  'Attendance',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.2,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StatRingCard(
              percentage: attendancePct,
              primaryValue: '${attendancePct.toInt()}%',
              primaryLabel: 'Present',
              accentColor: _primary,
              ringSize: 150,
              details: [
                StatDetail(
                  value: '$presentDays',
                  label: 'Days Present',
                  dotColor: _primary,
                ),
                StatDetail(
                  value: '$absentDays',
                  label: 'Days Absent',
                  dotColor: _primary.withOpacity(0.3),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // Skeleton loading screen (same as teacher dashboard)
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                // Points card skeleton
                Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: shimmerColor,
                  ),
                ),
                const SizedBox(height: 24),
                // Cards skeleton
                ...List.generate(
                  4,
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
