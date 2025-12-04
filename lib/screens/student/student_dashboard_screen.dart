import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/student_provider.dart';
import '../../providers/daily_challenge_provider.dart';
import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../models/status_model.dart';
import '../../models/student_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/parent_service.dart';
import '../teacher/status_view_screen.dart';
import 'daily_challenge_screen.dart';
import 'student_profile_screen.dart';
import '../ai/ai_chat_page.dart';
import 'dart:math' as math;

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.ensureInitialized();
      await _loadDashboardData();
      // Mark initialization complete
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });
  }

  Future<void> _loadDashboardData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
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
    if (authProvider.currentUser == null) {
      print('❌ No authenticated user found');
      return;
    }

    final userId = authProvider.currentUser!.uid;
    print('✅ Loading dashboard for user: $userId');

    try {
      await FirestoreService().processEndedTests();
    } catch (e) {
      print('⚠️ Error processing ended tests: $e');
    }

    // CRITICAL: Initialize daily challenge BEFORE loading student data
    // This ensures challenge state is ready when dashboard renders
    print('🎯 Initializing daily challenge for user: $userId');
    await dailyChallengeProvider.initialize(userId);
    print(
      '✅ Daily challenge initialized. Has answered: ${dailyChallengeProvider.hasAnsweredToday(userId)}',
    );

    // Load student data (with cache integration)
    await studentProvider.loadDashboardData(userId);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        // Show fetching screen while initializing OR loading student data
        if (_isInitializing ||
            studentProvider.isLoading ||
            studentProvider.currentStudent == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF16171A),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFF2800D),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Fetching your details...',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }

        final student = studentProvider.currentStudent;
        final authUser = Provider.of<AuthProvider>(context).currentUser;

        return Scaffold(
          backgroundColor: const Color(0xFF16171A),
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
            backgroundColor: const Color(0xFFF2800D),
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

    return Container(
      color: const Color(0xFF16171A),
      child: Column(
        children: [
          const SizedBox(height: 64),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi, $firstName 👋',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Here's your progress for today",
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFFE5E5E5),
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
                    const SizedBox(width: 12),
                    _buildProfileIcon(),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF2800D).withOpacity(0.2),
            borderRadius: BorderRadius.circular(24),
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
                  fontSize: 16,
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
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2C2C2E), width: 1),
        ),
        child: const Icon(Icons.person_outline, color: Colors.white, size: 24),
      ),
    );
  }

  // Announcements Section (WhatsApp-style)
  Widget _buildAnnouncementsSection(StudentModel student) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
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

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('class_highlights')
              .where('instituteId', isEqualTo: schoolIdentifier)
              .where('expiresAt', isGreaterThan: Timestamp.now())
              .orderBy('expiresAt', descending: false)
              .orderBy('createdAt', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, announcementSnapshot) {
            if (announcementSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const SizedBox.shrink();
            }

            final announcements = announcementSnapshot.hasData
                ? announcementSnapshot.data!.docs
                      .map((doc) => StatusModel.fromFirestore(doc))
                      .where(
                        (a) =>
                            a.teacherId.isNotEmpty &&
                            a.isVisibleTo(
                              userStandard: userStandard,
                              userSection: userSection,
                            ),
                      )
                      .toList()
                : <StatusModel>[];

            if (announcements.isEmpty) return const SizedBox.shrink();

            return _buildAnnouncementsRow(announcements, currentUserId);
          },
        );
      },
    );
  }

  Widget _buildAnnouncementsRow(
    List<StatusModel> announcements,
    String currentUserId,
  ) {
    final Map<String, List<StatusModel>> groupedByTeacher = {};
    for (final announcement in announcements) {
      groupedByTeacher
          .putIfAbsent(announcement.teacherId, () => [])
          .add(announcement);
    }

    final teacherGroups = groupedByTeacher.entries.map((entry) {
      final list = entry.value;
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }).toList();

    teacherGroups.sort(
      (a, b) => b.first.createdAt.compareTo(a.first.createdAt),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.campaign, color: Color(0xFFF2800D), size: 20),
              SizedBox(width: 8),
              Text(
                '📢 Announcements',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 8),
            scrollDirection: Axis.horizontal,
            itemCount: teacherGroups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final teacherAnnouncements = teacherGroups[index];
              final latest = teacherAnnouncements.first;
              final hasUnread = teacherAnnouncements.any(
                (a) => !a.viewedBy.contains(currentUserId),
              );

              return _buildAnnouncementAvatar(
                latest,
                hasUnread,
                () => _openAnnouncementViewer(teacherAnnouncements, 0),
                count: teacherAnnouncements.length,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementAvatar(
    StatusModel announcement,
    bool isUnread,
    VoidCallback onTap, {
    int count = 1,
  }) {
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
                      ? Border.all(color: Colors.grey[700]!, width: 2)
                      : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF16171A),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFFFF5EB),
                    child: Text(
                      announcement.teacherName.isNotEmpty
                          ? announcement.teacherName[0].toUpperCase()
                          : 'T',
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
                        color: const Color(0xFF16171A),
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
              announcement.teacherName.isNotEmpty
                  ? announcement.teacherName.split(' ').first
                  : 'Teacher',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                color: isUnread ? const Color(0xFFF2800D) : Colors.white70,
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

  void _openAnnouncementViewer(
    List<StatusModel> announcements,
    int initialIndex,
  ) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUser?.uid ?? '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatusViewScreen(
          statuses: announcements,
          initialIndex: initialIndex,
          currentUserId: currentUserId,
        ),
      ),
    );
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

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Topper: $topperPoints pts',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFBBBBBB),
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
              width: 150,
              height: 150,
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
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.white24, blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'POINTS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFBBBBBB),
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
      // Get all students from same school and class
      Query query = FirebaseFirestore.instance.collection('users');

      if (student.schoolId != null) {
        query = query.where('schoolId', isEqualTo: student.schoolId);
      }
      if (student.className != null) {
        query = query.where('className', isEqualTo: student.className);
      }

      query = query.where('role', isEqualTo: 'student');

      final snapshot = await query.get();

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

      return maxPoints;
    } catch (e) {
      debugPrint('Error getting topper points: $e');
      return 0;
    }
  }

  Widget _buildEmptyPointsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.stars, size: 60, color: Colors.white24),
          SizedBox(height: 12),
          Text(
            'No points yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _calculateStreakDays(String studentId) async {
    // Placeholder - implement actual streak calculation
    return 4;
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: hasAnswered
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A2A2A), Color(0xFF1C1C1E)],
                    ),
              color: hasAnswered
                  ? (isCorrect
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : const Color(0xFFEF5350).withOpacity(0.1))
                  : null,
              borderRadius: BorderRadius.circular(16),
              border: hasAnswered
                  ? Border.all(
                      color: isCorrect
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFEF5350),
                      width: 2,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
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
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: hasAnswered
                        ? (isCorrect
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFEF5350))
                        : Colors.white,
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
                        : Colors.white70,
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
                      color: const Color(0xFFFF8E24),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text(
                      'Take Challenge',
                      style: TextStyle(
                        color: Color(0xFF23190F),
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
                const Text(
                  'Assigned Test',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
                    color: const Color(0xFFF2800D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Due Today',
                    style: TextStyle(
                      color: Colors.white,
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
              const Icon(Icons.access_time, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                'Due Today, ${_formatTime(test.endDate)}',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Questions count
          Row(
            children: [
              const Icon(
                Icons.article_outlined,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${test.questions.length} Questions',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
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
                backgroundColor: const Color(0xFFF2800D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final testDate = DateTime(date.year, date.month, date.day);

    if (testDate == today) {
      return 'Today, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (testDate == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
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
            const Text(
              'Performance',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
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
                        width: 120,
                        height: 120,
                        child: CustomPaint(
                          painter: CircularProgressPainter(
                            progress: avgScore / 100,
                            strokeWidth: 12,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${avgScore.toInt()}%',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Colors.white24, blurRadius: 8),
                              ],
                            ),
                          ),
                          const Text(
                            'Avg. Score',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
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
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.white24, blurRadius: 8),
                          ],
                        ),
                      ),
                      const Text(
                        'Tests Taken',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
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
            const Text(
              'Attendance',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
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
                            strokeWidth: 12,
                            color: const Color(0xFF81C784),
                            backgroundColor: const Color(
                              0xFFEF5350,
                            ).withOpacity(0.3),
                          ),
                        ),
                      ),
                      Text(
                        '${attendancePct.toInt()}%',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
                            decoration: const BoxDecoration(
                              color: Color(0xFF81C784),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$presentDays Days Present',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
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
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF5350),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$absentDays Days Absent',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
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

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchEarnedBadges(student.uid),
      builder: (context, snapshot) {
        final earnedBadges = snapshot.data ?? [];

        // Sample badges for display
        final badges = [
          {
            'icon': Icons.school,
            'label': 'Scholar',
            'color': const Color(0xFFBA68C8),
            'earned': earnedBadges.length > 0,
          },
          {
            'icon': Icons.local_fire_department,
            'label': 'Streak',
            'color': const Color(0xFFFFB26B),
            'earned': earnedBadges.length > 1,
          },
          {
            'icon': Icons.military_tech,
            'label': 'Achiever',
            'color': const Color(0xFF64B5F6),
            'earned': earnedBadges.length > 2,
          },
          {
            'icon': Icons.lock,
            'label': 'Locked',
            'color': Colors.white24,
            'earned': false,
          },
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Badges Earned',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: badges
                  .map(
                    (badge) => _buildBadge(
                      badge['icon'] as IconData,
                      badge['label'] as String,
                      badge['color'] as Color,
                      badge['earned'] as bool,
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color, bool earned) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            shape: BoxShape.circle,
            boxShadow: earned
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: earned ? Colors.white : Colors.white38,
            size: 32,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: earned ? Colors.white70 : Colors.white38,
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _fetchEarnedBadges(
    String studentId,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('student_badges')
          .doc(studentId)
          .get();
      return (doc.data()?['badges'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
    } catch (e) {
      return [];
    }
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
