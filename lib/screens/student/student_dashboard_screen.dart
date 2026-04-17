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
import '../../services/offline_cache_manager.dart';
import '../../utils/cache_manager.dart';
import '../../widgets/stat_ring_card.dart';
import '../../widgets/profile_avatar_widget.dart';
import '../../widgets/notification_bell_button.dart';
import '../daily_challenge_result_screen.dart';
import 'daily_challenge_screen.dart';
import 'student_profile_screen.dart';
import '../ai/ai_chat_page.dart';
import '../common/announcement_pageview_screen.dart';
import 'dart:math' as math;
import 'dart:async';
import '../../controllers/animation_controller.dart';
import '../../widgets/animated_card_slider.dart';
import '../../widgets/animated_button.dart';
import '../../widgets/animated_progress_ring.dart';

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
  Future<String?>? _studentDocIdFuture;
  String? _studentDocLookupUid;

  // Cache viewed status for immediate UI updates - key: announcementId, value: isViewed
  final Map<String, bool> _viewedCache = {};
  final Map<String, Stream<List<Map<String, dynamic>>>>
  _announcementStreamCache = {};
  final OfflineCacheManager _offlineCacheManager = OfflineCacheManager();
  final ScrollController _scrollController = ScrollController();

  bool _showChallengeSection = false;
  bool _showPerformanceSection = false;
  bool _showPointsPulse = false;

  int _lastAnimatedPoints = 0;
  int _displayedPoints = 0;
  Timer? _pointsCounterTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollAnimations);
    _loadDashboardData();
    _preloadViewedStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirestoreService().processEndedTests();
      if (mounted) {
        setState(() {
          _showChallengeSection = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _pointsCounterTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScrollAnimations() {
    final offset = _scrollController.offset;
    if (!_showChallengeSection && offset > 120) {
      setState(() => _showChallengeSection = true);
    }
    if (!_showPerformanceSection && offset > 320) {
      setState(() => _showPerformanceSection = true);
    }
  }

  void _animatePointsCounter(int targetValue) {
    if (targetValue == _lastAnimatedPoints && _displayedPoints != 0) {
      return;
    }

    _lastAnimatedPoints = targetValue;
    _pointsCounterTimer?.cancel();

    final start = _displayedPoints;
    final end = targetValue;
    const steps = 22;
    var currentStep = 0;

    _pointsCounterTimer = Timer.periodic(const Duration(milliseconds: 28), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      currentStep++;
      final t = (currentStep / steps).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      final next = start + ((end - start) * eased).round();

      if (_displayedPoints != next) {
        setState(() => _displayedPoints = next);
      }

      if (currentStep >= steps) {
        setState(() {
          _displayedPoints = end;
          _showPointsPulse = true;
        });
        timer.cancel();
      }
    });
  }

  Route<T> _buildAnimatedRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: DashboardAnimationConfig.pageTransition,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        final slide = Tween<Offset>(
          begin: const Offset(0.04, 0),
          end: Offset.zero,
        ).animate(fade);
        final scale = Tween<double>(begin: 0.985, end: 1.0).animate(fade);

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
    );
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
          body: Stack(
            children: [
              const Positioned.fill(child: _AnimatedDashboardBackground()),
              RefreshIndicator(
                onRefresh: _loadDashboardData,
                color: const Color(0xFFF2800D),
                child: CustomScrollView(
                  controller: _scrollController,
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
                          if (student != null)
                            _buildAnimatedEntrance(
                              visible: true,
                              child: _buildAnnouncementsSection(student),
                            ),

                          const SizedBox(height: 16),

                          // Auto sliding summary cards
                          _buildTopSliderSection(student),

                          const SizedBox(height: 18),

                          // Daily Challenge
                          if (student != null)
                            _buildAnimatedEntrance(
                              visible: _showChallengeSection,
                              child: _buildDailyChallengeCard(student),
                            ),

                          const SizedBox(height: 24),

                          // Assigned Tests
                          _buildAssignedTestsSection(student),

                          const SizedBox(height: 24),

                          // Performance
                          _buildAnimatedEntrance(
                            visible: _showPerformanceSection,
                            child: _buildPerformanceSection(student),
                          ),

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
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(_buildAnimatedRoute(const AiChatPage()));
            },
            backgroundColor: _primary,
            elevation: 4,
            child: const Icon(Icons.smart_toy, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedEntrance({required bool visible, required Widget child}) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  Widget _buildTopSliderSection(StudentModel? student) {
    final cards = [
      _buildPointsCard(student),
      if (student != null) _buildDailyChallengeCard(student) else _buildEmptyPointsCard(),
      _buildPerformancePreviewCard(student),
    ];

    return AnimatedCardSlider(
      cards: cards,
      autoSlideInterval: DashboardAnimationConfig.cardAutoSlide,
    );
  }

  Widget _buildPerformancePreviewCard(StudentModel? student) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: _primary),
              const SizedBox(width: 8),
              Text(
                'Performance Snapshot',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            student == null
                ? 'Your latest results will appear here.'
                : 'Keep your streak alive with daily challenge and tests.',
            style: TextStyle(
              fontSize: 14,
              color: _muted(context),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Tip: Attempt tests regularly to improve your average score.',
              style: TextStyle(
                color: Color(0xFFF2800D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
                    NotificationBellButton(
                      iconColor: isDark ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 2),
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

        return _StreakPulseBadge(streakDays: streakDays, primary: _primary);
      },
    );
  }

  Future<void> _openStudentProfile() async {
    await Navigator.of(
      context,
    ).push(_buildAnimatedRoute(const StudentProfileScreen()));
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
            onTap: _openStudentProfile,
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
          onTap: _openStudentProfile,
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
          stream: _getAnnouncementStream(schoolIdentifier),
          builder: (context, announcementSnapshot) {
            if (announcementSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const SizedBox.shrink();
            }

            final combinedDocs = announcementSnapshot.data ?? [];
            final announcements = <Map<String, dynamic>>[];

            // Process teacher announcements
            for (final doc in combinedDocs) {
              final docMap = _normalizeAnnouncementMap(doc);
              final docType = docMap['type']?.toString() ?? '';

              if (docType == 'teacher') {
                final id = docMap['id']?.toString() ?? '';
                final rawData = _normalizeAnnouncementMap(docMap['data']);
                if (id.isEmpty) continue;
                final status = StatusModel.fromMap(id, rawData);
                // Check if announcement is still valid (not expired) and meets visibility criteria
                if (status.teacherId.isNotEmpty &&
                    status.isValid &&
                    status.isVisibleByNewRules(
                      userRole: 'student',
                      userStandard: userStandard,
                      userSection: userSection,
                    )) {
                  announcements.add({'type': 'teacher', 'data': status});
                }
              } else if (docType == 'principal') {
                final id = docMap['id']?.toString() ?? '';
                final rawData = _normalizeAnnouncementMap(docMap['data']);
                if (id.isEmpty) continue;
                final announcement = InstituteAnnouncementModel.fromMap(
                  id,
                  rawData,
                );
                if (announcement.isValid &&
                    announcement.isVisibleByNewRules(
                      userRole: 'student',
                      userStandard: userStandard,
                      userSection: userSection,
                    )) {
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

  Stream<List<Map<String, dynamic>>> _getAnnouncementStream(
    String instituteId,
  ) {
    final cached = _announcementStreamCache[instituteId];
    if (cached != null) return cached;

    final stream = _combineAnnouncementStreams(instituteId).asBroadcastStream();
    _announcementStreamCache[instituteId] = stream;
    return stream;
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

  Map<String, dynamic> _normalizeAnnouncementMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      final normalized = <String, dynamic>{};
      value.forEach((key, mapValue) {
        normalized[key.toString()] = mapValue;
      });
      return normalized;
    }
    return const <String, dynamic>{};
  }

  /// Combine announcements from both teachers and principals
  Stream<List<Map<String, dynamic>>> _combineAnnouncementStreams(
    String instituteId,
  ) async* {
    if (FirebaseAuth.instance.currentUser == null) {
      yield const <Map<String, dynamic>>[];
      return;
    }

    try {
      await _offlineCacheManager.initialize();
    } catch (_) {}

    final cached = _offlineCacheManager.getCachedAnnouncements(
      scope: 'student_dashboard',
      scopeId: instituteId,
    );
    if (cached != null && cached.isNotEmpty) {
      yield cached;
    }

    try {
      await for (final teacherSnapshot
          in FirebaseFirestore.instance
              .collection('class_highlights')
              .where('instituteId', isEqualTo: instituteId)
              .snapshots()) {
        if (FirebaseAuth.instance.currentUser == null) {
          break;
        }

        final combined = <Map<String, dynamic>>[];

        // Add teacher announcements
        for (final doc in teacherSnapshot.docs) {
          combined.add({
            'type': 'teacher',
            'id': doc.id,
            'data': _serializeAnnouncementMap(doc.data()),
          });
        }

        // Get principal announcements — catch permission errors independently
        try {
          final principalSnapshot = await FirebaseFirestore.instance
              .collection('institute_announcements')
              .where('instituteId', isEqualTo: instituteId)
              .get();
          for (final doc in principalSnapshot.docs) {
            combined.add({
              'type': 'principal',
              'id': doc.id,
              'data': _serializeAnnouncementMap(doc.data()),
            });
          }
        } catch (e) {
          debugPrint('Could not load institute_announcements: $e');
        }

        await _offlineCacheManager.cacheAnnouncements(
          scope: 'student_dashboard',
          scopeId: instituteId,
          announcements: combined,
        );

        yield combined;
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isSignedOut = FirebaseAuth.instance.currentUser == null;
      if (isSignedOut &&
          (msg.contains('permission-denied') ||
              msg.contains('permission denied') ||
              msg.contains('insufficient permissions'))) {
        yield const <Map<String, dynamic>>[];
        return;
      }

      debugPrint('_combineAnnouncementStreams error: $e');
      final fallback = _offlineCacheManager.getCachedAnnouncements(
        scope: 'student_dashboard',
        scopeId: instituteId,
      );
      yield fallback ?? const <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _serializeAnnouncementMap(Map<String, dynamic> input) {
    final output = <String, dynamic>{};
    input.forEach((key, value) {
      output[key] = _serializeAnnouncementValue(value);
    });
    return output;
  }

  dynamic _serializeAnnouncementValue(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    if (value is Map) {
      final mapped = <String, dynamic>{};
      value.forEach((k, v) {
        mapped[k.toString()] = _serializeAnnouncementValue(v);
      });
      return mapped;
    }
    if (value is List) {
      return value.map(_serializeAnnouncementValue).toList();
    }
    return value;
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

    if (_studentDocIdFuture == null || _studentDocLookupUid != student.uid) {
      _studentDocLookupUid = student.uid;
      _studentDocIdFuture = _resolveStudentDocId(student);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('student_rewards')
          .where('studentId', isEqualTo: student.uid)
          .snapshots(),
      builder: (context, rewardsSnapshot) {
        double totalEarnedPoints = 0;

        if (rewardsSnapshot.hasData) {
          for (final doc in rewardsSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null) {
              final points = data['pointsEarned'];
              if (points is int) {
                totalEarnedPoints += points;
              } else if (points is num) {
                totalEarnedPoints += points.toDouble();
              }
            }
          }
        }

        return FutureBuilder<String?>(
          future: _studentDocIdFuture,
          builder: (context, docIdSnapshot) {
            final docId = docIdSnapshot.data;

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: docId == null
                  ? null
                  : FirebaseFirestore.instance
                        .collection('students')
                        .doc(docId)
                        .snapshots(),
              builder: (context, studentSnapshot) {
                int studentPoints = student.rewardPoints;

                if (rewardsSnapshot.hasError) {
                  // Permission/network fallback to cached model value
                  studentPoints = student.rewardPoints;
                } else {
                  // Show total earned points (not available/deducted)
                  // This matches the leaderboard and is the canonical source
                  final earned = totalEarnedPoints.toInt();
                  studentPoints = earned < 0 ? 0 : earned;

                  // Fallback: if no earned points, use available_points from student doc
                  if (studentPoints == 0) {
                    final studentData = studentSnapshot.data?.data();
                    if (studentData != null &&
                        studentData.containsKey('available_points')) {
                      final available =
                          (studentData['available_points'] as num?)?.toInt() ??
                          0;
                      studentPoints = available < 0 ? 0 : available;
                    }
                  }
                }

                // Get topper points from class
                return FutureBuilder<int>(
                  future: _topperPointsFuture,
                  builder: (context, topperSnapshot) {
                    final topperPoints = topperSnapshot.data ?? 0;
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;

                    _animatePointsCounter(studentPoints);

                    return AnimatedScale(
                      scale: _showPointsPulse ? 1.0 : 0.985,
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 22,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: _surface(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.4),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              isDark ? 0.25 : 0.06,
                            ),
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
                            'Your Points: $_displayedPoints',
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
                    ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<String?> _resolveStudentDocId(StudentModel student) async {
    // Fast path where docId already equals uid.
    try {
      final byId = await FirebaseFirestore.instance
          .collection('students')
          .doc(student.uid)
          .get();
      if (byId.exists) return byId.id;
    } catch (_) {}

    // Canonical lookup by uid field.
    try {
      final byUid = await FirebaseFirestore.instance
          .collection('students')
          .where('uid', isEqualTo: student.uid)
          .limit(1)
          .get();
      if (byUid.docs.isNotEmpty) return byUid.docs.first.id;
    } catch (_) {}

    // Legacy fallback by email.
    if (student.email.isNotEmpty) {
      try {
        final byEmail = await FirebaseFirestore.instance
            .collection('students')
            .where('email', isEqualTo: student.email)
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty) return byEmail.docs.first.id;
      } catch (_) {}
    }

    return null;
  }

  Widget _buildCircularComparison(int studentPoints, int topperPoints) {
    return AnimatedProgressRing(
      key: ValueKey<int>(studentPoints),
      value: studentPoints,
      maxValue: topperPoints <= 0 ? math.max(studentPoints, 1) : topperPoints,
      label: 'POINTS',
      duration: const Duration(milliseconds: 1700),
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

      // Step 1: Load class roster.
      var q = FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: className);
      if (section.isNotEmpty) {
        q = q.where('section', isEqualTo: section);
      }
      final studentsSnap = await q.get();
      if (studentsSnap.docs.isEmpty) return 0;

      // Step 2: Calculate total earned points for each student (not available/deducted)
      // This ensures the topper points match the leaderboard display
      int topperPoints = 0;
      for (final doc in studentsSnap.docs) {
        final uid = (doc.data()['uid'] as String?);
        if (uid == null) continue;

        // Calculate earned points from student_rewards for this student
        int earnedPoints = 0;
        try {
          final rewardsSnap = await FirebaseFirestore.instance
              .collection('student_rewards')
              .where('studentId', isEqualTo: uid)
              .get();
          for (final rewardDoc in rewardsSnap.docs) {
            final pts = rewardDoc.data()['pointsEarned'];
            if (pts is num) earnedPoints += pts.toInt();
          }
        } catch (_) {
          // Fallback to available_points if student_rewards fails
          final data = doc.data();
          earnedPoints = (data['available_points'] as num?)?.toInt() ?? 0;
        }

        if (earnedPoints > topperPoints) topperPoints = earnedPoints;
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

  Future<void> _openDailyChallenge(
    StudentModel student,
    StudentProvider studentProvider,
    DailyChallengeProvider dailyChallengeProvider,
  ) async {
    final challengeResult = await Navigator.push<bool>(
      context,
      _buildAnimatedRoute(
        DailyChallengeScreen(
          studentId: student.uid,
          studentEmail: student.email,
        ),
      ),
    );

    if (!mounted || challengeResult == null) {
      return;
    }

    // Refresh streak before showing the overlay so the badge is current.
    await studentProvider.refreshStudentStreak(student.uid);
    final streakDays = studentProvider.currentStudent?.streak ?? 0;

    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => DailyChallengeResultScreen(
          isWinner: challengeResult,
          score: challengeResult ? 100 : 0,
          passingScore: 50,
          streakDays: streakDays,
          onContinue: () {},
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    // Re-check completion state after the overlay closes.
    await Future.delayed(const Duration(milliseconds: 300));
    await dailyChallengeProvider.initialize(student.uid);
    await studentProvider.refreshStudentStreak(student.uid);
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

        return Container(
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
                  AnimatedChallengeButton(
                    onPressed: () => _openDailyChallenge(
                      student,
                      studentProvider,
                      dailyChallengeProvider,
                    ),
                  ),
                ],
              ],
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

    final resultsStream = FirestoreService()
        .getTestResultsByStudent(student.uid)
        .asBroadcastStream();

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
      stream: FirestoreService()
          .getTestResultsByStudent(student.uid)
          .asBroadcastStream(),
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

class _StreakPulseBadge extends StatefulWidget {
  final int streakDays;
  final Color primary;

  const _StreakPulseBadge({
    required this.streakDays,
    required this.primary,
  });

  @override
  State<_StreakPulseBadge> createState() => _StreakPulseBadgeState();
}

class _StreakPulseBadgeState extends State<_StreakPulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = 0.10 + (_controller.value * 0.08);
        final scale = 0.98 + (_controller.value * 0.03);
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: widget.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: widget.primary.withValues(alpha: glow),
                  blurRadius: 12,
                  spreadRadius: 0.6,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: (_controller.value - 0.5) * 0.06,
                  child: const Icon(
                    Icons.local_fire_department,
                    color: Color(0xFFF2800D),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.streakDays}',
                  style: const TextStyle(
                    color: Color(0xFFF2800D),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedDashboardBackground extends StatefulWidget {
  const _AnimatedDashboardBackground();

  @override
  State<_AnimatedDashboardBackground> createState() =>
      _AnimatedDashboardBackgroundState();
}

class _AnimatedDashboardBackgroundState extends State<_AnimatedDashboardBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final shift = (_controller.value - 0.5) * 26;
          return Stack(
            children: [
              Positioned(
                top: 40 + shift,
                right: -18,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(
                          0xFFF2800D,
                        ).withValues(alpha: isDark ? 0.08 : 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 120 - shift,
                left: -36,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.blue.withValues(alpha: isDark ? 0.05 : 0.07),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
