import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'per_test_leaderboard_detail.dart';

class PerTestLeaderboardList extends StatelessWidget {
  const PerTestLeaderboardList({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final studentId = authProvider.currentUser?.uid;

    if (studentId == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.grey[50],
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111111) : Colors.grey[50],
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new,
                          color: isDark ? Colors.white60 : Colors.black54,
                          size: 24,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 0),
                    child: Text(
                      'Leaderboards',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1D21),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Segmented Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: isDark ? null : Border.all(color: Colors.black12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Overall',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF7B00),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF7B00).withOpacity(0.5),
                              blurRadius: 12,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Per-Test',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Test List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('testResults')
                    .where('studentId', isEqualTo: studentId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF7B00),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1A1A1A)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(48),
                            ),
                            child: Icon(
                              Icons.menu_book,
                              size: 48,
                              color: isDark
                                  ? const Color(0xFF52525B)
                                  : Colors.black26,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No tests assigned yet',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1D21),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tests will appear here once assigned',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF71717A)
                                  : Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Get unique tests
                  final testMap = <String, Map<String, dynamic>>{};
                  for (final doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final testId = data['testId'] as String?;
                    if (testId != null && !testMap.containsKey(testId)) {
                      testMap[testId] = data;
                    }
                  }

                  final tests = testMap.values.toList();
                  // Sort by date descending (use assignedAt for all tests)
                  tests.sort((a, b) {
                    final aDate = (a['assignedAt'] as Timestamp?)?.toDate();
                    final bDate = (b['assignedAt'] as Timestamp?)?.toDate();
                    if (aDate == null || bDate == null) return 0;
                    return bDate.compareTo(aDate);
                  });

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: tests.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final test = tests[index];
                      return _buildTestItem(context, test);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestItem(BuildContext context, Map<String, dynamic> test) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final testTitle = test['testTitle'] as String? ?? 'Unnamed Test';
    final subject = test['subject'] as String? ?? '';
    final assignedAt = (test['assignedAt'] as Timestamp?)?.toDate();
    final dateStr = assignedAt != null
        ? '${_monthName(assignedAt.month)} ${assignedAt.day}, ${assignedAt.year}'
        : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PerTestLeaderboardDetail(
                testId: test['testId'] as String,
                testTitle: testTitle,
                subject: subject,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color(0xFFFF7B00).withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF27272A)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.menu_book,
                  color: isDark ? Colors.white : const Color(0xFF1A1D21),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      testTitle,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1D21),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subject.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subject,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFA1A1AA)
                              : Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateStr,
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF71717A)
                              : Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: isDark ? Colors.white30 : Colors.black26,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthName(int month) {
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
    return months[month - 1];
  }
}
