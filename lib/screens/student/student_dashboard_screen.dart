import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../../providers/student_provider.dart';
import '../../providers/auth_provider.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({Key? key}) : super(key: key);

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _floatController1;
  late AnimationController _floatController2;
  late AnimationController _floatController3;
  late AnimationController _floatController4;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();

    // Float animations for background icons
    _floatController1 = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _floatController2 = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _floatController3 = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _floatController4 = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    // Progress bar animation
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Load Firebase data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDashboardData();
    });

    // Start progress animation
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _progressController.forward();
      }
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

  @override
  void dispose() {
    _floatController1.dispose();
    _floatController2.dispose();
    _floatController3.dispose();
    _floatController4.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _onNavItemTapped(int index) {
    setState(() => _selectedIndex = index);

    // Navigate based on index
    switch (index) {
      case 0: // Home - already here
        break;
      case 1: // Tests
        Navigator.pushNamed(context, '/student-tests');
        break;
      case 2: // Rewards
        Navigator.pushNamed(context, '/student-rewards');
        break;
      case 3: // Leaderboard
        Navigator.pushNamed(context, '/student-leaderboard');
        break;
      case 4: // Profile
        Navigator.pushNamed(context, '/student-profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        if (studentProvider.isLoading &&
            studentProvider.currentStudent == null) {
          return Scaffold(
            backgroundColor: isDark
                ? const Color(0xFF111827)
                : const Color(0xFFF3F4F6),
            body: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
              ),
            ),
          );
        }

        final student = studentProvider.currentStudent;

        return Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF111827)
              : const Color(0xFFF3F4F6),
          body: RefreshIndicator(
            onRefresh: () => _loadDashboardData(),
            color: const Color(0xFFF59E0B),
            child: Stack(
              children: [
                // Background floating icons
                _buildFloatingBackground(),

                // Main content
                SafeArea(
                  child: Column(
                    children: [
                      // Header
                      _buildHeader(isDark, student),

                      // Scrollable content
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Welcome text
                              _buildWelcomeText(
                                isDark,
                                student?.name ?? 'Student',
                              ),

                              // Search Rewards CTA
                              _buildSearchRewardsCTA(isDark),

                              // Daily Challenge Card
                              if (studentProvider.todayChallenge != null)
                                _buildDailyChallengeCard(
                                  isDark,
                                  studentProvider.todayChallenge!,
                                  studentProvider.hasAttemptedChallenge,
                                ),

                              // Monthly Target Card
                              _buildMonthlyTargetCard(
                                isDark,
                                student?.monthlyProgress ?? 0,
                                student?.monthlyTarget ?? 90,
                              ),

                              // Stats Grid
                              _buildStatsGrid(isDark, student),

                              // SWOT Reports
                              _buildSwotReports(isDark),

                              const SizedBox(
                                height: 100,
                              ), // Space for bottom nav
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom Navigation
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildBottomNav(isDark),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingBackground() {
    return Stack(
      children: [
        // Top left - school icon
        AnimatedBuilder(
          animation: _floatController1,
          builder: (context, child) {
            return Positioned(
              top:
                  MediaQuery.of(context).size.height * 0.25 +
                  (_floatController1.value * 20 - 10),
              left: MediaQuery.of(context).size.width * 0.25,
              child: Opacity(
                opacity: 0.1,
                child: Icon(
                  Icons.school,
                  size: 120,
                  color: Colors.grey.shade400,
                ),
              ),
            );
          },
        ),

        // Bottom right - trophy icon
        AnimatedBuilder(
          animation: _floatController2,
          builder: (context, child) {
            return Positioned(
              bottom:
                  MediaQuery.of(context).size.height * 0.25 +
                  (_floatController2.value * 20 - 10),
              right: MediaQuery.of(context).size.width * 0.25,
              child: Opacity(
                opacity: 0.1,
                child: Icon(
                  Icons.workspace_premium,
                  size: 120,
                  color: Colors.grey.shade400,
                ),
              ),
            );
          },
        ),

        // Top right - trophy icon (small)
        AnimatedBuilder(
          animation: _floatController3,
          builder: (context, child) {
            return Positioned(
              top: 40 + (_floatController3.value * 20 - 10),
              right: 40,
              child: Opacity(
                opacity: 0.1,
                child: Icon(
                  Icons.emoji_events,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
              ),
            );
          },
        ),

        // Bottom left - lightbulb icon
        AnimatedBuilder(
          animation: _floatController4,
          builder: (context, child) {
            return Positioned(
              bottom: 80 + (_floatController4.value * 20 - 10),
              left: 40,
              child: Opacity(
                opacity: 0.1,
                child: Icon(
                  Icons.lightbulb_outline,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(bool isDark, student) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Profile Picture
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.grey.shade700 : Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              color: const Color(0xFFF59E0B),
            ),
            child: student?.photoUrl != null
                ? ClipOval(
                    child: Image.network(
                      student!.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.person, color: Colors.white);
                      },
                    ),
                  )
                : const Icon(Icons.person, color: Colors.white, size: 24),
          ),

          // LenV Title
          Text(
            'LenV',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.grey.shade900,
            ),
          ),

          // Settings Button
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey.shade800.withOpacity(0.5)
                  : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                Icons.settings,
                size: 20,
                color: isDark ? Colors.white : Colors.grey.shade600,
              ),
              onPressed: () {
                // Navigate to settings
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeText(bool isDark, String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Text(
        'Welcome, $name!',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.grey.shade900,
        ),
      ),
    );
  }

  Widget _buildSearchRewardsCTA(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/search-rewards'),
          icon: const Text('🎁'),
          label: const Text('Search Rewards'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1777FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDailyChallengeCard(bool isDark, challenge, bool hasAttempted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: hasAttempted ? null : () => _showChallengeDialog(challenge),
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(
              math.sin(DateTime.now().millisecondsSinceEpoch / 1000) * 0.1,
            ),
          alignment: Alignment.center,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: hasAttempted
                    ? [Colors.grey.shade400, Colors.grey.shade500]
                    : [const Color(0xFFFB923C), const Color(0xFFF59E0B)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFB923C).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DAILY CHALLENGE${hasAttempted ? ' - COMPLETED' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.8),
                        letterSpacing: 1.2,
                      ),
                    ),
                    Icon(
                      hasAttempted ? Icons.check_circle : Icons.psychology,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  challenge.question,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    hasAttempted
                        ? '${challenge.points} points earned!'
                        : 'Tap to answer (+${challenge.points} points)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChallengeDialog(challenge) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(challenge.subject),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              challenge.question,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...challenge.options.map<Widget>(
              (option) => ListTile(
                title: Text(option),
                onTap: () {
                  Navigator.pop(context);
                  _submitChallengeAnswer(option, challenge.correctAnswer);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitChallengeAnswer(
    String answer,
    String correctAnswer,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );

    if (authProvider.currentUser == null) return;

    final isCorrect = await studentProvider.submitChallengeAnswer(
      authProvider.currentUser!.uid,
      answer,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCorrect
                ? '🎉 Correct! You earned points!'
                : '❌ Incorrect. The correct answer is: $correctAnswer',
          ),
          backgroundColor: isCorrect ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildMonthlyTargetCard(bool isDark, double progress, double target) {
    final percentage = target > 0 ? (progress / target * 100).clamp(0, 100) : 0;
    final testsNeeded = target > 0
        ? (target - progress).clamp(0, target).toInt()
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800.withOpacity(0.5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MONTHLY TARGET',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    letterSpacing: 1.2,
                  ),
                ),
                const Icon(
                  Icons.trending_up,
                  color: Color(0xFFF59E0B),
                  size: 24,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey.shade900,
                  ),
                ),
                Text(
                  'Target: ${target.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: _progressController,
              builder: (context, child) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progressController.value * (percentage / 100),
                    minHeight: 8,
                    backgroundColor: isDark
                        ? Colors.grey.shade700
                        : Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFF59E0B),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              testsNeeded > 0
                  ? 'Complete $testsNeeded more test${testsNeeded > 1 ? 's' : ''} to reach your goal!'
                  : '🎉 Goal achieved! Keep it up!',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark, student) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
        children: [
          _buildStatCard(
            isDark: isDark,
            icon: Icons.assignment,
            label: 'TESTS',
            value: '${student?.pendingTests ?? 0}',
            subtitle: 'Pending',
            iconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            onTap: () => Navigator.pushNamed(context, '/student-tests'),
          ),
          _buildStatCard(
            isDark: isDark,
            icon: Icons.emoji_events,
            label: 'REWARDS',
            value: '${student?.rewardPoints ?? 0}',
            subtitle: 'Points',
            iconColor: const Color(0xFFFBBF24),
            showPulse: true,
            onTap: () => Navigator.pushNamed(context, '/student-rewards'),
          ),
          _buildStatCard(
            isDark: isDark,
            icon: Icons.leaderboard,
            label: 'LEADERBOARD',
            value: '#${student?.classRank ?? '--'}',
            subtitle: 'Class Rank',
            iconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            onTap: () => Navigator.pushNamed(context, '/student-leaderboard'),
          ),
          _buildStatCard(
            isDark: isDark,
            icon: Icons.notifications,
            label: 'NOTIFICATIONS',
            value: '${student?.newNotifications ?? 0}',
            subtitle: 'New',
            iconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            showBadge: (student?.newNotifications ?? 0) > 0,
            onTap: () => Navigator.pushNamed(context, '/student-notifications'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
    required Color iconColor,
    bool showPulse = false,
    bool showBadge = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800.withOpacity(0.5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Icon(icon, color: iconColor, size: 20),
                  ],
                ),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),

            // Notification badge
            if (showBadge)
              Positioned(
                top: 0,
                right: 0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Static circle
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwotReports(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, '/student-swot-reports');
        },
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey.shade800.withOpacity(0.5)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFB923C), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFB923C).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.query_stats,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SWOT Reports',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Analyze your performance',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey.shade800.withOpacity(0.5)
            : Colors.white.withOpacity(0.7),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.grey.shade700.withOpacity(0.8)
                : Colors.grey.shade200.withOpacity(0.8),
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                    icon: Icons.home,
                    label: 'Home',
                    index: 0,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    icon: Icons.assignment,
                    label: 'Tests',
                    index: 1,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    icon: Icons.emoji_events,
                    label: 'Rewards',
                    index: 2,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    icon: Icons.leaderboard,
                    label: 'Leaderboard',
                    index: 3,
                    isDark: isDark,
                  ),
                  _buildNavItem(
                    icon: Icons.person,
                    label: 'Profile',
                    index: 4,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isDark,
  }) {
    final isSelected = _selectedIndex == index;
    final color = isSelected
        ? const Color(0xFFF59E0B)
        : isDark
        ? Colors.grey.shade400
        : Colors.grey.shade600;

    return InkWell(
      onTap: () => _onNavItemTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
