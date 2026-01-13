import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/parent_provider.dart';
import '../../models/student_model.dart';
import '../../models/reward_request_model.dart';
import 'parent_profile_screen.dart';
import '../common/announcement_pageview_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  // Parent green theme colors
  static const Color parentGreen = Color(0xFF14A670);

  Color _scaffoldBg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  Color _cardColor(BuildContext context) => Theme.of(context).cardColor;

  Color _onBackground(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  final PageController _childrenPageController = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeParentData();
    });
  }

  Future<void> _initializeParentData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);

    // Wait for auth to initialize first
    await authProvider.ensureInitialized();

    if (authProvider.currentUser != null) {
      final parentEmail = authProvider.currentUser!.email;
      final parentId = authProvider.currentUser!.uid;

      await parentProvider.initialize(parentEmail, parentId: parentId);
    }
  }

  @override
  void dispose() {
    _childrenPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer2<AuthProvider, ParentProvider>(
      builder: (context, authProvider, parentProvider, child) {
        // Show loading skeleton while initializing or loading children
        if (!authProvider.isInitialized || parentProvider.isLoadingChildren) {
          return Scaffold(
            backgroundColor: _scaffoldBg(context),
            body: _buildLoadingSkeleton(isDark),
          );
        }

        // Show message if no children found
        if (!parentProvider.hasChildren) {
          return Scaffold(
            backgroundColor: _scaffoldBg(context),
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.family_restroom,
                      size: 80,
                      color: isDark ? Colors.grey[700] : Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No children found',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : _onBackground(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Make sure your email is linked to student accounts',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => parentProvider.loadChildren(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: parentGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final currentChild = parentProvider.selectedChild!;
        final performanceStats = parentProvider.performanceStats;

        return Scaffold(
          backgroundColor: _scaffoldBg(context),
          body: SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(isDark, authProvider),

                // Scrollable Content
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => parentProvider.refresh(),
                    color: parentGreen,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Children Profile Cards Carousel
                          _buildChildrenCarousel(isDark, parentProvider),

                          // Page Indicator
                          _buildPageIndicator(parentProvider),

                          // Announcements Section
                          _buildAnnouncementsSection(isDark, parentProvider),

                          // Performance Summary
                          _buildPerformanceSummary(
                            isDark,
                            currentChild,
                            performanceStats,
                            parentProvider.attendance,
                          ),

                          // Parent-Teacher Section Group Card
                          _buildSectionGroupCard(isDark, parentProvider),

                          // Reward Requests
                          _buildRewardRequests(isDark, parentProvider),

                          // Teacher Messages
                          _buildTeacherMessages(isDark, parentProvider),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionGroupCard(bool isDark, ParentProvider parentProvider) {
    final group = parentProvider.sectionGroup;
    final isLoading = parentProvider.isLoadingSectionGroup;
    final error = parentProvider.sectionGroupError;
    final child = parentProvider.selectedChild;

    if (child == null) return const SizedBox.shrink();

    final fallbackTitle =
        '${child.className ?? 'Class'} ${child.section ?? ''} Parents & Teachers'
            .trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.transparent,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0 : 0.03),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: (group == null || isLoading || error != null)
              ? null
              : () {
                  Navigator.pushNamed(
                    context,
                    '/parent/section-group-chat',
                    arguments: {
                      'groupId': group.id,
                      'groupName': group.name.isNotEmpty
                          ? group.name
                          : fallbackTitle,
                      'className': group.className,
                      'section': group.section,
                      'schoolCode': group.schoolCode,
                      'childName': child.name,
                      'childId': child.uid,
                    },
                  );
                },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: parentGreen.withOpacity(0.15),
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        color: parentGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group?.name.isNotEmpty == true
                                ? group!.name
                                : fallbackTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : _onBackground(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Chat with teachers and parents of this section',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: parentGreen),
                  ],
                ),
                const SizedBox(height: 12),
                if (isLoading)
                  Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            parentGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Preparing your section group…',
                        style: TextStyle(
                          color: isDark ? Colors.white : _onBackground(context),
                        ),
                      ),
                    ],
                  )
                else if (error != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[400]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Could not load section group',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white
                                    : _onBackground(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              error,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[700],
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () =>
                                  parentProvider.loadSectionGroup(child),
                              icon: const Icon(
                                Icons.refresh,
                                color: parentGreen,
                              ),
                              label: const Text(
                                'Retry',
                                style: TextStyle(color: parentGreen),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    (group != null && group.lastMessage.isNotEmpty)
                        ? group.lastMessage
                        : 'Say hello to teachers and fellow parents of ${child.className ?? ''}${child.section != null ? ' - ${child.section}' : ''}',
                    style: TextStyle(
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, AuthProvider authProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _scaffoldBg(context),
      child: Row(
        children: [
          const SizedBox(width: 40),

          // Title
          Expanded(
            child: Text(
              'Dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : _onBackground(context),
              ),
            ),
          ),

          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildChildrenCarousel(bool isDark, ParentProvider parentProvider) {
    final children = parentProvider.children;
    final selectedIndex = parentProvider.selectedChildIndex;

    return SizedBox(
      height: 240,
      child: PageView.builder(
        controller: _childrenPageController,
        onPageChanged: (index) {
          parentProvider.selectChild(index);
        },
        itemCount: children.length,
        itemBuilder: (context, index) {
          final child = children[index];
          final isActive = index == selectedIndex;
          final cardColor = _cardColor(context);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Opacity(
              opacity: isActive ? 1.0 : 0.7,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cardColor.withOpacity(
                    isActive ? 1.0 : (isDark ? 0.6 : 0.8),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.transparent,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(
                              isDark ? 0.2 : 0.05,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile Header with Gradient
                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF14A670), Color(0xFF0F8A5A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Initial Circle
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  child.name.isNotEmpty
                                      ? child.name[0].toUpperCase()
                                      : 'S',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF14A670),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Name
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                (child.name.trim().isNotEmpty
                                    ? child.name
                                    : 'Student'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Class with icon
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.school,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${child.className ?? "N/A"}${child.section != null ? " - ${child.section}" : ""}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Child Info
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  if (isActive) {
                                    // Navigate to child profile screen
                                    Navigator.pushNamed(
                                      context,
                                      '/parent/child-profile',
                                    );
                                  } else {
                                    parentProvider.selectChild(index);
                                    _childrenPageController.animateToPage(
                                      index,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isActive
                                      ? parentGreen
                                      : parentGreen.withOpacity(0.2),
                                  foregroundColor: isActive
                                      ? Colors.white
                                      : (isDark
                                            ? Colors.white
                                            : _onBackground(context)),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: isActive ? 2 : 0,
                                ),
                                child: Text(
                                  isActive ? 'View Profile' : 'Switch Profile',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
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
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageIndicator(ParentProvider parentProvider) {
    final children = parentProvider.children;
    final selectedIndex = parentProvider.selectedChildIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(children.length, (index) {
          final isActive = index == selectedIndex;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 16 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? parentGreen : parentGreen.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAnnouncementsSection(
    bool isDark,
    ParentProvider parentProvider,
  ) {
    // Filter announcements to only those within 24 hours or with future expiresAt
    final now = DateTime.now();
    final announcements = parentProvider.announcements.where((a) {
      final createdAt = a['createdAt'];
      final expiresAt = a['expiresAt'];
      DateTime? created;
      DateTime? expiry;
      if (createdAt is Timestamp) {
        created = createdAt.toDate();
      } else if (createdAt is DateTime) {
        created = createdAt;
      } else if (createdAt is String) {
        try {
          created = DateTime.parse(createdAt);
        } catch (_) {}
      }
      if (expiresAt is Timestamp) {
        expiry = expiresAt.toDate();
      } else if (expiresAt is DateTime) {
        expiry = expiresAt;
      } else if (expiresAt is String) {
        try {
          expiry = DateTime.parse(expiresAt);
        } catch (_) {}
      }
      // If expiry provided, use it; else fallback to 24h from created
      if (expiry != null) {
        return expiry.isAfter(now);
      }
      if (created != null) {
        return now.difference(created) < const Duration(hours: 24);
      }
      // If timestamps missing, keep to be safe
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title with Icon
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: parentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.campaign, color: parentGreen, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                '📢 Announcements',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _onBackground(context),
                ),
              ),
            ],
          ),
        ),

        // Horizontal scrollable list of circular avatars
        SizedBox(
          height: 100,
          child: announcements.isEmpty
              ? _buildEmptyAnnouncementsList(isDark)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: announcements.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final announcement = announcements[index];
                    return _buildAnnouncementAvatar(isDark, announcement);
                  },
                ),
        ),
      ],
    );
  }

  /// Empty announcements list
  Widget _buildEmptyAnnouncementsList(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mail_outline,
              size: 32,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'No announcements yet',
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual announcement avatar (circular with gradient border)
  Widget _buildAnnouncementAvatar(
    bool isDark,
    Map<String, dynamic> announcement,
  ) {
    final teacherName = announcement['teacherName'] as String? ?? 'Teacher';
    final teacherInitial = teacherName.isNotEmpty
        ? teacherName[0].toUpperCase()
        : 'T';
    final title = announcement['title'] as String? ?? 'Announcement';
    final description = announcement['description'] as String? ?? '';

    return GestureDetector(
      onTap: () {
        // Role mapping: prefer explicit role, fallback to 'teacher'
        final role =
            (announcement['role'] as String?)?.toLowerCase() ?? 'teacher';
        final postedByLabel =
            'Posted by ${role[0].toUpperCase()}${role.substring(1)}';

        // Parse timestamps
        DateTime? postedAt;
        DateTime? expiresAt;
        final createdAt = announcement['createdAt'];
        final expAt = announcement['expiresAt'];
        if (createdAt is Timestamp) {
          postedAt = createdAt.toDate();
        } else if (createdAt is DateTime) {
          postedAt = createdAt;
        } else if (createdAt is String) {
          try {
            postedAt = DateTime.parse(createdAt);
          } catch (_) {}
        }
        if (expAt is Timestamp) {
          expiresAt = expAt.toDate();
        } else if (expAt is DateTime) {
          expiresAt = expAt;
        } else if (expAt is String) {
          try {
            expiresAt = DateTime.parse(expAt);
          } catch (_) {}
        }
        // Fallback to 24h expiry if not provided
        expiresAt ??= (postedAt != null)
            ? postedAt.add(const Duration(hours: 24))
            : DateTime.now().add(const Duration(hours: 24));

        openAnnouncementPageView(
          context,
          announcements: [
            {
              'role': role,
              'title': title,
              'subtitle': description,
              'postedByLabel': postedByLabel,
              'avatarUrl': announcement['teacherPhotoUrl'] as String?,
              'postedAt': postedAt,
              'expiresAt': expiresAt,
            },
          ],
          initialIndex: 0,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with gradient border
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF14A670), Color(0xFF0F8A5A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _scaffoldBg(context),
              ),
              padding: const EdgeInsets.all(2),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: parentGreen.withOpacity(0.1),
                child: Text(
                  teacherInitial,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: parentGreen,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Teacher name (truncated to first name)
          SizedBox(
            width: 68,
            child: Text(
              teacherName.split(' ').first,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: parentGreen,
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

  Widget _buildPerformanceSummary(
    bool isDark,
    StudentModel child,
    Map<String, dynamic> performanceStats,
    double attendance,
  ) {
    final rewardPoints = child.rewardPoints;
    final testsCompleted = (performanceStats['completedTests'] ?? 0) as int;
    final attendancePercentage = attendance > 0
        ? attendance
        : (child.monthlyProgress * 100);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 32, bottom: 12),
            child: Text(
              'Performance Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : _onBackground(context),
              ),
            ),
          ),

          // Performance Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.emoji_events,
                  value: rewardPoints.toString(),
                  label: 'Rewards',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.history_edu,
                  value: testsCompleted.toString(),
                  label: 'Tests Attended',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.task_alt,
                  value: '${attendancePercentage.toStringAsFixed(0)}%',
                  label: 'Attendance',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0 : 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: parentGreen, size: 30),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : _onBackground(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRewardRequests(bool isDark, ParentProvider parentProvider) {
    final rewardRequests = parentProvider.rewardRequests
        .where((r) => r.status == RewardRequestStatus.pending)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 32, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reward Requests',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _onBackground(context),
                  ),
                ),
                if (rewardRequests.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: parentGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${rewardRequests.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Reward Requests List
          if (rewardRequests.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _cardColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  'No pending reward requests',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            )
          else
            ...rewardRequests.map((request) {
              IconData icon = Icons.emoji_events;
              if (request.productName.toLowerCase().contains('game')) {
                icon = Icons.sports_esports;
              } else if (request.productName.toLowerCase().contains(
                    'ice cream',
                  ) ||
                  request.productName.toLowerCase().contains('food')) {
                icon = Icons.icecream;
              } else if (request.productName.toLowerCase().contains('book')) {
                icon = Icons.book;
              } else if (request.productName.toLowerCase().contains('toy')) {
                icon = Icons.toys;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.transparent,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0 : 0.02),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: parentGreen.withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: parentGreen, size: 24),
                    ),
                    const SizedBox(width: 16),

                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.productName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white
                                  : _onBackground(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${request.pointsRequired} Points',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Approve/Reject Buttons
                    Row(
                      children: [
                        IconButton(
                          onPressed: () async {
                            final success = await parentProvider
                                .approveRewardRequest(request.id);
                            if (success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Reward request approved!'),
                                  backgroundColor: parentGreen,
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.check_circle,
                            color: parentGreen,
                          ),
                          tooltip: 'Approve',
                        ),
                        IconButton(
                          onPressed: () async {
                            final success = await parentProvider
                                .rejectRewardRequest(request.id, null);
                            if (success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Reward request rejected',
                                  ),
                                  backgroundColor: Colors.red[400],
                                ),
                              );
                            }
                          },
                          icon: Icon(Icons.cancel, color: Colors.red[400]),
                          tooltip: 'Reject',
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTeacherMessages(bool isDark, ParentProvider parentProvider) {
    final conversations = parentProvider.conversations.take(5).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.only(top: 32, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Messages from Teachers',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _onBackground(context),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // View all messages
                  },
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      color: parentGreen,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Messages List
          if (conversations.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _cardColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  'No messages yet',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            )
          else
            ...conversations.map((conversation) {
              final teacherName =
                  conversation['teacherName'] as String? ?? 'Teacher';
              final lastMessage = conversation['lastMessage'] as String? ?? '';
              final teacherPhotoUrl =
                  conversation['teacherPhotoUrl'] as String?;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _cardColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.transparent,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0 : 0.02),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/chat',
                      arguments: {
                        'conversationId': conversation['id'],
                        'parentName': teacherName,
                        'parentPhotoUrl': teacherPhotoUrl,
                        'studentName': parentProvider.selectedChild?.name ?? '',
                      },
                    );
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: parentGreen.withOpacity(0.2),
                        ),
                        child: teacherPhotoUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  teacherPhotoUrl,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(Icons.person, color: parentGreen, size: 24),
                      ),
                      const SizedBox(width: 16),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              teacherName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white
                                    : _onBackground(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lastMessage,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Loading skeleton placeholder - similar to teacher dashboard
  Widget _buildLoadingSkeleton(bool isDark) {
    final shimmerColor = isDark ? Colors.grey[800] : Colors.grey[300];

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
                parentGreen.withOpacity(0.3),
                parentGreen.withOpacity(0.1),
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
                // Child card skeleton
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: shimmerColor,
                  ),
                ),
                const SizedBox(height: 24),
                // Stats cards skeleton
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: shimmerColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: shimmerColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // More cards skeleton
                ...List.generate(
                  2,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      height: 120,
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
