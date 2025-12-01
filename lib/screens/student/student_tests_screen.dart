import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import 'test_rules_screen.dart';

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
            _Header(),
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
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor.withOpacity(0.8),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Assigned Tests',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
    // Unified query: get all student assignments, then fetch test details and classify locally.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where(
            'status',
            whereIn: ['assigned', 'started', 'completed', 'submitted'],
          )
          .snapshots(),
      builder: (context, assignedSnap) {
        if (assignedSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final resultDocs = assignedSnap.data?.docs ?? [];
        if (resultDocs.isEmpty) {
          return const _EmptyState(message: 'No tests assigned yet');
        }

        final testIds = resultDocs
            .map((d) => (d.data() as Map<String, dynamic>)['testId'] as String?)
            .where((id) => id != null && id.isNotEmpty)
            .toSet()
            .take(10)
            .toList();

        if (testIds.isEmpty) {
          return const _EmptyState(message: 'No tests assigned yet');
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('scheduledTests')
              .where(FieldPath.documentId, whereIn: testIds)
              .snapshots(),
          builder: (context, testsSnap) {
            if (testsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final testDocs = testsSnap.data?.docs ?? [];
            final tests = testDocs
                .map(
                  (d) => TestModel.fromScheduledTest(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList();

            if (tests.isEmpty) {
              return const _EmptyState(message: 'No tests assigned yet');
            }

            final items = <_TestListItem>[];

            for (final t in tests) {
              QueryDocumentSnapshot? matchingDoc;
              for (final doc in resultDocs) {
                final raw = doc.data() as Map<String, dynamic>;
                if (raw['testId'] == t.id) {
                  matchingDoc = doc;
                  break;
                }
              }

              if (matchingDoc == null) {
                items.add(_TestListItem.pending(test: t));
                continue;
              }

              final data = matchingDoc.data() as Map<String, dynamic>;
              final status = (data['status'] ?? '') as String;
              final submittedAt = data['submittedAt'];
              final score = data['score'];
              final isCompleted =
                  status == 'completed' ||
                  status == 'submitted' ||
                  submittedAt != null ||
                  (score is num && score > 0);

              if (!isCompleted) {
                items.add(_TestListItem.pending(test: t));
                continue;
              }

              try {
                final result = TestResultModel.fromFirestore(
                  matchingDoc as DocumentSnapshot<Map<String, dynamic>>,
                );
                final canShow = DateTime.now().isAfter(t.endDate);
                items.add(
                  _TestListItem.completed(
                    result: result,
                    showResult: canShow,
                    endDate: t.endDate,
                  ),
                );
                if (status != 'completed') {
                  matchingDoc.reference.update({'status': 'completed'}).catchError((
                    e,
                  ) {
                    print(
                      '⚠️ Auto-heal status update failed for testResult ${matchingDoc!.id}: $e',
                    );
                  });
                }
              } catch (e) {
                print('❌ Error converting result for test ${t.id}: $e');
                items.add(_TestListItem.pending(test: t));
              }
            }

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
    // Query assigned tests from student's testResults
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where(
            'status',
            whereIn: ['assigned', 'started', 'completed', 'submitted'],
          )
          .snapshots(),
      builder: (context, assignedSnap) {
        if (assignedSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Filter only truly pending (exclude those that have submittedAt or score or status completed/submitted)
        final allDocs = assignedSnap.data?.docs ?? [];
        final assignedDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '') as String;
          final submittedAt = data['submittedAt'];
          final score = data['score'];
          // Exclude both 'completed' (app) and 'submitted' (website)
          final isCompleted =
              status == 'completed' ||
              status == 'submitted' ||
              submittedAt != null ||
              (score is num && score > 0);
          return !isCompleted; // keep only pending
        }).toList();
        if (assignedDocs.isEmpty) {
          return const _EmptyState(message: 'No pending tests');
        }

        // Fetch test details
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('scheduledTests')
              .where(
                FieldPath.documentId,
                whereIn: assignedDocs
                    .map((doc) => doc['testId'] as String)
                    .take(10)
                    .toList(),
              )
              .snapshots(),
          builder: (context, testsSnap) {
            if (testsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final testDocs = testsSnap.data?.docs ?? [];
            final tests = testDocs
                .map(
                  (d) => TestModel.fromScheduledTest(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  ),
                )
                .toList();

            final now = DateTime.now();

            // Pending tests are those not expired (status is already 'assigned')
            final pending = tests
                .where((t) => now.isBefore(t.endDate))
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
    // Query completed assignments from testResults collection
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('testResults')
          .where('studentId', isEqualTo: studentId)
          .where(
            'status',
            whereIn: ['assigned', 'started', 'completed', 'submitted'],
          )
          .snapshots(),
      builder: (context, assignmentsSnap) {
        if (assignmentsSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = assignmentsSnap.data?.docs ?? [];
        // Completed classification: status completed/submitted OR submittedAt/score present
        final assignmentDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '') as String;
          final submittedAt = data['submittedAt'];
          final score = data['score'];
          // Recognize both 'completed' (app) and 'submitted' (website)
          return status == 'completed' ||
              status == 'submitted' ||
              submittedAt != null ||
              (score is num && score > 0);
        }).toList();
        print(
          '📊 Completed tests query returned ${assignmentDocs.length} assignments',
        );

        if (assignmentDocs.isEmpty) {
          return const _EmptyState(message: 'No completed tests');
        }

        // Extract test IDs from assignments
        final testIds = assignmentDocs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .map((data) => data['testId'] as String?)
            .where((id) => id != null && id.isNotEmpty)
            .toSet()
            .toList();

        if (testIds.isEmpty) {
          return const _EmptyState(message: 'No completed tests');
        }

        print('📝 Fetching test details for ${testIds.length} unique tests');

        // Fetch test details from scheduledTests collection
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('scheduledTests')
              .where(FieldPath.documentId, whereIn: testIds)
              .snapshots(),
          builder: (context, testsSnap) {
            if (testsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final testDocs = testsSnap.data?.docs ?? [];
            print(
              '📚 Retrieved ${testDocs.length} test details from scheduledTests',
            );

            // Convert to TestModel using fromScheduledTest
            final Map<String, TestModel> testById = {};
            for (final doc in testDocs) {
              try {
                final test = TestModel.fromScheduledTest(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                );
                testById[test.id] = test;
              } catch (e) {
                print('❌ Error converting test ${doc.id}: $e');
              }
            }

            // Build items from completed assignments directly
            final items = <_TestListItem>[];
            final now = DateTime.now();

            for (final assignmentDoc in assignmentDocs) {
              final assignmentData =
                  assignmentDoc.data() as Map<String, dynamic>;
              final testId = assignmentData['testId'] as String?;
              if (testId == null) continue;

              TestModel? test = testById[testId];
              DateTime? endDate = test?.endDate;
              if (test == null) {
                // Fallback compute endDate from assignment data
                try {
                  final dateStr = assignmentData['date'] as String?;
                  final startTimeStr =
                      assignmentData['startTime'] as String? ?? '00:00';
                  final duration = (assignmentData['duration'] as int?) ?? 60;
                  if (dateStr != null) {
                    final startDate = DateTime.parse('$dateStr $startTimeStr');
                    endDate = startDate.add(Duration(minutes: duration));
                  }
                } catch (_) {}
              }

              try {
                final result = TestResultModel.fromFirestore(
                  assignmentDoc as DocumentSnapshot<Map<String, dynamic>>,
                );
                final canShow = endDate == null ? true : now.isAfter(endDate);
                items.add(
                  _TestListItem.completed(
                    result: result,
                    showResult: canShow,
                    endDate: endDate,
                  ),
                );
              } catch (e) {
                print('❌ Error creating result for test $testId: $e');
              }
            }

            if (items.isEmpty) {
              return const _EmptyState(message: 'No completed tests');
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
      final notStartedYet = now.isBefore(t.startDate);

      title = t.title;
      subject = t.subject;
      assignedBy = t.teacherName;
      // Show start or due date based on schedule
      if (notStartedYet) {
        dateLabel = 'Starts:';
        dateValue = fmt.format(t.startDate);
      } else {
        dateLabel = 'Due Date:';
        dateValue = fmt.format(t.endDate);
      }

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
        if (notStartedYet) {
          buttonText = 'Yet to start';
          onPressed = () {
            // Inform the student about the scheduled start time
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Test not started'),
                content: Text(
                  'This test is scheduled to start on ${fmt.format(t.startDate)}. Please check back later.',
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
          statusBg = const Color(0xFFE3F2FD);
          statusText = const Color(0xFF1565C0);
          statusLabel = 'Scheduled';
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
      }

      leadingIcon = Icons.quiz;
      leadingBg = const Color(0xFFFEF2E6);
      leadingFg = const Color(0xFFF2800D);
    } else {
      final r = item.result!;
      title = r.testTitle;
      subject = r.subject;
      assignedBy = '';
      // Show results immediately after completion
      dateLabel = 'Completed:';
      dateValue = fmt.format(r.completedAt);
      buttonText = 'View Results';
      onPressed = () {
        Navigator.pushNamed(
          context,
          '/student-test-result',
          arguments: {'resultId': r.id},
        );
      };
      leadingIcon = Icons.history_edu;
      leadingBg = const Color(0xFFE8E9EB);
      leadingFg = const Color(0xFF1C140D);
      statusBg = const Color(0xFFE8E9EB);
      statusText = const Color(0xFF656669);
      statusLabel = 'Completed';
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                        Expanded(
                          child: Text(
                            subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
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
                          Expanded(
                            child: Text(
                              assignedBy,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
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
                  overflow: TextOverflow.ellipsis,
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
                    '$dateLabel ',
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
                    (item.isPending &&
                        !isExpired &&
                        buttonText != 'Yet to start') ||
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
