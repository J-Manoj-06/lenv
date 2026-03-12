// ignore_for_file: unused_element, unused_field
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/leaderboard_service.dart';
import 'per_test_leaderboard_detail.dart';

class KeyedSubtree extends StatelessWidget {
  @override
  final Key key;
  final Widget child;

  const KeyedSubtree({required this.key, required this.child})
    : super(key: key);

  @override
  Widget build(BuildContext context) => child;
}

class StudentLeaderboardScreen extends StatefulWidget {
  const StudentLeaderboardScreen({super.key});

  @override
  State<StudentLeaderboardScreen> createState() =>
      _StudentLeaderboardScreenState();
}

class _StudentLeaderboardScreenState extends State<StudentLeaderboardScreen> {
  // Default to Overall tab selected
  bool _isPerTest = false;
  String? _selectedTestId;
  String _selectedTestLabel = 'Test Name';

  final _leaderboardService = LeaderboardService();

  Stream<List<LeaderboardEntry>>? _overallStream;
  Stream<List<LeaderboardEntry>>? _perTestStream;
  List<TestModel> _myTests = const [];
  String? _schoolCode;
  String? _className;
  String? _section;
  String? _currentUid;

  // ✅ OPTIMIZATION: Cache streams to avoid recreating them
  Stream<List<LeaderboardEntry>>? _cachedOverallStream;
  final Map<String, Stream<List<LeaderboardEntry>>> _cachedPerTestStreams = {};
  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Wait for auth to initialize before loading leaderboard data
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.ensureInitialized();
      if (!mounted) return;
      await _initContextAndOverall();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final beginOffset = _isPerTest
                      ? const Offset(
                          1.0,
                          0.0,
                        ) // slide in from right when going to per-test
                      : const Offset(
                          -1.0,
                          0.0,
                        ); // slide in from left when returning to overall
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: beginOffset,
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                // Overall: scrollable (list height can exceed viewport)
                // Per-Test: internal Column manages its own Expanded ListView
                child: _isPerTest
                    ? KeyedSubtree(
                        key: const ValueKey('perTestView'),
                        child: _buildLeaderboardList(theme),
                      )
                    : SingleChildScrollView(
                        key: const ValueKey('overallView'),
                        child: Column(children: [_buildLeaderboardList(theme)]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Column(
        children: [
          // Top bar with back button and title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Removed back button - use bottom navigation instead
                Expanded(
                  child: Text(
                    'Leaderboards',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tab selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Container(
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.1)
                    : const Color(0xFFF5F5F4),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(theme, 'Overall', !_isPerTest, () {
                      if (_isPerTest) {
                        // Switching from Per-Test to Overall - recreate stream
                        setState(() {
                          _isPerTest = false;
                          _overallStream = _buildOverallStream();
                        });
                      }
                    }),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      theme,
                      'Per-Test',
                      _isPerTest,
                      () => setState(() => _isPerTest = true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Per-Test shows test cards inline; no filter row
        ],
      ),
    );
  }

  Widget _buildTabButton(
    ThemeData theme,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFFF8A00), Color(0xFFFF6A00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? null
              : Border.all(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.2)
                      : const Color(0xFFFFE0B3),
                  width: 2,
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF97316).withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : theme.textTheme.bodyMedium?.color?.withOpacity(0.6),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildFilterChip(
              theme,
              _selectedTestLabel,
              true,
              () => _showFilterDialog('Test Name'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    ThemeData theme,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFfcb045), Color(0xFFf27f0d)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isSelected
              ? null
              : isDark
              ? const Color(0xFF2A2A2A)
              : const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFf27f0d)
                : const Color(0xFFf27f0d).withOpacity(0.6),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFf27f0d).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 18,
              color: isSelected ? Colors.white : const Color(0xFFf27f0d),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: isSelected ? Colors.white : const Color(0xFFf27f0d),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: isSelected ? Colors.white : const Color(0xFFf27f0d),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardList(ThemeData theme) {
    if (!_isPerTest) {
      // Overall leaderboard
      if (_overallStream == null) {
        _initContextAndOverall();
        return _loadingState(theme);
      }
      return StreamBuilder<List<LeaderboardEntry>>(
        stream: _overallStream,
        builder: (context, snap) {
          // Show loading only while waiting for FIRST data
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return _loadingState(theme);
          }
          final items = snap.data ?? [];
          // Once we have the data (even if empty), show the section title
          // Remove header (trophy + text). Keep subtle spacing above list.
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _emptyState(theme, 'No leaderboard data yet'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              _listBody(theme, items),
              const SizedBox(height: 6),
            ],
          );
        },
      );
    } else {
      // Per-Test: show test cards with search
      final uid = _currentUid;
      if (uid == null) {
        return _loadingState(theme);
      }
      return _PerTestTab(studentId: uid, theme: theme);
    }
  }

