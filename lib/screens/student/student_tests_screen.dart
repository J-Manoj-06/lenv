import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/firestore_service.dart';
import 'test_rules_screen.dart';
import '../../widgets/student_bottom_nav.dart';

class StudentTestsScreen extends StatefulWidget {
  const StudentTestsScreen({super.key});

  @override
  State<StudentTestsScreen> createState() => _StudentTestsScreenState();
}

class _StudentTestsScreenState extends State<StudentTestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final testProvider = Provider.of<TestProvider>(context, listen: false);
      if (auth.currentUser != null) {
        testProvider.loadAvailableTests(
          auth.currentUser!.uid,
          studentEmail: auth.currentUser!.email,
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final studentId = auth.currentUser?.uid;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF111827)
          : const Color(0xFFF7F3EF),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _Header(),

            // Tabs
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.grey.shade800
                        : const Color(0xFFE8DBCE),
                  ),
                ),
                color: isDark
                    ? Colors.black.withOpacity(0.1)
                    : Colors.white.withOpacity(0.8),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Theme.of(context).textTheme.bodyLarge?.color,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                unselectedLabelColor: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withOpacity(0.6),
                indicatorColor: const Color(0xFFF2800D),
                indicatorWeight: 2,
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Pending'),
                  Tab(text: 'Completed'),
                ],
              ),
            ),

            Expanded(
              child: studentId == null
                  ? const Center(child: Text('Please login as a student.'))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _AllTestsTab(studentId: studentId),
                        _PendingTab(studentId: studentId),
                        _CompletedTab(studentId: studentId),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const StudentBottomNav(currentIndex: 1),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor.withOpacity(0.8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back,
              color: Theme.of(context).iconTheme.color,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 40.0),
              child: Text(
                'Assigned Tests',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllTestsTab extends StatelessWidget {
  final String studentId;
  const _AllTestsTab({required this.studentId});

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();

    return StreamBuilder<List<TestModel>>(
      stream: FirebaseFirestore.instance
          .collection('tests')
          .where('assignedStudentIds', arrayContains: studentId)
          .snapshots()
          .map((s) {
            print('🎓 Student Tests Query for $studentId:');
            print(
              '   Query: tests where assignedStudentIds arrayContains $studentId',
            );
            print(
              '   Found ${s.docs.length} tests with student in assignedStudentIds',
            );

            if (s.docs.isEmpty) {
              // Debug: Check all published tests to see if any have this student
              FirebaseFirestore.instance
                  .collection('tests')
                  .where('status', isEqualTo: 'published')
                  .get()
                  .then((allTests) {
                    print(
                      '   🔍 Checking all ${allTests.docs.length} published tests:',
                    );
                    for (var doc in allTests.docs.take(5)) {
                      final data = doc.data();
                      final assignedIds =
                          data['assignedStudentIds'] as List<dynamic>?;
                      final title = data['title'];
                      print(
                        '     - "$title": ${assignedIds?.length ?? 0} students assigned',
                      );
                      if (assignedIds != null &&
                          assignedIds.contains(studentId)) {
                        print('       ✓ THIS TEST HAS THE STUDENT!');
                      } else if (assignedIds != null) {
                        print(
                          '       ✗ Student not in list. First 3 IDs: ${assignedIds.take(3)}',
                        );
                      }
                    }
                  });
            }

            final tests = s.docs.map((d) {
              final test = TestModel.fromJson(d.data());
              print(
                '   - Test: ${test.title}, Status: ${test.status}, ID: ${test.id}',
              );
              return test;
            }).toList();
            return tests;
          }),
      builder: (context, pendingSnap) {
        return StreamBuilder<List<TestResultModel>>(
          stream: firestore.getTestResultsByStudent(studentId),
          builder: (context, completedSnap) {
            if ((pendingSnap.connectionState == ConnectionState.waiting) ||
                (completedSnap.connectionState == ConnectionState.waiting)) {
              return const Center(child: CircularProgressIndicator());
            }

            final tests = (pendingSnap.data ?? [])
                .where((t) => t.status == TestStatus.published)
                .toList();

            print(
              '📝 After filtering by published status: ${tests.length} tests',
            );
            if (tests.isNotEmpty) {
              print('   Available tests:');
              for (final t in tests) {
                print('     - ${t.title} (${t.className} ${t.section})');
              }
            }

            final completed = completedSnap.data ?? [];
            final completedById = {for (var r in completed) r.testId: r};
            final now = DateTime.now();

            // Merge lists into a unified view model
            final items = <_TestListItem>[];
            for (final t in tests) {
              final r = completedById[t.id];
              if (r != null) {
                final canShow = now.isAfter(t.endDate);
                items.add(
                  _TestListItem.completed(
                    result: r,
                    showResult: canShow,
                    endDate: t.endDate,
                  ),
                );
              } else {
                items.add(_TestListItem.pending(test: t));
              }
            }
            // Include any stray results without a matching test doc
            for (final r in completed) {
              if (!tests.any((t) => t.id == r.testId)) {
                items.add(_TestListItem.completed(result: r));
              }
            }
            // Sort: show most recent first by created/completed date
            items.sort((a, b) {
              final aDate = a.isPending
                  ? a.test!.createdAt
                  : a.result!.completedAt;
              final bDate = b.isPending
                  ? b.test!.createdAt
                  : b.result!.completedAt;
              return bDate.compareTo(aDate);
            });

            if (items.isEmpty) {
              return const _EmptyState();
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) => _TestCard(item: items[i]),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: items.length,
            );
          },
        );
      },
    );
  }
}

