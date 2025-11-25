import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  // Parent green theme colors
  static const Color parentGreen = Color(0xFF14A670);
  static const Color parentGreenLight = Color(0xFFD4F4E8);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  final PageController _childrenPageController = PageController();
  int _currentChildIndex = 0;

  // Mock data - replace with real data fetching
  final List<Map<String, dynamic>> _children = [
    {
      'name': 'Alex Johnson',
      'class': 'Class 4B',
      'image': 'https://via.placeholder.com/300x400',
      'rewards': 12,
      'testsAttended': 24,
      'attendance': 98,
    },
    {
      'name': 'Sarah Johnson',
      'class': 'Class 2A',
      'image': 'https://via.placeholder.com/300x400',
      'rewards': 8,
      'testsAttended': 18,
      'attendance': 95,
    },
  ];

  final List<Map<String, dynamic>> _announcements = [
    {
      'teacherName': 'Ms. Davis',
      'teacherInitial': 'D',
      'title': 'Science Fair Project Due',
      'description': 'Reminder: All projects must be submitted by Friday.',
      'date': 'Oct 28',
      'isUnread': true,
      'count': 2,
    },
    {
      'teacherName': 'Mr. Smith',
      'teacherInitial': 'S',
      'title': 'Parent-Teacher Meeting',
      'description': 'Scheduled for next Tuesday. Please RSVP.',
      'date': 'Oct 25',
      'isUnread': false,
      'count': 1,
    },
    {
      'teacherName': 'Ms. Johnson',
      'teacherInitial': 'J',
      'title': 'Field Trip Permission',
      'description': 'Please sign the permission form by tomorrow.',
      'date': 'Oct 24',
      'isUnread': true,
      'count': 1,
    },
  ];

  final List<Map<String, dynamic>> _rewardRequests = [
    {
      'icon': Icons.sports_esports,
      'title': 'Video Game Time',
      'description': '30 minutes',
    },
    {
      'icon': Icons.icecream,
      'title': 'Ice Cream Coupon',
      'description': '5 Points',
    },
  ];

  final List<Map<String, dynamic>> _teacherMessages = [
    {
      'name': 'Ms. Davis',
      'message': "That's great to hear! Alex has been making wonderful...",
      'image': 'https://via.placeholder.com/100',
    },
    {
      'name': 'Mr. Smith',
      'message': 'Just a quick note about the upcoming field trip. Please...',
      'image': 'https://via.placeholder.com/100',
    },
  ];

  @override
  void dispose() {
    _childrenPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentChild = _children[_currentChildIndex];

    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(isDark),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Children Profile Cards Carousel
                    _buildChildrenCarousel(isDark),

                    // Page Indicator
                    _buildPageIndicator(),

                    // Announcements Section
                    _buildAnnouncementsSection(isDark),

                    // Performance Summary
                    _buildPerformanceSummary(isDark, currentChild),

                    // Reward Requests
                    _buildRewardRequests(isDark),

                    // Teacher Messages
                    _buildTeacherMessages(isDark),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: isDark ? backgroundDark : backgroundLight,
      child: Row(
        children: [
          // Profile Picture
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: parentGreen.withOpacity(0.2),
              image: const DecorationImage(
                image: NetworkImage('https://via.placeholder.com/100'),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Title
          Expanded(
            child: Text(
              'Dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
          ),

          // Notifications Button
          IconButton(
            onPressed: () {
              // Handle notifications
            },
            icon: Icon(
              Icons.notifications_outlined,
              color: isDark ? Colors.white : textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChildrenCarousel(bool isDark) {
    return SizedBox(
      height: 280,
      child: PageView.builder(
        controller: _childrenPageController,
        onPageChanged: (index) {
          setState(() {
            _currentChildIndex = index;
          });
        },
        itemCount: _children.length,
        itemBuilder: (context, index) {
          final child = _children[index];
          final isActive = index == _currentChildIndex;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Opacity(
              opacity: isActive ? 1.0 : 0.7,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark ? backgroundDark.withOpacity(0.5) : cardBg)
                      : (isDark
                            ? backgroundDark.withOpacity(0.2)
                            : cardBg.withOpacity(0.5)),
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
                    // Profile Image
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        color: parentGreen.withOpacity(0.1),
                        image: DecorationImage(
                          image: NetworkImage(child['image']),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    // Child Info
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  child['name'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  child['class'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  // Handle view profile
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isActive
                                      ? parentGreen
                                      : parentGreen.withOpacity(0.2),
                                  foregroundColor: isActive
                                      ? Colors.white
                                      : (isDark ? Colors.white : textPrimary),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
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

  Widget _buildPageIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_children.length, (index) {
          final isActive = index == _currentChildIndex;
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

  Widget _buildAnnouncementsSection(bool isDark) {
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
                  color: isDark ? Colors.white : textPrimary,
                ),
              ),
            ],
          ),
        ),

        // Horizontal scrollable list of circular avatars
        SizedBox(
          height: 100,
          child: _announcements.isEmpty
              ? _buildEmptyAnnouncementsList(isDark)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _announcements.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final announcement = _announcements[index];
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
    final isUnread = announcement['isUnread'] as bool;
    final count = announcement['count'] as int;
    final teacherName = announcement['teacherName'] as String;
    final teacherInitial = announcement['teacherInitial'] as String;

    return GestureDetector(
      onTap: () {
        // Handle announcement tap - open viewer
        _showAnnouncementDetails(announcement);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with gradient border if unread
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isUnread
                      ? const LinearGradient(
                          colors: [Color(0xFF14A670), Color(0xFF0F8A5A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: !isUnread
                      ? Border.all(
                          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                          width: 2,
                        )
                      : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? backgroundDark : Colors.white,
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
              // Count badge (if more than 1 announcement)
              if (count > 1)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: parentGreen,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? backgroundDark : Colors.white,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(minWidth: 20),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Teacher name (truncated to first name)
          SizedBox(
            width: 68,
            child: Text(
              teacherName.split(' ').first,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                color: isUnread
                    ? parentGreen
                    : (isDark ? Colors.grey[400] : Colors.grey[700]),
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

  /// Show announcement details in a dialog or bottom sheet
  void _showAnnouncementDetails(Map<String, dynamic> announcement) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? backgroundDark : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: parentGreen.withOpacity(0.1),
                child: Text(
                  announcement['teacherInitial'],
                  style: const TextStyle(
                    color: parentGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement['teacherName'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                    Text(
                      announcement['date'],
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                announcement['title'],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                announcement['description'],
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: parentGreen)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPerformanceSummary(bool isDark, Map<String, dynamic> child) {
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
                color: isDark ? Colors.white : textPrimary,
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
                  value: child['rewards'].toString(),
                  label: 'Rewards',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.history_edu,
                  value: child['testsAttended'].toString(),
                  label: 'Tests Attended',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.task_alt,
                  value: '${child['attendance']}%',
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
        color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
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
              color: isDark ? Colors.white : textPrimary,
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

  Widget _buildRewardRequests(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 32, bottom: 12),
            child: Text(
              'Reward Requests',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
          ),

          // Reward Requests List
          ..._rewardRequests.map((request) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
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
                    child: Icon(request['icon'], color: parentGreen, size: 24),
                  ),
                  const SizedBox(width: 16),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request['title'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request['description'],
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Approve Button
                  ElevatedButton(
                    onPressed: () {
                      // Handle approve
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: parentGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Approve',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTeacherMessages(bool isDark) {
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
                    color: isDark ? Colors.white : textPrimary,
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
          ..._teacherMessages.map((message) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
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
                  // Teacher Profile Picture
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: parentGreen.withOpacity(0.2),
                      image: DecorationImage(
                        image: NetworkImage(message['image']),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Message Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message['name'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message['message'],
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
