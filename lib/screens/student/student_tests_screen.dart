import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/test_model.dart';
import '../../models/test_result_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/firestore_service.dart';

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
        testProvider.loadAvailableTests(auth.currentUser!.uid);
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
      backgroundColor: isDark ? const Color(0xFF111827) : const Color(0xFFF7F3EF),
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
                    color: isDark ? Colors.grey.shade800 : const Color(0xFFE8DBCE),
                  ),
                ),
                color: isDark ? Colors.black.withOpacity(0.1) : Colors.white.withOpacity(0.8),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: isDark ? Colors.white : const Color(0xFF1C140D),
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                unselectedLabelColor: isDark ? Colors.grey.shade500 : const Color(0xFF9C7349),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.black.withOpacity(0.1) : Colors.white.withOpacity(0.8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : const Color(0xFF1C140D)),
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: 40.0),
              child: Text(
                'Assigned Tests',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C140D),
                ),
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
          .map((s) => s.docs.map((d) => TestModel.fromJson(d.data())).toList()),
      builder: (context, pendingSnap) {
        return StreamBuilder<List<TestResultModel>>(
          stream: firestore.getTestResultsByStudent(studentId),
          builder: (context, completedSnap) {
            if ((pendingSnap.connectionState == ConnectionState.waiting) ||
                (completedSnap.connectionState == ConnectionState.waiting)) {
              return const Center(child: CircularProgressIndicator());
            }

            final pending = (pendingSnap.data ?? [])
                .where((t) => t.status == TestStatus.published)
                .toList();
            final completed = completedSnap.data ?? [];

            // Merge lists into a unified view model
            final items = <_TestListItem>[];
            for (final t in pending) {
              items.add(_TestListItem.pending(test: t));
            }
            for (final r in completed) {
              items.add(_TestListItem.completed(result: r));
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
    return Consumer<TestProvider>(
      builder: (context, provider, child) {
        final pending = provider.tests
            .where((t) => t.status == TestStatus.published)
            .toList();
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (pending.isEmpty) {
          return const _EmptyState(message: 'No pending tests');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemBuilder: (ctx, i) => _TestCard(
            item: _TestListItem.pending(test: pending[i]),
          ),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: pending.length,
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
    return StreamBuilder<List<TestResultModel>>(
      stream: firestore.getTestResultsByStudent(studentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return const _EmptyState(message: 'No completed tests');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemBuilder: (ctx, i) => _TestCard(
            item: _TestListItem.completed(result: results[i]),
          ),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: results.length,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.quiz_outlined,
                size: 48, color: isDark ? Colors.white38 : Colors.black38),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
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

  _TestListItem.pending({required this.test})
      : result = null,
        isPending = true;
  _TestListItem.completed({required this.result})
      : test = null,
        isPending = false;
}

class _TestCard extends StatelessWidget {
  final _TestListItem item;
  const _TestCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('MMM d, yyyy');

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

    if (item.isPending) {
      final t = item.test!;
      title = t.title;
      subject = t.subject;
      assignedBy = t.teacherName;
      dateLabel = 'Due Date:';
      dateValue = fmt.format(t.endDate);
      buttonText = 'Start Test';
      onPressed = () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test attempt is coming soon.'),
          ),
        );
      };
      leadingIcon = Icons.quiz;
      leadingBg = const Color(0xFFFEF2E6);
      leadingFg = const Color(0xFFF2800D);
      statusBg = const Color(0xFFF2800D);
      statusText = Colors.white;
      statusLabel = 'Pending';
    } else {
      final r = item.result!;
      title = r.testTitle;
      subject = r.subject;
      assignedBy = '';
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
        color: isDark ? Colors.grey.shade800.withOpacity(0.5) : Colors.white,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1C140D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Subject: ',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : const Color(0xFF9C7349),
                          ),
                        ),
                        Text(
                          subject,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1C140D),
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
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : const Color(0xFF9C7349),
                            ),
                          ),
                          Text(
                            assignedBy,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1C140D),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            color: isDark ? Colors.grey.shade700 : const Color(0xFFE8DBCE),
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
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : const Color(0xFF9C7349),
                    ),
                  ),
                  Text(
                    dateValue,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1C140D),
                    ),
                  ),
                ],
              ),
              _PrimaryButton(label: buttonText, onPressed: onPressed, isPrimary: item.isPending),
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
  const _PrimaryButton({required this.label, required this.onPressed, this.isPrimary = true});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(100, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: isPrimary ? const Color(0xFFF2800D) : Colors.white,
        foregroundColor: isPrimary ? Colors.white : const Color(0xFF1C140D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isPrimary ? Colors.transparent : const Color(0xFFE8DBCE))),
        elevation: isPrimary ? 1 : 0,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
