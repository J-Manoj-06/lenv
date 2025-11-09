import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/student_provider.dart';
import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../models/status_model.dart';
import '../../models/student_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/daily_challenge_card.dart';
import '../teacher/status_view_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({Key? key}) : super(key: key);

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  @override
  void initState() {
    super.initState();

    // Load Firebase data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardData();
    });
  }

  Future<void> _loadDashboardData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );

    if (authProvider.currentUser != null) {
      await studentProvider.loadDashboardData(authProvider.currentUser!.uid);
    }
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
                          _buildProgressText(theme),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Hi, ${student?.name?.split(' ').first ?? authUser?.email?.split('@').first ?? 'Brooklyn'} 👋',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/student-profile'),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: student?.photoUrl != null
                    ? DecorationImage(
                        image: NetworkImage(student!.photoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: student?.photoUrl == null
                    ? const Color(0xFFF27F0D)
                    : null,
              ),
              child: student?.photoUrl == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressText(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        "Here's your progress for today",
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.textTheme.bodySmall?.color,
        ),
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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFCC6600), Color(0xFFF27F0D)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF27F0D).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Points',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '--',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rank: --',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.military_tech,
                size: 56,
                color: Colors.white.withOpacity(0.4),
              ),
            ],
          ),
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
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFCC6600), Color(0xFFF27F0D)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF27F0D).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Points',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$rewardPoints',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rank > 0 ? 'Rank: #$rank' : 'Rank: --',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.military_tech,
                      size: 56,
                      color: Colors.white.withOpacity(0.4),
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
        double accuracy = 0.0;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final results = snapshot.data!;
          testsTaken = results.length;

          // Calculate average score (score field is already a percentage)
          double totalScore = 0.0;
          int totalCorrect = 0;
          int totalQuestions = 0;

          for (var result in results) {
            // score is already stored as a percentage value (0-100)
            totalScore += result.score;
            totalCorrect += result.correctAnswers;
            totalQuestions += result.totalQuestions;
          }

          avgScore = testsTaken > 0 ? totalScore / testsTaken : 0.0;
          accuracy = totalQuestions > 0
              ? (totalCorrect / totalQuestions) * 100
              : 0.0;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
              child: Text(
                'Your Performance 📊',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildPerformanceStat(
                        theme,
                        testsTaken > 0
                            ? '${avgScore.toStringAsFixed(0)}%'
                            : '-',
                        'Avg. Score',
                      ),
                      _buildPerformanceStat(
                        theme,
                        '$testsTaken',
                        'Tests Taken',
                      ),
                      _buildPerformanceStat(
                        theme,
                        testsTaken > 0
                            ? '${accuracy.toStringAsFixed(0)}%'
                            : '-',
                        'Accuracy',
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
  }

  Widget _buildPerformanceStat(ThemeData theme, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: value.contains('%') ? const Color(0xFFF27F0D) : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color,
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
    final isDark = theme.brightness == Brightness.dark;

    // Lottie (first 5) + Icon badges (next 5)
    final lottieBadges = [
      (
        title: 'Top Performer',
        subtitle: 'Scored 90%+ in tests',
        url: 'https://assets9.lottiefiles.com/packages/lf20_awc77jfz.json',
      ),
      (
        title: 'Streak Master',
        subtitle: '7-day learning streak',
        url: 'https://assets10.lottiefiles.com/packages/lf20_jbrw3hcz.json',
      ),
      (
        title: 'Quiz Champ',
        subtitle: 'Perfect quiz score',
        url: 'https://assets2.lottiefiles.com/packages/lf20_myejiggj.json',
      ),
      (
        title: 'Daily Solver',
        subtitle: 'Daily challenge completed',
        url: 'https://assets1.lottiefiles.com/packages/lf20_tz1zby.json',
      ),
      (
        title: 'Consistent Learner',
        subtitle: 'Learning 5 days/week',
        url: 'https://assets8.lottiefiles.com/packages/lf20_q5pk6p1k.json',
      ),
    ];

    final iconBadges = [
      (
        title: 'Creative Thinker',
        subtitle: 'Out-of-the-box ideas',
        icon: Icons.lightbulb_outline,
      ),
      (
        title: 'Fast Finisher',
        subtitle: 'Finished ahead of time',
        icon: Icons.timer,
      ),
      (
        title: 'Goal Reacher',
        subtitle: 'Hit your monthly target',
        icon: Icons.flag_circle,
      ),
      (
        title: 'Dedicated Learner',
        subtitle: 'Practice makes perfect',
        icon: Icons.auto_graph,
      ),
      (
        title: 'Helpful Mate',
        subtitle: 'Helped a classmate',
        icon: Icons.volunteer_activism,
      ),
    ];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: Column(
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
              SizedBox(
                height: 180,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemCount: lottieBadges.length + iconBadges.length,
                  itemBuilder: (context, index) {
                    final bool isLottie = index < lottieBadges.length;
                    final bgColor = isDark
                        ? const Color(0xFF221910)
                        : Colors.white;
                    final borderColor = const Color(
                      0xFFF27F0D,
                    ).withOpacity(0.35);

                    Widget media;
                    String title;
                    String subtitle;

                    if (isLottie) {
                      final item = lottieBadges[index];
                      title = item.title;
                      subtitle = item.subtitle;
                      media = Lottie.network(
                        item.url,
                        width: 100,
                        height: 100,
                        repeat: true,
                        frameRate: FrameRate.max,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback to icon on network error
                          return Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF27F0D).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.emoji_events,
                              size: 48,
                              color: Color(0xFFF27F0D),
                            ),
                          );
                        },
                      );
                    } else {
                      final item = iconBadges[index - lottieBadges.length];
                      title = item.title;
                      subtitle = item.subtitle;
                      media = Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF27F0D).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.icon,
                          size: 48,
                          color: const Color(0xFFF27F0D),
                        ),
                      );
                    }

                    return _PressScale(
                      scale: 1.05,
                      child: Container(
                        width: 150,
                        height: 180,
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderColor, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF27F0D).withOpacity(0.25),
                              blurRadius: 16,
                              spreadRadius: 0,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            media,
                            const SizedBox(height: 10),
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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

    // Parse student's className to extract standard and section
    String userStandard = '';
    String userSection = '';

    if (student.className != null && student.className!.isNotEmpty) {
      final className = student.className!;

      if (className.contains('-')) {
        final parts = className.split('-').map((e) => e.trim()).toList();
        if (parts.length == 2) {
          userStandard = parts[0].replaceAll('Grade', '').trim();
          userSection = parts[1].trim();
        }
      } else if (className.contains(' ')) {
        userStandard = className.replaceAll('Grade', '').trim();
      } else {
        final match = RegExp(r'^(\d+)([A-Z])$').firstMatch(className);
        if (match != null) {
          userStandard = match.group(1) ?? '';
          userSection = match.group(2) ?? '';
        } else {
          userStandard = className;
        }
      }
    }

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
                    // If we're querying all, also check instituteId matches
                    if (!hasValidSchoolId ||
                        announcement.instituteId == schoolIdentifier) {
                      final isVisible = announcement.isVisibleTo(
                        userStandard: userStandard,
                        userSection: '$userStandard$userSection',
                      );
                      return isVisible;
                    }
                    return false;
                  })
                  .toList()
            : <StatusModel>[];

        // Show horizontal list (always visible, even if empty)
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
          child: announcements.isEmpty
              ? _buildEmptyAnnouncementsList(theme)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: announcements.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final announcement = announcements[index];
                    final isUnread = !announcement.viewedBy.contains(
                      currentUserId,
                    );
                    return _buildAnnouncementAvatar(
                      theme,
                      announcement,
                      isUnread,
                      () {
                        _openAnnouncementViewer(announcements, index);
                      },
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
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with gradient border if unread
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
class _PressScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const _PressScale({required this.child, this.scale = 1.05});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  void _set(bool v) => setState(() => _pressed = v);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
