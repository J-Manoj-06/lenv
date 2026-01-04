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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
    final bgColor = theme.scaffoldBackgroundColor;

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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text(
            'Tests',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.textTheme.bodyLarge?.color,
              letterSpacing: -1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: theme.textTheme.bodyLarge?.color, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search tests...',
          hintStyle: TextStyle(
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.5),
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
            size: 22,
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF1C1E22) : const Color(0xFFF5F5F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.08),
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.08),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: const Color(0xFF7A5CFF).withOpacity(0.6),
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabLabels = ['All Tests', 'Live', 'Scheduled', 'Completed'];
    return Container(
      color: theme.scaffoldBackgroundColor,
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
                    setState(() {
                      _selectedTabIndex = index;
                    });
                    _armTicker();
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xFF7A5CFF), Color(0xFF9D7FFF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected
                          ? null
                          : (isDark
                                ? const Color(0xFF1C1E22)
                                : const Color(0xFFF5F5F7)),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF7A5CFF,
                                ).withOpacity(0.35),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : theme.textTheme.bodySmall?.color?.withOpacity(
                                  0.65,
                                ),
                          letterSpacing: 0.2,
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1E22) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF2A2D35).withOpacity(0.5)
                  : const Color(0xFFE5E5E7),
              width: 1,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: theme.textTheme.bodyLarge?.color,
                            letterSpacing: -0.4,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.6),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          iconColor.withOpacity(0.15),
                          iconColor.withOpacity(0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(subjectIcon, color: iconColor, size: 24),
                  ),
                ],
              ),

              const SizedBox(height: 12),

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
                                height: 4,
                                decoration: BoxDecoration(
                                  color: theme.dividerColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: progress > 0
                                    ? FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: progress,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFFFFA726),
                                                Color(0xFFFFB74D),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$completedCount / $totalCount students completed',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.55),
                                  fontWeight: FontWeight.w500,
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
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: theme.dividerColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: totalCount > 0 && completedCount > 0
                                    ? FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor:
                                            completedCount / totalCount,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF7A5CFF),
                                                Color(0xFF9D7FFF),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$completedCount / $totalCount students completed',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodySmall?.color
                                      ?.withOpacity(0.55),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    else
                      Text(
                        'Scheduled: ${_formatDateTime(startDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.6,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

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
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF7A5CFF).withOpacity(0.15),
                            const Color(0xFF9D7FFF).withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
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
                                  Icon(
                                    Icons.timer_outlined,
                                    color: const Color(0xFF7A5CFF),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$hh:$mm:$ss',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF7A5CFF),
                                      letterSpacing: 0.3,
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
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7A5CFF), Color(0xFF9D7FFF)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7A5CFF).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
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
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'View Results',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(),

                  // Delete button
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
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: theme.colorScheme.error.withOpacity(0.7),
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
          gradient: const LinearGradient(
            colors: [Color(0xFF7A5CFF), Color(0xFF9D7FFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7A5CFF).withOpacity(0.4),
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