class _PendingTab extends StatelessWidget {
  final String studentId;
  const _PendingTab({required this.studentId});

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    return StreamBuilder<List<TestModel>>(
      stream: FirebaseFirestore.instance
          .collection('tests')
          .where('assignedStudentIds', arrayContains: studentId)
          .snapshots()
          .map(
            (s) => s.docs
                .map((d) => TestModel.fromJson(d.data()))
                .where((t) => t.status == TestStatus.published)
                .toList(),
          ),
      builder: (context, testsSnap) {
        return StreamBuilder<List<TestResultModel>>(
          stream: firestore.getTestResultsByStudent(studentId),
          builder: (context, resultsSnap) {
            if (testsSnap.connectionState == ConnectionState.waiting ||
                resultsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final tests = testsSnap.data ?? [];
            final completedIds = (resultsSnap.data ?? [])
                .map((r) => r.testId)
                .toSet();
            final now = DateTime.now();
            // Pending tests are those not completed AND not expired
            final pending = tests
                .where(
                  (t) =>
                      !completedIds.contains(t.id) && now.isBefore(t.endDate),
                )
                .toList();
            if (pending.isEmpty) {
              return const _EmptyState(message: 'No pending tests');
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) =>
                  _TestCard(item: _TestListItem.pending(test: pending[i])),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: pending.length,
            );
          },
        );
      },
    );
  }
}