  // Consistent loading UI aligned with section content
  Widget _loadingState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required ThemeData theme,
    required String title,
    required Widget child,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),
        child,
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _listBody(ThemeData theme, List<LeaderboardEntry> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items
            .map(
              (e) => _buildLeaderboardCard(theme, {
                'rank': e.rank,
                'name': e.name,
                'score': e.score,
                'isCurrentUser': e.studentId == _currentUid,
                'imageUrl': e.photoUrl,
              }),
            )
            .toList(),
      ),
    );
  }

  Widget _emptyState(
    ThemeData theme,
    String message, {
    IconData icon = Icons.hourglass_empty,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyLarge?.color?.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardCard(ThemeData theme, Map<String, dynamic> item) {
    final int rank = item['rank'];
    final String name = item['name'];
    final num score = item['score'] is num ? item['score'] as num : 0;
    final bool hasVerified = item['hasVerified'] ?? false;
    final bool hasFire = item['hasFire'] ?? false;
    final bool isCurrentUser = item['isCurrentUser'] ?? false;
    final String? imageUrl = item['imageUrl'];

    final bool isTopThree = rank <= 3;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: 0.0, end: isCurrentUser ? 1.0 : 0.0),
      builder: (context, glow, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isCurrentUser
                ? const Color(0xFFFF7B00).withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: null,
            boxShadow: isCurrentUser
                ? [
                    BoxShadow(
                      color: const Color(
                        0xFFFF7A00,
                      ).withOpacity(0.15 + 0.15 * glow),
                      blurRadius: 12 + 6 * glow,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Rank badge with crown for top 3
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: rank == 1
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFFCD34D),
                                Color(0xFFFBBF24),
                                Color(0xFFF59E0B),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : rank == 2
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFE2E8F0),
                                Color(0xFFCBD5E1),
                                Color(0xFF94A3B8),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : rank == 3
                          ? const LinearGradient(
                              colors: [
                                Color(0xFFF59E0B),
                                Color(0xFFD97706),
                                Color(0xFFB45309),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: !isTopThree ? const Color(0xFF333333) : null,
                      border: !isTopThree
                          ? Border.all(color: const Color(0xFF555555), width: 1)
                          : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: isTopThree
                          ? Text(
                              rank == 1
                                  ? '🥇'
                                  : rank == 2
                                  ? '🥈'
                                  : '🥉',
                              style: const TextStyle(fontSize: 28),
                            )
                          : Text(
                              '$rank',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Avatar (if available)
              if (imageUrl != null && imageUrl.isNotEmpty) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    image: DecorationImage(
                      image: NetworkImage(imageUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Name with badges
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasVerified) ...[
                      const SizedBox(width: 6),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                        ).createShader(bounds),
                        child: const Icon(
                          Icons.verified,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                    if (hasFire) ...[
                      const SizedBox(width: 6),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                        ).createShader(bounds),
                        child: const Icon(
                          Icons.local_fire_department,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Score
              // Score with star icon
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF7A00), Color(0xFFFF9500)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF7A00).withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      score == 0
                          ? '0'
                          : (score is int
                                ? '$score'
                                : (score % 1 == 0
                                      ? '${score.toInt()}'
                                      : score.toStringAsFixed(1))),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilterDialog(String filterType) async {
    if (filterType == 'Test Name') {
      await _ensureTestsLoaded();
      if (!mounted) return;
      final selected = await _showModernTestSelector(context);
      if (selected != null) {
        setState(() {
          _selectedTestId = selected.id;
          _selectedTestLabel = selected.title;
          _perTestStream = _buildPerTestStream(selected.id);
        });
      }
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$filterType filter coming soon!')));
  }

  /// 🎨 Modern Test Selector Dialog with smooth animations and theme support
  Future<TestModel?> _showModernTestSelector(BuildContext context) async {
    return await showDialog<TestModel>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return _ModernTestSelectorDialog(
          tests: _myTests,
          selectedTestId: _selectedTestId,
        );
      },
    );
  }

  Future<void> _initContextAndOverall() async {
    if (!mounted) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.currentUser?.uid;
    final email = auth.currentUser?.email;
    if (uid == null) {
      return;
    }

    _currentUid = uid;

    // Find student's school/class/section from students collection
    final stDoc = await FirebaseFirestore.instance
        .collection('students')
        .doc(uid)
        .get();

    if (!mounted) return;

    Map<String, dynamic>? st;
    if (stDoc.exists) {
      st = stDoc.data();
    } else if (email != null) {
      final q = await FirebaseFirestore.instance
          .collection('students')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (!mounted) return;

      if (q.docs.isNotEmpty) {
        st = q.docs.first.data();
      }
    }

    _schoolCode = (st?['schoolCode'] as String?)?.trim();
    _className = (st?['className'] as String?)?.trim();
    _section = (st?['section'] as String?)?.trim();

    // Treat empty strings as null to avoid filtering issues
    if (_schoolCode != null && _schoolCode!.isEmpty) _schoolCode = null;
    if (_className != null && _className!.isEmpty) _className = null;
    if (_section != null && _section!.isEmpty) _section = null;

    if (!mounted) return;

    if (_schoolCode != null && _className != null) {
      setState(() {
        _overallStream = _buildOverallStream();
      });
    }
  }

  Future<void> _ensureTestsLoaded() async {
    if (_myTests.isNotEmpty) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.currentUser?.uid;
    if (uid == null) return;

    // Load tests assigned to me from testResults collection
    final assignmentsSnap = await FirebaseFirestore.instance
        .collection('testResults')
        .where('studentId', isEqualTo: uid)
        .where('status', whereIn: ['assigned', 'started', 'completed'])
        .get();

    // Extract unique test IDs
    final testIds = assignmentsSnap.docs
        .map((doc) => doc.data()['testId'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .toList();

    if (testIds.isEmpty) {
      _myTests = [];
      return;
    }

    // Fetch test details from scheduledTests in batches (10 at a time due to whereIn limit)
    _myTests = [];
    for (var i = 0; i < testIds.length; i += 10) {
      final batch = testIds.skip(i).take(10).toList();
      final testsSnap = await FirebaseFirestore.instance
          .collection('scheduledTests')
          .where(FieldPath.documentId, whereIn: batch)
          .get();

      for (var doc in testsSnap.docs) {
        try {
          final test = TestModel.fromScheduledTest(doc.id, doc.data());
          // Only include published tests
          if (test.status == TestStatus.published) {
            _myTests.add(test);
          }
        } catch (e) {}
      }
    }
  }

  // Build a stream for overall leaderboard from school path; fallback to service
  Stream<List<LeaderboardEntry>> _buildOverallStream() {
    if (_schoolCode == null || _schoolCode!.isEmpty) {
      return const Stream.empty();
    }

    // ✅ OPTIMIZATION: Use cached stream with instant display + real-time updates
    // Emits cached data immediately (0s) then listens for real-time updates

    return _leaderboardService.getOverallLeaderboardStreamForClass(
      schoolCode: _schoolCode!,
      className: _className ?? '',
      section: _section,
      limit: 100,
    );
  }

  // Build per-test leaderboard stream from school path; fallback to service
  Stream<List<LeaderboardEntry>> _buildPerTestStream(String testId) {
    // Don't filter by schoolCode initially - let the service handle it
    final schoolRef = _schoolCode != null && _schoolCode!.isNotEmpty
        ? FirebaseFirestore.instance.collection('schools').doc(_schoolCode)
        : null;

    // Try school-based path first
    if (schoolRef != null) {
      return schoolRef
          .collection('tests')
          .doc(testId)
          .collection('leaderboard')
          .orderBy('score', descending: true)
          .limit(100)
          .snapshots()
          .asyncMap((snap) async {
            final list1 = _mapEntries(snap.docs);
            if (list1.isNotEmpty) return list1;
            // Fallback: query testResults directly without schoolCode filter
            return _leaderboardService.getPerTestLeaderboard(
              testId: testId,
              schoolCode: null, // Don't filter by schoolCode
            );
          });
    }

    // Direct query if no school context
    return Stream.fromFuture(
      _leaderboardService.getPerTestLeaderboard(
        testId: testId,
        schoolCode: null,
      ),
    );
  }

  List<LeaderboardEntry> _mapEntries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = docs.map((d) => d.data()).toList();
    items.sort(
      (a, b) => ((b['score'] ?? b['points']) as num).compareTo(
        (a['score'] ?? a['points']) as num,
      ),
    );
    final list = <LeaderboardEntry>[];
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      list.add(
        LeaderboardEntry(
          studentId: (e['studentId'] ?? e['uid'] ?? '') as String,
          name: (e['name'] ?? e['studentName'] ?? 'Student') as String,
          photoUrl: e['photoUrl'] as String?,
          rank: i + 1,
          score: (e['score'] ?? e['points'] ?? 0) as num,
        ),
      );
    }
    return list;
  }
}

/// 🔍 Per-Test Tab with Live Search
/// Completely isolated widget with its own state management
class _PerTestTab extends StatefulWidget {
  final String studentId;
  final ThemeData theme;

  const _PerTestTab({required this.studentId, required this.theme});

  @override
  State<_PerTestTab> createState() => _PerTestTabState();
}

class _PerTestTabState extends State<_PerTestTab> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('testResults')
          .where('studentId', isEqualTo: widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoading();
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmpty('No tests assigned yet');
        }

        // Extract unique tests
        final testMap = <String, Map<String, dynamic>>{};
        for (final doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final testId = data['testId'] as String?;
          if (testId != null && !testMap.containsKey(testId)) {
            testMap[testId] = data;
          }
        }

        var tests = testMap.values.toList();
        tests.sort((a, b) {
          final aDate = (a['assignedAt'] as Timestamp?)?.toDate();
          final bDate = (b['assignedAt'] as Timestamp?)?.toDate();
          if (aDate == null || bDate == null) return 0;
          return bDate.compareTo(aDate);
        });

        return tests.isEmpty
            ? _buildEmpty('No tests assigned yet')
            : _buildTestList(tests);
      },
    );
  }

  Widget _buildTestList(List<Map<String, dynamic>> tests) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: tests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 15),
      itemBuilder: (context, index) {
        final t = tests[index];
        final title = t['testTitle'] as String? ?? 'Unnamed Test';
        final subject = t['subject'] as String? ?? '';
        final assignedAt = (t['assignedAt'] as Timestamp?)?.toDate();
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
                    testId: t['testId'] as String,
                    testTitle: title,
                    subject: subject,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: widget.theme.brightness == Brightness.dark
                    ? const Color(0xFF1A1A1A)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.theme.brightness == Brightness.dark
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
                      color: widget.theme.brightness == Brightness.dark
                          ? const Color(0xFF27272A)
                          : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.menu_book,
                      color: widget.theme.brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF1A1D21),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: widget.theme.brightness == Brightness.dark
                                ? Colors.white
                                : const Color(0xFF1A1D21),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subject.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subject,
                            style: TextStyle(
                              color: widget.theme.brightness == Brightness.dark
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
                              color: widget.theme.brightness == Brightness.dark
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
                    color: widget.theme.brightness == Brightness.dark
                        ? Colors.white30
                        : Colors.black26,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(
          widget.theme.brightness == Brightness.dark
              ? Colors.white
              : const Color(0xFFf27f0d),
        ),
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: widget.theme.brightness == Brightness.dark
              ? Colors.white54
              : Colors.black54,
          fontSize: 16,
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

/// 🎨 Modern Test Selector Dialog Widget
/// Beautiful, animated dialog with gradient selections and theme support
class _ModernTestSelectorDialog extends StatefulWidget {
  final List<TestModel> tests;
  final String? selectedTestId;

  const _ModernTestSelectorDialog({required this.tests, this.selectedTestId});

  @override
  State<_ModernTestSelectorDialog> createState() =>
      _ModernTestSelectorDialogState();
}

class _ModernTestSelectorDialogState extends State<_ModernTestSelectorDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  String _searchQuery = '';
  String? _hoveredTestId;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _closeDialog([TestModel? selectedTest]) {
    _animationController.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop(selectedTest);
      }
    });
  }

  List<TestModel> get _filteredTests {
    if (_searchQuery.isEmpty) return widget.tests;
    return widget.tests
        .where(
          (test) =>
              test.title.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 32,
            vertical: 80,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with title and close button
                _buildHeader(theme, isDark),

                // Search bar
                if (widget.tests.length > 5) _buildSearchBar(theme, isDark),

                // Test list
                Flexible(
                  child: widget.tests.isEmpty
                      ? _buildEmptyState(theme, isDark)
                      : _buildTestList(theme, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFfcb045), Color(0xFFf27f0d)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select Test',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFFf27f0d),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _closeDialog(),
            icon: Icon(
              Icons.close_rounded,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search tests...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFFf27f0d)),
          filled: true,
          fillColor: isDark
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFFfce6d1).withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildTestList(ThemeData theme, bool isDark) {
    final filteredTests = _filteredTests;

    if (filteredTests.isEmpty) {
      return _buildEmptyState(theme, isDark);
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredTests.length,
      itemBuilder: (context, index) {
        final test = filteredTests[index];
        final isSelected = test.id == widget.selectedTestId;
        final isHovered = test.id == _hoveredTestId;

        return MouseRegion(
          onEnter: (_) => setState(() => _hoveredTestId = test.id),
          onExit: (_) => setState(() => _hoveredTestId = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFFfcb045), Color(0xFFf27f0d)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected
                  ? null
                  : isHovered
                  ? const Color(0xFFfce6d1)
                  : isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFf27f0d)
                    : isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFf27f0d).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _closeDialog(test),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // Test icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withOpacity(0.2)
                              : const Color(0xFFf27f0d).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.assignment_outlined,
                          size: 18,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFFf27f0d),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Test name
                      Expanded(
                        child: Text(
                          test.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : isHovered
                                ? const Color(0xFFf27f0d)
                                : isDark
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                      // Check icon for selected
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Color(0xFFf27f0d),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFfce6d1).withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _searchQuery.isEmpty
                  ? Icons.assignment_outlined
                  : Icons.search_off_rounded,
              size: 48,
              color: const Color(0xFFf27f0d).withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No tests available' : 'No tests found',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Tests will appear here once assigned'
                : 'Try a different search term',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}

// Bottom nav is centralized in StudentBottomNav widget.
