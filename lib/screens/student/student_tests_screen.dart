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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            // Show loading while auth is initializing
            if (auth.isLoading || auth.currentUser == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFF2800D),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading your tests...',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }

            final studentId = auth.currentUser!.uid;
            final studentEmail = auth.currentUser!.email;

            return Column(
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
                      Tab(text: 'Upcoming'),
                      Tab(text: 'Completed'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _AllTestsTab(
                        studentId: studentId,
                        studentEmail: studentEmail,
                      ),
                      _UpcomingTab(
                        studentId: studentId,
                        studentEmail: studentEmail,
                      ),
                      _CompletedTab(
                        studentId: studentId,
                        studentEmail: studentEmail,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
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

class _AllTestsTab extends StatefulWidget {
  final String studentId;
  final String? studentEmail;
  const _AllTestsTab({required this.studentId, this.studentEmail});

  @override
  State<_AllTestsTab> createState() => _AllTestsTabState();
}

class _AllTestsTabState extends State<_AllTestsTab> {
  @override
  Widget build(BuildContext context) {
    // Unified query: get all student assignments, then fetch test details and classify locally.
    return StreamBuilder<QuerySnapshot>(
      stream: (() {
        final email = (widget.studentEmail ?? '').trim();
        if (email.isNotEmpty) {
          return FirebaseFirestore.instance
              .collection('testResults')
              .where('studentEmail', isEqualTo: email)
              .where(
                'status',
                whereIn: ['assigned', 'started', 'completed', 'submitted'],
              )
              .snapshots();
        }
        return FirebaseFirestore.instance
            .collection('testResults')
            .where('studentId', isEqualTo: widget.studentId)
            .where(
              'status',
              whereIn: ['assigned', 'started', 'completed', 'submitted'],
            )
            .snapshots();
      })(),
      builder: (context, assignedSnap) {
        if (assignedSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (assignedSnap.hasError) {
          return _ErrorState(
            message: 'Failed to load tests: ${assignedSnap.error}',
            onRetry: () => setState(() {}),
          );
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

            if (testsSnap.hasError) {
              return _ErrorState(
                message: 'Failed to load test details: ${testsSnap.error}',
                onRetry: () => setState(() {}),
              );
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
                  matchingDoc.reference
                      .update({'status': 'completed'})
                      .catchError((e) {});
                }
              } catch (e) {
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
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemCount: items.length,
            );
          },
        );
      },
    );
  }
}

class _UpcomingTab extends StatelessWidget {
  final String studentId;
  final String? studentEmail;
  const _UpcomingTab({required this.studentId, this.studentEmail});

  @override
  Widget build(BuildContext context) {
    // Query assigned tests from student's testResults
    return StreamBuilder<QuerySnapshot>(
      stream: (() {
        final email = (studentEmail ?? '').trim();
        if (email.isNotEmpty) {
          return FirebaseFirestore.instance
              .collection('testResults')
              .where('studentEmail', isEqualTo: email)
              .where(
                'status',
                whereIn: ['assigned', 'started', 'completed', 'submitted'],
              )
              .snapshots();
        }
        return FirebaseFirestore.instance
            .collection('testResults')
            .where('studentId', isEqualTo: studentId)
            .where(
              'status',
              whereIn: ['assigned', 'started', 'completed', 'submitted'],
            )
            .snapshots();
      })(),
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
          return const _EmptyState(message: 'No upcoming tests');
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

            // Upcoming tests: scheduled tests that haven't started yet OR live tests not yet attempted
            // (status is already 'assigned' meaning not completed)
            final upcoming = tests
                .where((t) => now.isBefore(t.endDate)) // Not expired
                .toList();

            // Sort by start date (upcoming first)
            upcoming.sort((a, b) => a.startDate.compareTo(b.startDate));

            if (upcoming.isEmpty) {
              return const _EmptyState(message: 'No upcoming tests');
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) =>
                  _TestCard(item: _TestListItem.pending(test: upcoming[i])),
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemCount: upcoming.length,
            );
          },
        );
      },
    );
  }
}

class _CompletedTab extends StatelessWidget {
  final String studentId;
  final String? studentEmail;
  const _CompletedTab({required this.studentId, this.studentEmail});