class _CompletedTab extends StatelessWidget {
  final String studentId;
  const _CompletedTab({required this.studentId});

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    return StreamBuilder<List<TestModel>>(
      stream: FirebaseFirestore.instance
          .collection('tests')
          .where('assignedStudentIds', arrayContains: studentId)
          .snapshots()
          .map((s) => s.docs.map((d) => TestModel.fromJson(d.data())).toList()),
      builder: (context, testsSnap) {
        return StreamBuilder<List<TestResultModel>>(
          stream: firestore.getTestResultsByStudent(studentId),
          builder: (context, resultsSnap) {
            if (testsSnap.connectionState == ConnectionState.waiting ||
                resultsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final tests = testsSnap.data ?? [];
            final testById = {for (var t in tests) t.id: t};
            final resultsRaw = resultsSnap.data ?? [];
            // Dedup results by testId: keep latest completedAt to avoid duplicate listings/counts
            final Map<String, TestResultModel> latestByTest = {};
            for (final r in resultsRaw) {
              final existing = latestByTest[r.testId];
              if (existing == null ||
                  r.completedAt.isAfter(existing.completedAt)) {
                latestByTest[r.testId] = r;
              }
            }
            final results = latestByTest.values.toList();
            if (results.isEmpty) {
              return const _EmptyState(message: 'No completed tests');
            }
            final now = DateTime.now();
            final items = results.map((r) {
              final t = testById[r.testId];
              final endDate = t?.endDate;
              final canShow = endDate == null ? true : now.isAfter(endDate);
              return _TestListItem.completed(
                result: r,
                showResult: canShow,
                endDate: endDate,
              );
            }).toList();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) => _TestCard(item: items[i]),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: items.length,
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({this.message = 'No tests to show'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.quiz_outlined,
              size: 48,
              color: Theme.of(context).iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _TestListItem {
  final TestModel? test;
  final TestResultModel? result;
  final bool isPending;
  final bool showResult; // for completed items: gate result until endDate
  final DateTime? endDate;

  _TestListItem.pending({required this.test})
    : result = null,
      isPending = true,
      showResult = false,
      endDate = test!.endDate;
  _TestListItem.completed({
    required this.result,
    this.showResult = true,
    this.endDate,
  }) : test = null,
       isPending = false;
}

class _TestCard extends StatelessWidget {
  final _TestListItem item;
  const _TestCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    final now = DateTime.now();

    final Color statusBg;
    final Color statusText;
    final String statusLabel;

    String title = '';
    String subject = '';
    String assignedBy = '';
    String dateLabel = '';
    String dateValue = '';
    VoidCallback onPressed;
    String buttonText;
    IconData leadingIcon;
    Color leadingBg;
    Color leadingFg;
    bool isExpired = false;

    if (item.isPending) {
      final t = item.test!;
      isExpired = now.isAfter(t.endDate);

      title = t.title;
      subject = t.subject;
      assignedBy = t.teacherName;
      dateLabel = 'Due Date:';
      dateValue = fmt.format(t.endDate);

      if (isExpired) {
        buttonText = 'Test Ended';
        onPressed = () {
          // Show dialog explaining test has expired
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Test Expired'),
              content: const Text(
                'This test has ended and is no longer available. The allocated time has passed.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        };
        statusBg = Colors.grey.shade400;
        statusText = Colors.white;
        statusLabel = 'Expired';
      } else {
        buttonText = 'Start Test';
        onPressed = () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => TestRulesScreen(test: t)),
          );
        };
        statusBg = const Color(0xFFF2800D);
        statusText = Colors.white;
        statusLabel = 'Pending';
      }

      leadingIcon = Icons.quiz;
      leadingBg = const Color(0xFFFEF2E6);
      leadingFg = const Color(0xFFF2800D);
    } else {
      final r = item.result!;
      title = r.testTitle;
      subject = r.subject;
      assignedBy = '';
      final canShowResults =
          item.showResult ||
          (item.endDate != null && DateTime.now().isAfter(item.endDate!));
      dateLabel = canShowResults ? 'Completed:' : 'Due Date:';
      dateValue = canShowResults
          ? fmt.format(r.completedAt)
          : (item.endDate != null ? fmt.format(item.endDate!) : '');
      buttonText = canShowResults ? 'View Results' : 'Results after due';
      onPressed = canShowResults
          ? () {
              Navigator.pushNamed(
                context,
                '/student-test-result',
                arguments: {'resultId': r.id},
              );
            }
          : () {};
      leadingIcon = Icons.history_edu;
      leadingBg = const Color(0xFFE8E9EB);
      leadingFg = const Color(0xFF1C140D);
      statusBg = const Color(0xFFE8E9EB);
      statusText = const Color(0xFF656669);
      statusLabel = canShowResults
          ? 'Completed'
          : 'Completed (awaiting results)';
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: leadingBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(leadingIcon, color: leadingFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Subject: ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          subject,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (assignedBy.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Assigned By: ',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            assignedBy,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            color: Theme.of(context).dividerColor,
            height: 16,
            thickness: 1,
            indent: 0,
            endIndent: 0,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    dateLabel + ' ',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    dateValue,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              _PrimaryButton(
                label: buttonText,
                onPressed: onPressed,
                isPrimary: item.isPending && !isExpired,
                enabled:
                    (item.isPending && !isExpired) ||
                    buttonText == 'View Results',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool enabled;
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isPrimary = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(100, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: !enabled
            ? Colors.grey.shade300
            : (isPrimary ? const Color(0xFFF2800D) : Colors.white),
        foregroundColor: !enabled
            ? Colors.grey.shade600
            : (isPrimary ? Colors.white : const Color(0xFF1C140D)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: !enabled
                ? Colors.grey.shade300
                : (isPrimary ? Colors.transparent : const Color(0xFFE8DBCE)),
          ),
        ),
        elevation: !enabled ? 0 : (isPrimary ? 1 : 0),
      ),
      onPressed: enabled ? onPressed : null,
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
