import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/leaderboard_service.dart';
import '../../widgets/student_bottom_nav.dart';

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

  @override
  void initState() {
    super.initState();
    _initContextAndOverall();
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
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: SingleChildScrollView(
                  key: ValueKey(_isPerTest),
                  child: Column(children: [_buildLeaderboardList(theme)]),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const StudentBottomNav(currentIndex: 3),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Column(
        children: [
          // Top bar with back button and title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: theme.iconTheme.color,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Leaderboards',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
          // Tab selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                    child: _buildTabButton(
                      theme,
                      'Overall',
                      !_isPerTest,
                      () => setState(() => _isPerTest = false),
                    ),
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
          // When Per-Test is active, place the filter just below tabs to avoid extra gaps
          if (_isPerTest) _buildFilters(theme),
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
          if (snap.connectionState == ConnectionState.waiting) {
            // Only show loader, no section title during loading
            return _loadingState(theme);
          }
          final items = snap.data ?? [];
          // Once we have the data (even if empty), show the section title
          return _buildSection(
            theme: theme,
            title: 'Overall Leaderboard',
            icon: Icons.emoji_events_rounded,
            child: items.isEmpty
                ? _emptyState(theme, 'No leaderboard data yet')
                : _listBody(theme, items),
          );
        },
      );
    } else {
      // Per-Test leaderboard
      if (_selectedTestId == null) {
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _emptyState(
            theme,
            'Select a test to view the leaderboard.',
            icon: Icons.menu_book_outlined,
          ),
        );
      }
      if (_perTestStream == null) {
        _perTestStream = _buildPerTestStream(_selectedTestId!);
      }
      return StreamBuilder<List<LeaderboardEntry>>(
        stream: _perTestStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            // Only loader during loading
            return _loadingState(theme);
          }
          final items = snap.data ?? [];
          return _buildSection(
            theme: theme,
            title: 'Per-Test Leaderboard',
            icon: Icons.menu_book_rounded,
            child: items.isEmpty
                ? _emptyState(theme, 'No results for this test yet')
                : _listBody(theme, items),
          );
        },
      );
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
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: isCurrentUser
                ? Border.all(color: const Color(0xFFF97316), width: 2)
                : Border.all(color: theme.dividerColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: isCurrentUser
                    ? const Color(0xFFF59E0B).withOpacity(0.08 + 0.12 * glow)
                    : Colors.black.withOpacity(0.05),
                blurRadius: isCurrentUser ? 12 + 6 * glow : 4,
                spreadRadius: isCurrentUser ? 1 : 0,
                offset: Offset(0, isCurrentUser ? 3 : 2),
              ),
            ],
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
                      gradient: isTopThree
                          ? LinearGradient(
                              colors: rank == 1
                                  ? const [
                                      Color(0xFFFFD700),
                                      Color(0xFFFFB300),
                                    ] // gold
                                  : rank == 2
                                  ? const [
                                      Color(0xFFC0C0C0),
                                      Color(0xFF9E9E9E),
                                    ] // silver
                                  : const [
                                      Color(0xFFCD7F32),
                                      Color(0xFF8D5524),
                                    ], // bronze
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isTopThree
                          ? null
                          : theme.brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.1)
                          : const Color(0xFFE7E5E4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color: isTopThree
                              ? Colors.white
                              : theme.textTheme.bodyMedium?.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  if (isTopThree)
                    Positioned(
                      top: -10,
                      right: -6,
                      child: Icon(
                        Icons.emoji_events_rounded,
                        size: 20,
                        color: rank == 1
                            ? const Color(0xFFFFD700)
                            : rank == 2
                            ? const Color(0xFFC0C0C0)
                            : const Color(0xFFCD7F32),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Avatar (if available)
              if (imageUrl != null) ...[
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
              Text(
                score == 0 
                    ? '0' 
                    : (score is int 
                        ? '$score' 
                        : (score % 1 == 0 
                            ? '${score.toInt()}' 
                            : score.toStringAsFixed(1))),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.currentUser?.uid;
    final email = auth.currentUser?.email;
    if (uid == null) return;

    _currentUid = uid;

    // Find student's school/class/section from students collection
    final stDoc = await FirebaseFirestore.instance
        .collection('students')
        .doc(uid)
        .get();
    Map<String, dynamic>? st;
    if (stDoc.exists) {
      st = stDoc.data();
    } else if (email != null) {
      final q = await FirebaseFirestore.instance
          .collection('students')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) st = q.docs.first.data();
    }

    _schoolCode = (st?['schoolCode'] as String?)?.trim();
    _className = (st?['className'] as String?)?.trim();
    _section = (st?['section'] as String?)?.trim();

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
    // Load tests assigned to me (published only)
    final snap = await FirebaseFirestore.instance
        .collection('tests')
        .where('assignedStudentIds', arrayContains: uid)
        .where('status', isEqualTo: 'published')
        .get();
    _myTests = snap.docs.map((d) => TestModel.fromJson(d.data())).toList();
  }

  // Build a stream for overall leaderboard from school path; fallback to service
  Stream<List<LeaderboardEntry>> _buildOverallStream() {
    if (_schoolCode == null || _schoolCode!.isEmpty) {
      return const Stream.empty();
    }
    final schoolRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolCode);

    // Attempt 1: subcollection at leaderboards/overall (collection of entries)
    final attempt1Stream = schoolRef
        .collection('leaderboards')
        .doc('overall')
        .collection('entries')
        .orderBy('score', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snap) async {
          final list1 = _mapEntries(snap.docs);
          // If Firestore has entries but all scores are zero (or missing),
          // fall back to computing from testResults for accuracy.
          final hasAnyNonZero = list1.any((e) => (e.score is num) && (e.score as num) > 0);
          if (list1.isNotEmpty && hasAnyNonZero) return list1;
          // Attempt 2: collection 'leaderboards_overall'
          final snap2 = await schoolRef
              .collection('leaderboards_overall')
              .orderBy('score', descending: true)
              .limit(100)
              .get();
          final list2 = _mapEntries(snap2.docs);
          final hasAnyNonZero2 = list2.any((e) => (e.score is num) && (e.score as num) > 0);
          if (list2.isNotEmpty && hasAnyNonZero2) return list2;
          // Fallback to compute via service once
          return _leaderboardService.getOverallLeaderboardForClass(
            schoolCode: _schoolCode!,
            className: _className ?? '',
            section: _section,
            limit: 100,
          );
        });
    return attempt1Stream;
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
