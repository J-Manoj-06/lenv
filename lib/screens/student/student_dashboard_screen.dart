import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/student_provider.dart';
import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../models/status_model.dart';
import '../../models/student_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/parent_service.dart';
import '../../widgets/daily_challenge_card.dart';
import '../teacher/status_view_screen.dart';
import '../../widgets/achievement_section.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure auth restored (FirebaseAuth currentUser) before loading data.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.ensureInitialized();
      // If still unauthenticated after restore attempt, stay; router can handle redirect.
      await _loadDashboardData();
    });
  }

  Future<void> _loadDashboardData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    // Attempt one more lazy re-init if user is null (cold start race condition)
    if (authProvider.currentUser == null && !authProvider.isLoading) {
      await authProvider.initializeAuth();
    }
    if (authProvider.currentUser == null) {
      // User truly not logged in; skip loading (UI will reflect auth state elsewhere)
      return;
    }

    // Process any ended tests to award pending points
    try {
      await FirestoreService().processEndedTests();
    } catch (e) {
      print('⚠️ Error processing ended tests: $e');
    }

    await studentProvider.loadDashboardData(authProvider.currentUser!.uid);
  }

  // Navigation handled by shared StudentBottomNav widget.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        if (studentProvider.isLoading &&
            studentProvider.currentStudent == null) {
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF27F0D)),
              ),
            ),
          );
        }

        final student = studentProvider.currentStudent;
        final authUser = Provider.of<AuthProvider>(context).currentUser;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: RefreshIndicator(
            onRefresh: _loadDashboardData,
            color: const Color(0xFFF27F0D),
            child: SafeArea(
              child: Column(
                children: [
                  // Top App Bar
                  _buildTopAppBar(theme, student, authUser),

                  // Scrollable Content
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Announcements Section
                          if (student != null)
                            _buildAnnouncementsSection(theme, student),
                          // Removed duplicate progress subtitle (already shown in top app bar)
                          // _buildProgressText(theme),
                          _buildPointsCard(theme, student),
                          // Daily Challenge Card
                          if (student != null)
                            DailyChallengeCard(
                              studentId: student.uid,
                              studentEmail: student.email,
                            ),
                          _buildActiveTestsSection(theme),
                          _buildPerformanceSection(theme, student),
                          _buildRewardsSection(theme, student),
                          _buildAchievementsSection(theme),
                          const SizedBox(height: 80),
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
    );
  }

  Widget _buildTopAppBar(ThemeData theme, student, authUser) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi, ${student?.name?.split(' ').first ?? authUser?.email?.split('@').first ?? 'Student'} 👋',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Here’s your progress for today",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFB0B0B0),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/student-profile'),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: student?.photoUrl != null
                    ? DecorationImage(
                        image: NetworkImage(student!.photoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: student?.photoUrl == null
                    ? const Color(0xFFFF8A00)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: student?.photoUrl == null
                  ? const Icon(Icons.person, color: Colors.white, size: 28)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsCard(ThemeData theme, student) {
    if (student == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFF8A00), Color(0xFFFF9E2E)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Points',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '--',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Rank: --',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.military_tech, size: 70, color: Colors.white54),
            ],
          ),
        ),
      );
    }

    // Aggregate all points from student_rewards collection (tests + daily challenges)
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('student_rewards')
          .where('studentId', isEqualTo: student.uid)
          .snapshots(),
      builder: (context, rewardsSnapshot) {
        int rewardPoints = 0;

        // Sum all pointsEarned from student_rewards (tests + daily challenges)
        if (rewardsSnapshot.hasData) {
          for (final doc in rewardsSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data != null) {
              final points = data['pointsEarned'];
              if (points is int) {
                rewardPoints += points;
              } else if (points is num) {
                rewardPoints += points.toInt();
              }
            }
          }
        }

        // Calculate rank dynamically based on class
        return FutureBuilder<int?>(
          future: _calculateClassRank(
            student.uid,
            student.className,
            rewardPoints,
          ),
          builder: (context, rankSnapshot) {
            final rank = rankSnapshot.data ?? student.classRank;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFFFF8A00), Color(0xFFFF9E2E)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Points',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$rewardPoints',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          rank > 0 ? 'Rank: #$rank' : 'Rank: --',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const Icon(
                      Icons.military_tech,
                      size: 70,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<int?> _calculateClassRank(
    String uid,
    String? className,
    int rewardPoints,
  ) async {
    if (className == null || className.isEmpty) return null;

    try {
      // Get all students in the same class
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('className', isEqualTo: className)
          .where('role', isEqualTo: 'student')
          .get();

      if (snapshot.docs.isEmpty) return null;

      // Sort by reward points descending
      final students = snapshot.docs.map((doc) {
        final data = doc.data();
        return {'uid': doc.id, 'rewardPoints': data['rewardPoints'] ?? 0};
      }).toList();

      students.sort(
        (a, b) =>
            (b['rewardPoints'] as int).compareTo(a['rewardPoints'] as int),
      );

      // Find this student's rank
      for (int i = 0; i < students.length; i++) {
        if (students[i]['uid'] == uid) {
          return i + 1; // 1-based rank
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Widget _buildActiveTestsSection(ThemeData theme) {
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    final student = studentProvider.currentStudent;
    if (student == null) {
      return SizedBox.shrink();
    }
    final studentId = student.uid;
    final resultsStream = FirestoreService().getTestResultsByStudent(studentId);
    return StreamBuilder<List<TestResultModel>>(
      stream: resultsStream,
      builder: (context, resultsSnap) {
        final completedTestIds = <String>{
          if (resultsSnap.hasData) ...resultsSnap.data!.map((r) => r.testId),
        };
        return StreamBuilder<List<TestModel>>(
          stream: FirestoreService().getAvailableTestsForStudent(
            studentId,
            studentEmail: student.email,
          ),
          builder: (context, testsSnap) {
            if (resultsSnap.connectionState == ConnectionState.waiting ||
                testsSnap.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final tests = testsSnap.data ?? [];
            final now = DateTime.now();
            final liveUnattempted = tests.where((t) {
              final inWindow =
                  !t.startDate.isAfter(now) && !t.endDate.isBefore(now);
              final notAttempted = !completedTestIds.contains(t.id);
              return inWindow && notAttempted;
            }).toList();

            if (liveUnattempted.isEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'No live tests available. Assigned tests will appear here when active and not attempted.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text(
                    'Your Active Tests 📘',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...liveUnattempted.map(
                  (test) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF27F0D).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.calculate,
                              color: Color(0xFFF27F0D),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  test.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Duration: ${test.duration} minutes',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              '/student-tests',
                              arguments: test,
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFF27F0D)),
                              foregroundColor: const Color(0xFFF27F0D),
                            ),
                            child: const Text('Start Test'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPerformanceSection(ThemeData theme, student) {
    if (student == null) {
      return SizedBox.shrink();
    }

    return StreamBuilder<List<TestResultModel>>(
      stream: FirestoreService().getTestResultsByStudent(student.uid),
      builder: (context, snapshot) {
        // Calculate real performance metrics
        int testsTaken = 0;
        double avgScore = 0.0;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final results = snapshot.data!;
          testsTaken = results.length;

          // Calculate average score (score field is already a percentage)
          double totalScore = 0.0;
          for (var result in results) {
            totalScore += result.score; // 0-100
          }
          avgScore = testsTaken > 0 ? totalScore / testsTaken : 0.0;
        }

        // Fetch attendance percentage for the student
        return FutureBuilder<double>(
          future: ParentService().getStudentAttendance(student.uid),
          builder: (context, attSnap) {
            final attendancePct = (attSnap.data ?? 0.0).clamp(0.0, 100.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
                  child: const Text(
                    'Your Performance 📊',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 20,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _performanceCell(
                            testsTaken > 0
                                ? '${avgScore.toStringAsFixed(0)}%'
                                : '-',
                            'Avg. Score',
                            highlight: true,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 46,
                          color: Colors.white.withOpacity(0.1),
                        ),
                        Expanded(
                          child: _performanceCell('$testsTaken', 'Tests Taken'),
                        ),
                        Container(
                          width: 1,
                          height: 46,
                          color: Colors.white.withOpacity(0.1),
                        ),
                        Expanded(
                          child: _performanceCell(
                            attSnap.connectionState == ConnectionState.waiting
                                ? '--%'
                                : '${attendancePct.toStringAsFixed(0)}%',
                            'Attendance',
                            highlight: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _performanceCell(
    String value,
    String label, {
    bool highlight = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: highlight ? const Color(0xFFFF8A00) : Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFFB0B0B0),
          ),
        ),
      ],
    );
  }

  Widget _buildRewardsSection(ThemeData theme, student) {
    if (student == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rewards 🎁',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Points',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '0',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFF27F0D),
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/student-rewards'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF27F0D).withOpacity(0.2),
                      foregroundColor: const Color(0xFFF27F0D),
                      elevation: 0,
                    ),
                    child: const Text('View'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Stream the user document to get real-time reward points
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(student.uid)
          .snapshots(),
      builder: (context, snapshot) {
        int rewardPoints = student.rewardPoints;

        if (snapshot.hasData && snapshot.data != null) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('rewardPoints')) {
            rewardPoints = data['rewardPoints'] ?? 0;
          }
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rewards 🎁',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Points',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$rewardPoints',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFF27F0D),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/student-rewards'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFFF27F0D,
                        ).withOpacity(0.2),
                        foregroundColor: const Color(0xFFF27F0D),
                        elevation: 0,
                      ),
                      child: const Text('View'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAchievementsSection(ThemeData theme) {
    // Replace previous static achievements with real earned badges
    final student = Provider.of<StudentProvider>(
      context,
      listen: false,
    ).currentStudent;
    if (student == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            'Your Achievements 🏅',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ),
        // Real achievements fetched from Firestore badges array
        // Achievements list
        // ignore: prefer_const_constructors
        AchievementSection(studentId: student.uid),
      ],
    );
  }

  // Bottom nav is centralized in StudentBottomNav widget.

  /// Build announcements section with beautiful card design
  Widget _buildAnnouncementsSection(ThemeData theme, StudentModel student) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUser?.uid ?? '';

    // Get school identifier - USE SCHOOLCODE FIRST (like "OAK001")!
    final schoolIdentifier =
        student.schoolCode ?? // PRIMARY: schoolCode from Firestore
        student.schoolId ?? // Fallback: old schoolId if exists
        student.schoolName ?? // Last resort: full name
        '';

    // Check if we have any valid identifier
    if (schoolIdentifier.isEmpty) {
      return _buildErrorCard(
        theme,
        '⚠️ Configuration Issue',
        'Your school information is missing. Please contact your administrator to update your profile in the system.',
      );
    }

    // Use FutureBuilder to fetch section if needed
    return FutureBuilder<Map<String, String>>(
      future: _parseStudentInfo(student),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final userStandard = snapshot.data!['standard'] ?? '';
        final userSection = snapshot.data!['section'] ?? '';

        return _buildAnnouncementsStream(
          theme,
          student,
          schoolIdentifier,
          currentUserId,
          userStandard,
          userSection,
        );
      },
    );
  }

  /// Parse student's className and fetch section from Firestore if needed
  Future<Map<String, String>> _parseStudentInfo(StudentModel student) async {
    String userStandard = '';
    String userSection = '';

    // First, check if section is directly available in StudentModel
    if (student.section != null && student.section!.isNotEmpty) {
      userSection = student.section!.trim();
    }

    if (student.className != null && student.className!.isNotEmpty) {
      final className = student.className!;

      // Handle formats like "Grade 10 - A" or "Grade 10-A"
      if (className.contains('-')) {
        final parts = className.split('-').map((e) => e.trim()).toList();
        if (parts.length == 2) {
          userStandard = parts[0]
              .replaceAll('Grade', '')
              .replaceAll('grade', '')
              .trim();
          userSection = parts[1].trim();
        }
      }
      // Handle format like "Grade 10" (no section in className, fetch from Firestore)
      else if (className.toLowerCase().contains('grade')) {
        userStandard = className
            .replaceAll('Grade', '')
            .replaceAll('grade', '')
            .trim();
      }
      // Handle format like "10A"
      else {
        final match = RegExp(r'^(\d+)([A-Z])$').firstMatch(className);
        if (match != null) {
          userStandard = match.group(1) ?? '';
          userSection = match.group(2) ?? '';
        } else {
          userStandard = className.trim();
        }
      }
    }

    // If section is still empty, fetch it from the student document in Firestore
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

    print(
      '📊 Student Info - Standard: "$userStandard", Section: "$userSection"',
    );
    print('   className: "${student.className}"');

    return {'standard': userStandard, 'section': userSection};
  }

  /// Build the actual announcements stream widget
  Widget _buildAnnouncementsStream(
    ThemeData theme,
    StudentModel student,
    String schoolIdentifier,
    String currentUserId,
    String userStandard,
    String userSection,
  ) {
    print('   schoolCode: "$schoolIdentifier"');

    // TEMPORARY FIX: If schoolIdentifier is empty or doesn't match, query ALL announcements
    // and filter client-side. This helps diagnose the issue.
    final hasValidSchoolId = schoolIdentifier.isNotEmpty;

    return StreamBuilder<QuerySnapshot>(
      stream: hasValidSchoolId
          ? FirebaseFirestore.instance
                .collection('class_highlights')
                .where('instituteId', isEqualTo: schoolIdentifier)
                .where('expiresAt', isGreaterThan: Timestamp.now())
                .orderBy('expiresAt', descending: false)
                .orderBy('createdAt', descending: true)
                .limit(10)
                .snapshots()
          : FirebaseFirestore.instance
                .collection('class_highlights')
                .where('expiresAt', isGreaterThan: Timestamp.now())
                .orderBy('expiresAt', descending: false)
                .orderBy('createdAt', descending: true)
                .limit(10)
                .snapshots(),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildAnnouncementsLoadingCard(theme);
        }

        // Parse and filter announcements
        final allAnnouncements = snapshot.hasData
            ? snapshot.data!.docs
                  .map((doc) {
                    final announcement = StatusModel.fromFirestore(doc);
                    return announcement;
                  })
                  .where((announcement) {
                    // Show only teacher-posted announcements
                    final fromTeacher = announcement.teacherId.isNotEmpty;
                    if (!fromTeacher) return false;

                    // If we're querying all, also check instituteId matches
                    final sameInstitute =
                        !hasValidSchoolId ||
                        announcement.instituteId == schoolIdentifier;
                    if (!sameInstitute) return false;

                    final isVisible = announcement.isVisibleTo(
                      userStandard: userStandard,
                      userSection:
                          userSection, // Pass just the section letter (e.g., 'A')
                    );
                    return isVisible;
                  })
                  .toList()
            : <StatusModel>[];

        // Only show announcements section if there are teacher announcements
        if (allAnnouncements.isEmpty) {
          return const SizedBox.shrink();
        }
        return _buildAnnouncementsHorizontalRow(
          theme,
          allAnnouncements,
          currentUserId,
        );
      },
    );
  }

  /// Build horizontal scrollable row of announcements (WhatsApp-style)
  Widget _buildAnnouncementsHorizontalRow(
    ThemeData theme,
    List<StatusModel> announcements,
    String currentUserId,
  ) {
    // Group announcements by teacherId
    final Map<String, List<StatusModel>> groupedByTeacher = {};
    for (final announcement in announcements) {
      final teacherId = announcement.teacherId;
      if (!groupedByTeacher.containsKey(teacherId)) {
        groupedByTeacher[teacherId] = [];
      }
      groupedByTeacher[teacherId]!.add(announcement);
    }

    // Convert to list of teacher groups (sorted by most recent announcement)
    final teacherGroups = groupedByTeacher.entries.map((entry) {
      final teacherAnnouncements = entry.value;
      // Sort announcements by creation time (newest first)
      teacherAnnouncements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return teacherAnnouncements;
    }).toList();

    // Sort teacher groups by their most recent announcement
    teacherGroups.sort(
      (a, b) => b.first.createdAt.compareTo(a.first.createdAt),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF27F0D).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.campaign,
                  color: Color(0xFFF27F0D),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '📢 Announcements',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),

        // Horizontal scrollable list
        SizedBox(
          height: 100,
          child: teacherGroups.isEmpty
              ? _buildEmptyAnnouncementsList(theme)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: teacherGroups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final teacherAnnouncements = teacherGroups[index];
                    final latestAnnouncement = teacherAnnouncements.first;

                    // Check if ANY announcement from this teacher is unread
                    final hasUnread = teacherAnnouncements.any(
                      (a) => !a.viewedBy.contains(currentUserId),
                    );

                    return _buildAnnouncementAvatar(
                      theme,
                      latestAnnouncement,
                      hasUnread,
                      () {
                        _openAnnouncementViewer(teacherAnnouncements, 0);
                      },
                      announcementCount: teacherAnnouncements.length,
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Empty announcements list (shows placeholder message)
  Widget _buildEmptyAnnouncementsList(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 32, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'No announcements yet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual announcement avatar (circular with gradient border)
  Widget _buildAnnouncementAvatar(
    ThemeData theme,
    StatusModel announcement,
    bool isUnread,
    VoidCallback onTap, {
    int announcementCount = 1, // Number of announcements from this teacher
  }) {
    return GestureDetector(
      onTap: onTap,
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
                          colors: [Color(0xFFFFA726), Color(0xFFF27F0D)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: !isUnread
                      ? Border.all(color: Colors.grey[300]!, width: 2)
                      : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.scaffoldBackgroundColor,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFFFF5EB),
                    child: Text(
                      announcement.teacherName.isNotEmpty
                          ? announcement.teacherName[0].toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF27F0D),
                      ),
                    ),
                  ),
                ),
              ),
              // Count badge (if more than 1 announcement)
              if (announcementCount > 1)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF27F0D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.scaffoldBackgroundColor,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(minWidth: 20),
                    child: Text(
                      '$announcementCount',
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
          // Teacher name (truncated)
          SizedBox(
            width: 68,
            child: Text(
              announcement.teacherName.split(' ').first,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                color: isUnread
                    ? const Color(0xFFF27F0D)
                    : theme.textTheme.bodySmall?.color,
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

  /// Open announcement viewer (full-screen status viewer)
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

  /// Loading state for horizontal row
  Widget _buildAnnouncementsLoadingCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF27F0D).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.campaign,
                  color: Color(0xFFF27F0D),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '� Announcements',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),

        // Shimmer loading circles
        SizedBox(
          height: 100,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[300],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 50,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Error state card for configuration issues
  Widget _buildErrorCard(ThemeData theme, String title, String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red[300]!, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.red[700],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red[900],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.red[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '🔍 Check console logs for technical details',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red[700],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Press-to-scale wrapper used by badges
// Removed unused helper widgets and legacy stat/progress builders.
