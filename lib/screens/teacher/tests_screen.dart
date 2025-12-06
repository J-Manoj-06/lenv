import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/test_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({super.key});

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  int _selectedTabIndex = 0;
  String _selectedClassFilter = 'All Classes';
  bool _initialLoadDone = false; // ensure we wait for auth user
  // Migration flag removed (website now writes correct studentId values).
  Timer? _ticker; // drives live countdown and status transitions

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Attempt loading once auth provider has a user
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;
    if (!_initialLoadDone && user != null) {
      _initialLoadDone = true;
      print('🚀 Initial auth ready, loading tests for ${user.uid}');
      Provider.of<TestProvider>(
        context,
        listen: false,
      ).loadTestsByTeacher(user.uid);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh when app comes back to foreground
      _loadTests();
    }
  }

  void _loadTests() {
    // Manual refresh path (pull-to-refresh)
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    print('🔁 Manual refresh - currentUser: ${user?.email}, uid: ${user?.uid}');
    if (user != null) {
      Provider.of<TestProvider>(
        context,
        listen: false,
      ).loadTestsByTeacher(user.uid);
    }
  }

  void _armTicker() {
    // Recreate ticker with cadence based on selected tab
    _ticker?.cancel();
    Duration? cadence;
    // 0=All, 1=Live, 2=Past
    if (_selectedTabIndex == 1) {
      cadence = const Duration(seconds: 2); // Live slowed to 2s cadence
    } else if (_selectedTabIndex == 0) {
      cadence = null; // All disabled (cards self-update individually)
    } else {
      cadence = null; // Past doesn't need ticking
    }
    if (cadence != null) {
      _ticker = Timer.periodic(cadence, (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1A1C20),
              ),
              child: const Icon(
                Icons.school_outlined,
                size: 60,
                color: Color(0xFF2A2D30),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Start assessing your class with ease.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first test now to get started.',
              style: TextStyle(color: Color(0xFFA0A0A0), fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<String> _buildClassFilters(List<TestModel> tests) {
    final set = <String>{'All Classes'};
    for (final t in tests) {
      final label = (t.className ?? '').isNotEmpty
          ? (t.section != null && (t.section ?? '').isNotEmpty
                ? '${t.className} - ${t.section}'
                : t.className!)
          : (t.subject.isNotEmpty ? t.subject : '');
      if (label.isNotEmpty) set.add(label);
    }
    return set.toList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testProv = Provider.of<TestProvider>(context);
    final tests = testProv.tests;
    final filters = _buildClassFilters(tests);
    if (!filters.contains(_selectedClassFilter)) {
      _selectedClassFilter = 'All Classes';
    }

    final filtered = _applyFilters(tests);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              _buildTabs(),
              Expanded(
                child: testProv.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Color(0xFF7961FF)),
                        ),
                      )
                    : filtered.isEmpty
                    ? RefreshIndicator(
                        color: const Color(0xFF7961FF),
                        onRefresh: () async {
                          _loadTests();
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                        },
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: _buildEmptyState(),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: const Color(0xFF7961FF),
                        onRefresh: () async {
                          _loadTests();
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildTestCardFromModel(filtered[i]),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          _buildFAB(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.8)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: const Text(
            'Tests',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search for a test...',
          hintStyle: const TextStyle(color: Color(0xFFA0A0A0)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFFA0A0A0)),
          filled: true,
          fillColor: const Color(0xFF1A1C20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: Color(0xFF2A2D30)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: Color(0xFF2A2D30)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9999),
            borderSide: const BorderSide(color: Color(0xFF7961FF), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        ),
        onChanged: (value) {
          setState(() {});
        },
      ),
    );
  }

  Widget _buildTabs() {
    final tabLabels = ['All Tests', 'Live', 'Scheduled', 'Completed'];
    return Container(
      color: Colors.black.withOpacity(0.8),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabLabels.length, (index) {
            final isSelected = _selectedTabIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                  _armTicker();
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF7961FF)
                        : const Color(0xFF1A1C20),
                    borderRadius: BorderRadius.circular(9999),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0xFF2A2D30)),
                  ),
                  child: Center(
                    child: Text(
                      tabLabels[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFFA0A0A0),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  List<TestModel> _applyFilters(List<TestModel> tests) {
    final query = _searchController.text.trim().toLowerCase();
    DateTime now = DateTime.now();

    // Debug logging removed to reduce console spam

    bool matchesTab(TestModel t) {
      final isLive = t.startDate.isBefore(now) && t.endDate.isAfter(now);
      final isScheduled = t.startDate.isAfter(now);
      final isPast = t.endDate.isBefore(now);

      switch (_selectedTabIndex) {
        case 0: // All
          return true;
        case 1: // Live
          return isLive;
        case 2: // Scheduled
          return isScheduled;
        case 3: // Completed
          return isPast;
        default:
          return true;
      }
    }

    bool matchesClass(TestModel t) {
      if (_selectedClassFilter == 'All Classes') return true;
      final label = (t.className ?? '').isNotEmpty
          ? (t.section != null && (t.section ?? '').isNotEmpty
                ? '${t.className} - ${t.section}'
                : t.className!)
          : (t.subject.isNotEmpty ? t.subject : '');
      return label == _selectedClassFilter;
    }

    bool matchesSearch(TestModel t) {
      if (query.isEmpty) return true;
      return t.title.toLowerCase().contains(query) ||
          t.subject.toLowerCase().contains(query);
    }

    final filtered = tests
        .where(matchesTab)
        .where(matchesClass)
        .where(matchesSearch)
        .toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Debug logging removed
    return filtered;
  }

  Widget _buildTestCardFromModel(TestModel t) {
    // Make each card self-updating every second
    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 1),
        (_) => DateTime.now(),
      ),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final isLive = t.startDate.isBefore(now) && t.endDate.isAfter(now);
        final isPast = t.endDate.isBefore(now);
        final isScheduled = t.startDate.isAfter(now);

        final statusText = isLive
            ? 'LIVE'
            : (isScheduled ? 'UPCOMING' : 'COMPLETED');
        final statusColor = isLive
            ? const Color(0xFFFFA726)
            : (isScheduled ? const Color(0xFF64B5F6) : const Color(0xFF4CAF50));
        final statusBg = isLive
            ? const Color(0xFFFFA726).withOpacity(0.2)
            : (isScheduled
                  ? const Color(0xFF64B5F6).withOpacity(0.2)
                  : const Color(0xFF4CAF50).withOpacity(0.2));

        final subtitle =
            'Subject: ${t.subject} | ${(t.className ?? '').isNotEmpty ? (t.section != null && (t.section ?? '').isNotEmpty ? '${t.className} - ${t.section}' : t.className!) : 'Class'}';

        IconData subjectIcon;
        Color iconColor;
        if (t.subject.toLowerCase().contains('math')) {
          subjectIcon = Icons.calculate_outlined;
          iconColor = const Color(0xFF4CAF50);
        } else if (t.subject.toLowerCase().contains('science')) {
          subjectIcon = Icons.science_outlined;
          iconColor = const Color(0xFFFFA726);
        } else if (t.subject.toLowerCase().contains('history')) {
          subjectIcon = Icons.history_edu_outlined;
          iconColor = const Color(0xFF64B5F6);
        } else {
          subjectIcon = Icons.school_outlined;
          iconColor = const Color(0xFF7961FF);
        }

        return _buildTestCard(
          testId: t.id,
          title: t.title,
          subtitle: subtitle,
          status: statusText,
          statusColor: statusColor,
          statusBgColor: statusBg,
          subjectIcon: subjectIcon,
          iconColor: iconColor,
          isLive: isLive,
          isPast: isPast,
          endDate: t.endDate,
          startDate: t.startDate,
          totalPoints: t.totalPoints,
          className: t.className,
          section: t.section,
          schoolCode: t.instituteId,
          onDelete: () async {
            final prov = Provider.of<TestProvider>(context, listen: false);
            final ok = await prov.deleteTest(t.id);
            if (ok && mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Deleted ${t.title}')));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Failed to delete: ${prov.errorMessage ?? 'Unknown error'}',
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }

  Future<int> _getCompletedCount(String testId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('testResults')
          .where('testId', isEqualTo: testId)
          .where('status', isEqualTo: 'completed')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getTotalStudentsInClass(
    String? className,
    String? section,
    String? schoolCode,
  ) async {
    try {
      if (className == null || section == null || schoolCode == null) {
        return 0;
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .where('className', isEqualTo: className)
          .where('section', isEqualTo: section)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting class student count: $e');
      return 0;
    }
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y, $hh:$mm';
  }

  Widget _buildTestCard({
    String? testId,
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required Color statusBgColor,
    required IconData subjectIcon,
    required Color iconColor,
    required bool isLive,
    required bool isPast,
    required DateTime endDate,
    required DateTime startDate,
    required int totalPoints,
    String? className,
    String? section,
    String? schoolCode,
    Future<void> Function()? onDelete,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/test-result',
          arguments: {
            'testId': testId ?? '',
            'name': title,
            'class': subtitle,
            'status': status,
            'endTime': '',
          },
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A2D30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFA0A0A0),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111315),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(subjectIcon, color: iconColor, size: 28),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Time/Date info - Fixed height container for consistent card sizes
            SizedBox(
              height: 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  if (isLive)
                    FutureBuilder<List<int>>(
                      future: Future.wait([
                        _getCompletedCount(testId ?? ''),
                        _getTotalStudentsInClass(
                          className,
                          section,
                          schoolCode,
                        ),
                      ]),
                      builder: (context, snapshot) {
                        final completedCount = snapshot.data?[0] ?? 0;
                        final totalCount = snapshot.data?[1] ?? 0;
                        final progress = totalCount > 0
                            ? completedCount / totalCount
                            : 0.0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2D30),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                              child: progress > 0
                                  ? FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: progress,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFA726),
                                          borderRadius: BorderRadius.circular(
                                            9999,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$completedCount / $totalCount students completed',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFA0A0A0),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  else if (isPast)
                    FutureBuilder<List<int>>(
                      future: Future.wait([
                        _getCompletedCount(testId ?? ''),
                        _getTotalStudentsInClass(
                          className,
                          section,
                          schoolCode,
                        ),
                      ]),
                      builder: (context, snapshot) {
                        final completedCount = snapshot.data?[0] ?? 0;
                        final totalCount = snapshot.data?[1] ?? 0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Completed: ${_formatDateTime(endDate)}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFA0A0A0),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2D30),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                              child: totalCount > 0 && completedCount > 0
                                  ? FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: completedCount / totalCount,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF7961FF),
                                          borderRadius: BorderRadius.circular(
                                            9999,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$completedCount / $totalCount students completed',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFA0A0A0),
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  else
                    Text(
                      'Scheduled: ${_formatDateTime(startDate)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFA0A0A0),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Footer buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7961FF).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StreamBuilder<DateTime>(
                          stream: Stream<DateTime>.periodic(
                            const Duration(seconds: 1),
                            (_) => DateTime.now(),
                          ),
                          builder: (context, snapshot) {
                            final now = snapshot.data ?? DateTime.now();
                            final remaining = endDate.difference(now);
                            final hh = remaining.inHours.toString().padLeft(
                              2,
                              '0',
                            );
                            final mm = (remaining.inMinutes % 60)
                                .toString()
                                .padLeft(2, '0');
                            final ss = (remaining.inSeconds % 60)
                                .toString()
                                .padLeft(2, '0');

                            return Row(
                              children: [
                                const Icon(
                                  Icons.timer,
                                  color: Color(0xFF7961FF),
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$hh:$mm:$ss',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF7961FF),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  )
                else if (isPast)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/test-result',
                        arguments: {
                          'testId': testId ?? '',
                          'name': title,
                          'class': subtitle,
                          'status': status,
                          'endTime': '',
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7961FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'View Results',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const SizedBox(),

                // Delete button
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111315),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF2A2D30)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    iconSize: 20,
                    color: Colors.red,
                    onPressed: () {
                      if (onDelete != null) {
                        _showDeleteDialogConfirm(title, onDelete);
                      }
                    },
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7961FF), Color(0xFFA371F7)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7961FF).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.pushNamed(context, '/create-test-entry');
            },
            customBorder: const CircleBorder(),
            child: const Center(
              child: Icon(Icons.add, size: 32, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialogConfirm(
    String testName,
    Future<void> Function() onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Test'),
          content: Text('Are you sure you want to delete "$testName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await onConfirm();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