  @override
  Widget build(BuildContext context) {
    // Query completed assignments from testResults collection
    return StreamBuilder<QuerySnapshot>(
      stream: (() {
        final email = (studentEmail ?? '').trim();
        if (email.isNotEmpty) {
          return FirebaseFirestore.instance
              .collection('testResults')
              .where('studentEmail', isEqualTo: email)
              .where(
                'status',
                whereIn: ['assigned', 'started', 'completed', 'submitted'],
              )
              .snapshots();
        }
        return FirebaseFirestore.instance
            .collection('testResults')
            .where('studentId', isEqualTo: studentId)
            .where(
              'status',
              whereIn: ['assigned', 'started', 'completed', 'submitted'],
            )
            .snapshots();
      })(),
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

            // Convert to TestModel using fromScheduledTest
            final Map<String, TestModel> testById = {};
            for (final doc in testDocs) {
              try {
                final test = TestModel.fromScheduledTest(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                );
                testById[test.id] = test;
              } catch (e) {}
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
              } catch (e) {}
            }

            if (items.isEmpty) {
              return const _EmptyState(message: 'No completed tests');
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (ctx, i) => _TestCard(item: items[i]),
              separatorBuilder: (_, _) => const SizedBox(height: 12),
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

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
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
    final fmtTime = DateFormat('MMM d, yyyy • h:mm a');
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
    DateTime? startAt;
    DateTime? endAt;
    DateTime? completedAt;
    String stateDescription = '';

    if (item.isPending) {
      final t = item.test!;
      isExpired = now.isAfter(t.endDate);
      final notStartedYet = now.isBefore(t.startDate);

      title = t.title;
      subject = t.subject;
      assignedBy = t.teacherName;
      startAt = t.startDate;
      endAt = t.endDate;
      // Show start or due date based on schedule
      if (notStartedYet) {
        dateLabel = 'Starts:';
        dateValue = fmtTime.format(t.startDate);
      } else {
        dateLabel = 'Due Date:';
        dateValue = fmtTime.format(t.endDate);
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
        stateDescription = 'Not attempted (test expired)';
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
          stateDescription = 'Scheduled';
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
          stateDescription = 'Not attempted';
        }
      }

      leadingIcon = Icons.quiz;
      leadingBg = const Color(0xFFFEF2E6);
      leadingFg = const Color(0xFFF2800D);
    } else {
      final r = item.result!;
      final canShow = item.showResult;
      title = r.testTitle;
      subject = r.subject;
      assignedBy = '';
      completedAt = r.completedAt;
      endAt = item.endDate;
      if (canShow) {
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
      } else {
        // Lock results until due time
        dateLabel = 'Available After:';
        dateValue = item.endDate != null
            ? fmt.format(item.endDate!)
            : 'Due time';
        buttonText = 'Results Locked';
        onPressed = () {};
      }
      leadingIcon = Icons.history_edu;
      leadingBg = const Color(0xFFE8E9EB);
      leadingFg = const Color(0xFF1C140D);
      statusBg = const Color(0xFFE8E9EB);
      statusText = const Color(0xFF656669);
      statusLabel = canShow ? 'Completed' : 'Completed';
      stateDescription = canShow ? 'Completed' : 'Completed (results locked)';
    }

    final cardColor = isDark
        ? Theme.of(context).cardColor
        : Color.alphaBlend(statusBg.withOpacity(0.08), Colors.white);
    final borderColor = isDark ? Colors.white10 : statusBg.withOpacity(0.35);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _StudentTestDetailsPage(
              title: title,
              subject: subject,
              assignedBy: assignedBy,
              statusLabel: statusLabel,
              statusBg: statusBg,
              statusText: statusText,
              stateDescription: stateDescription,
              startAt: startAt,
              endAt: endAt,
              completedAt: completedAt,
              actionLabel: buttonText,
              onAction: onPressed,
              actionEnabled:
                  (item.isPending &&
                      !isExpired &&
                      buttonText != 'Yet to start') ||
                  buttonText == 'View Results',
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.16 : 0.07),
              blurRadius: 12,
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$dateLabel ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        TextSpan(
                          text: dateValue,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _PrimaryButton(
                        label: buttonText,
                        onPressed: onPressed,
                        isPrimary: item.isPending && !isExpired,
                        enabled:
                            (item.isPending &&
                                !isExpired &&
                                buttonText != 'Yet to start') ||
                            buttonText == 'View Results',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentTestDetailsPage extends StatelessWidget {
  const _StudentTestDetailsPage({
    required this.title,
    required this.subject,
    required this.assignedBy,
    required this.statusLabel,
    required this.statusBg,
    required this.statusText,
    required this.stateDescription,
    required this.startAt,
    required this.endAt,
    required this.completedAt,
    required this.actionLabel,
    required this.onAction,
    required this.actionEnabled,
  });

  final String title;
  final String subject;
  final String assignedBy;
  final String statusLabel;
  final Color statusBg;
  final Color statusText;
  final String stateDescription;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? completedAt;
  final String actionLabel;
  final VoidCallback onAction;
  final bool actionEnabled;

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '-';
    return DateFormat('dd MMM yyyy, h:mm a').format(dateTime);
  }

  String _statusMessage() {
    final label = statusLabel.toLowerCase();
    final action = actionLabel.toLowerCase();

    if (label.contains('expired') || action == 'test ended') {
      return 'Test expired • Not attempted';
    }
    if (action.contains('view result')) {
      return 'Test completed';
    }
    if (action == 'start test') {
      return 'Ready to attempt';
    }
    return stateDescription;
  }

  ({Color bg, Color fg, String text}) _semanticBadge() {
    final label = statusLabel.toLowerCase();
    final action = actionLabel.toLowerCase();

    if (label.contains('expired') || action == 'test ended') {
      return (bg: const Color(0xFF5E6169), fg: Colors.white, text: 'Expired');
    }
    if (action.contains('view result')) {
      return (bg: const Color(0xFF2B8A3E), fg: Colors.white, text: 'Active');
    }
    if (action == 'start test') {
      return (bg: const Color(0xFFF2800D), fg: Colors.white, text: 'Upcoming');
    }

    return (bg: statusBg, fg: statusText, text: statusLabel);
  }

  IconData _subjectIcon() {
    final s = subject.toLowerCase();
    if (s.contains('math')) return Icons.calculate_rounded;
    if (s.contains('eng')) return Icons.menu_book_rounded;
    if (s.contains('science')) return Icons.science_rounded;
    if (s.contains('history')) return Icons.account_balance_rounded;
    if (s.contains('computer')) return Icons.memory_rounded;
    return Icons.book_rounded;
  }

  String? _durationText() {
    if (startAt == null || endAt == null) return null;
    final diff = endAt!.difference(startAt!);
    if (diff.inMinutes <= 0) return null;
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours == 0) return '${diff.inMinutes} min';
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
  }

  String? _countdownText() {
    if (actionLabel.toLowerCase() != 'start test' || endAt == null) {
      return null;
    }
    final now = DateTime.now();
    if (now.isAfter(endAt!)) return null;
    final diff = endAt!.difference(now);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours <= 0) return 'Ends in ${diff.inMinutes} min';
    return 'Ends in ${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badge = _semanticBadge();
    final countdown = _countdownText();
    final duration = _durationText();
    final statusMessage = _statusMessage();
    final displayActionLabel = actionLabel == 'View Results'
        ? 'View Result'
        : actionLabel;

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withOpacity(0.62),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 54,
        centerTitle: true,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.16),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Test Details'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF59A3E), Color(0xFFF2800D)],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF171A1F) : const Color(0xFF20242A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2800D).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFF2800D).withOpacity(0.35),
                      ),
                    ),
                    child: Icon(_subjectIcon(), color: const Color(0xFFFFB978)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badge.bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge.text,
                  style: TextStyle(
                    color: badge.fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                statusMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFFFC48A),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (countdown != null) ...[
                const SizedBox(height: 8),
                Text(
                  countdown,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF74D99F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                height: 1,
                color: Colors.white.withOpacity(0.12),
              ),
              row('Subject', subject.isEmpty ? '-' : subject),
              if (assignedBy.isNotEmpty) row('Assigned By', assignedBy),
              if (startAt != null) row('Start Time', _formatTime(startAt)),
              if (endAt != null) row('End Time', _formatTime(endAt)),
              if (duration != null) row('Duration', duration),
              if (completedAt != null)
                row('Completed At', _formatTime(completedAt)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: actionEnabled ? onAction : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    elevation: actionEnabled ? 2 : 0,
                    backgroundColor: actionEnabled
                        ? const Color(0xFFF2800D)
                        : const Color(0xFF4A4D54),
                    foregroundColor: actionEnabled
                        ? Colors.white
                        : Colors.white.withOpacity(0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    displayActionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
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
