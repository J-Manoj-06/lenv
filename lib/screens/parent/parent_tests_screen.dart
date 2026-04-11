import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/parent_provider.dart';
import '../../models/test_result_model.dart';
import '../../widgets/student_selection/student_avatar_row.dart';
import 'parent_test_result_detail_screen.dart';
import 'parent_profile_screen.dart';

class ParentTestsScreen extends StatefulWidget {
  const ParentTestsScreen({super.key});

  @override
  State<ParentTestsScreen> createState() => _ParentTestsScreenState();
}

class _ParentTestsScreenState extends State<ParentTestsScreen>
    with SingleTickerProviderStateMixin {
  static const Color parentGreen = Color(0xFF14A670);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  late TabController _tabController;

  double _contentBottomInset(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return 128 + 64 + safeBottom;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      body: Consumer<ParentProvider>(
        builder: (context, parentProvider, child) {
          if (!parentProvider.hasChildren) {
            return _buildEmptyState(isDark, 'No children found');
          }

          if (parentProvider.isLoadingTests) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(parentGreen),
              ),
            );
          }

          return NestedScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: _buildScrollableHeader(context, isDark),
              ),
              const SliverToBoxAdapter(child: StudentAvatarRow()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  height: 48,
                  child: Container(
                    color: isDark ? backgroundDark : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: parentGreen,
                      unselectedLabelColor: isDark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                      indicatorColor: parentGreen,
                      tabs: const [
                        Tab(text: 'Completed'),
                        Tab(text: 'Pending'),
                        Tab(text: 'Upcoming'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildCompletedTests(isDark, parentProvider),
                _buildPendingTests(isDark, parentProvider),
                _buildUpcomingTests(isDark, parentProvider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildScrollableHeader(BuildContext context, bool isDark) {
    final iconColor = isDark ? Colors.white : textPrimary;
    final surfaceColor = isDark ? backgroundDark : Colors.white;

    return Container(
      color: surfaceColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: Text(
              'Tests',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.person, size: 28, color: iconColor),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ParentProfileScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingTests(bool isDark, ParentProvider provider) {
    if (provider.upcomingTests.isEmpty) {
      return _buildEmptyState(isDark, 'No upcoming tests');
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _contentBottomInset(context)),
      itemCount: provider.upcomingTests.length,
      itemBuilder: (context, index) {
        final test = provider.upcomingTests[index];
        return _buildUpcomingTestCard(isDark, test);
      },
    );
  }

  Widget _buildCompletedTests(bool isDark, ParentProvider provider) {
    final completedTests = provider.testResults.where((test) {
      return true; // All test results are completed tests
    }).toList();

    completedTests.sort((a, b) {
      return b.completedAt.compareTo(a.completedAt);
    });

    if (completedTests.isEmpty) {
      return _buildEmptyState(isDark, 'No completed tests');
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _contentBottomInset(context)),
      itemCount: completedTests.length,
      itemBuilder: (context, index) {
        final test = completedTests[index];
        return _buildTestResultCard(isDark, test, provider);
      },
    );
  }

  Widget _buildPendingTests(bool isDark, ParentProvider provider) {
    // Pending tests are upcoming tests that haven't been completed yet
    if (provider.upcomingTests.isEmpty) {
      return _buildEmptyState(isDark, 'No pending tests');
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 16, 16, _contentBottomInset(context)),
      itemCount: provider.upcomingTests.length,
      itemBuilder: (context, index) {
        final test = provider.upcomingTests[index];
        return _buildUpcomingTestCard(isDark, test);
      },
    );
  }

  Widget _buildUpcomingTestCard(bool isDark, Map<String, dynamic> test) {
    final testDate = (test['scheduledDate'] as Timestamp?)?.toDate();
    final dateStr = testDate != null
        ? DateFormat('MMM dd, yyyy').format(testDate)
        : 'Date TBD';
    final timeStr = testDate != null
        ? DateFormat('hh:mm a').format(testDate)
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1A2F) : cardBg,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: parentGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: parentGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        test['testName'] ?? 'Untitled Test',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        test['subject'] ?? 'General',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2540) : backgroundLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : textPrimary,
                    ),
                  ),
                  if (timeStr.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (test['duration'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.timer,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Duration: ${test['duration']} minutes',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTestResultCard(
    bool isDark,
    TestResultModel test,
    ParentProvider provider,
  ) {
    final isNotAttended =
        test.answers.isEmpty && test.correctAnswers == 0 && test.score == 0;
    final percentage = test.totalQuestions > 0
        ? (test.correctAnswers / test.totalQuestions * 100).round()
        : 0;

    final dateStr = DateFormat('MMM dd, yyyy').format(test.completedAt);

    Color scoreColor;
    if (isNotAttended) {
      scoreColor = const Color(0xFFF4C430);
    } else if (percentage >= 80) {
      scoreColor = Colors.green;
    } else if (percentage >= 60) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1A2F) : cardBg,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ParentTestResultDetailScreen(test: test),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Score Circle
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scoreColor, width: 3),
                ),
                child: Center(
                  child: Text(
                    '$percentage%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Test Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      test.testTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      test.subject,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (!isNotAttended) ...[
                          Icon(
                            Icons.check_circle,
                            size: 14,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${test.correctAnswers}/${test.totalQuestions} correct',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (isNotAttended)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3CD),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Not attended',
                              style: TextStyle(
                                color: Color(0xFF8A6D1D),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isNotAttended) const SizedBox(width: 12),
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow Icon
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return height != oldDelegate.height || child != oldDelegate.child;
  }
}
