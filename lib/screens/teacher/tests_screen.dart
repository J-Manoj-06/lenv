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
  Timer? _tabSwitchDebounce; // debounce rapid tab switching

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
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7A5CFF).withOpacity(0.15),
                    const Color(0xFF9D7FFF).withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                Icons.assignment_outlined,
                size: 48,
                color: const Color(0xFF7A5CFF).withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'No Tests Yet',
              style: TextStyle(
                color: theme.textTheme.bodyLarge?.color,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Create your first test to start\nassessing student performance',
              style: TextStyle(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                fontSize: 15,
                height: 1.5,
              ),
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
    _tabSwitchDebounce?.cancel();
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
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
                          valueColor: AlwaysStoppedAnimation(Color(0xFF355872)),
                        ),
                      )
                    : filtered.isEmpty
                    ? RefreshIndicator(
                        color: const Color(0xFF355872),
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
                        color: const Color(0xFF355872),
                        onRefresh: () async {
                          _loadTests();
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                        },
                        child: ListView.builder(
                          key: ValueKey(_selectedTabIndex),
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(color: isDark ? Colors.black : Colors.white),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Tests',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search tests...',
            hintStyle: TextStyle(
              color: isDark
                  ? Colors.white.withOpacity(0.4)
                  : Colors.grey.withOpacity(0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search,
              color: isDark
                  ? Colors.white.withOpacity(0.5)
                  : Colors.grey.withOpacity(0.6),
              size: 20,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabLabels = ['All Tests', 'Live', 'Scheduled', 'Completed'];
    return Container(
      color: isDark ? Colors.black : Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabLabels.length, (index) {
            final isSelected = _selectedTabIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    // Debounce rapid tab switches
                    _tabSwitchDebounce?.cancel();
                    _tabSwitchDebounce = Timer(
                      const Duration(milliseconds: 200),
                      () {
                        if (mounted) {
                          setState(() {
                            _selectedTabIndex = index;
                          });
                          _armTicker();
                        }
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF355872)
                          : Colors.transparent,
                      border: isSelected
                          ? null
                          : Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.grey.withOpacity(0.3),
                              width: 1.5,
                            ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF355872,
                                ).withOpacity(0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        tabLabels[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : theme.textTheme.bodySmall?.color?.withOpacity(
                                  0.7,
                                ),
                          letterSpacing: 0.3,
                        ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
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
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.grey.withOpacity(0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status badge and icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.textTheme.bodyLarge?.color,
                            letterSpacing: -0.3,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(subjectIcon, color: iconColor, size: 24),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Content based on test status
              if (isLive)
                FutureBuilder<List<int>>(
                  future: Future.wait([
                    _getCompletedCount(testId ?? ''),
                    _getTotalStudentsInClass(className, section, schoolCode),
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
                        // Progress bar
                        Container(
                          width: double.infinity,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.dividerColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: progress > 0
                              ? FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF97316),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        // Completion stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$completedCount / $totalCount responses',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF97316,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF97316),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Timer
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFF97316).withOpacity(0.25),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.timer_outlined,
                                    color: Color(0xFFF97316),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  StreamBuilder<DateTime>(
                                    stream: Stream<DateTime>.periodic(
                                      const Duration(seconds: 1),
                                      (_) => DateTime.now(),
                                    ),
                                    builder: (context, snapshot) {
                                      final now =
                                          snapshot.data ?? DateTime.now();
                                      final remaining = endDate.difference(now);
                                      final hh = remaining.inHours
                                          .toString()
                                          .padLeft(2, '0');
                                      final mm = (remaining.inMinutes % 60)
                                          .toString()
                                          .padLeft(2, '0');
                                      final ss = (remaining.inSeconds % 60)
                                          .toString()
                                          .padLeft(2, '0');

                                      return Text(
                                        '$hh:$mm:$ss',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFF97316),
                                          letterSpacing: 0.3,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              Text(
                                'Live now',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(
                                    0xFFF97316,
                                  ).withOpacity(0.8),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
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
                    _getTotalStudentsInClass(className, section, schoolCode),
                  ]),
                  builder: (context, snapshot) {
                    final completedCount = snapshot.data?[0] ?? 0;
                    final totalCount = snapshot.data?[1] ?? 0;
                    final percentage = totalCount > 0
                        ? ((completedCount / totalCount) * 100)
                        : 0.0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Completion Rate',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF10B981,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${percentage.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.dividerColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: totalCount > 0 && completedCount > 0
                              ? FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: completedCount / totalCount,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Completed: ${_formatDateTime(endDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$completedCount of $totalCount students',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.5),
                          ),
                        ),
                      ],
                    );
                  },
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: const Color(0xFF3B82F6).withOpacity(0.7),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Starts: ${_formatDateTime(startDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Scheduled',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF3B82F6),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 14),

              // Action buttons
              if (isPast)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7961FF),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7961FF).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: InkWell(
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
                      child: const Text(
                        'View Results',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (onDelete != null) {
                            _showDeleteDialogConfirm(title, onDelete);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: theme.colorScheme.error.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF7961FF),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7961FF).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => Navigator.pushNamed(context, '/create-test-entry'),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          child: const Icon(Icons.add, size: 28),
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
