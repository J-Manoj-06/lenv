import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/leaderboard_service.dart';

class StudentLeaderboardScreen extends StatefulWidget {
  const StudentLeaderboardScreen({super.key});

  @override
  State<StudentLeaderboardScreen> createState() =>
      _StudentLeaderboardScreenState();
}

class _StudentLeaderboardScreenState extends State<StudentLeaderboardScreen> {
  // Default to Overall tab selected
  bool _isPerTest = false;
  String _selectedSubject = 'Subject';
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
    return Scaffold(
      backgroundColor: const Color(0xFFFCFBF8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: SingleChildScrollView(
                  key: ValueKey(_isPerTest),
                  child: Column(
                    children: [
                      // Filters are only relevant for Per-Test view
                      if (_isPerTest) _buildFilters(),
                      _buildLeaderboardList(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFBF8).withOpacity(0.8),
      ),
      child: Column(
        children: [
          // Top bar with back button and title
          Padding(
            padding: const EdgeInsets.all(16),
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
                    icon: const Icon(Icons.arrow_back, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Leaderboards',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF292524),
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
          // Tab selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F4),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTabButton(
                      'Overall',
                      !_isPerTest,
                      () => setState(() => _isPerTest = false),
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      'Per-Test',
                      _isPerTest,
                      () => setState(() => _isPerTest = true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Removed extra vertical space
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
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
              : Border.all(color: const Color(0xFFFFE0B3), width: 2),
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
            color: isSelected ? Colors.white : const Color(0xFF78716C),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildFilterChip(
            _selectedSubject,
            true,
            () => _showFilterDialog('Subject'),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            _selectedTestLabel,
            false,
            () => _showFilterDialog('Test Name'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEA580C).withOpacity(0.1)
              : const Color(0xFFE7E5E4).withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFEA580C)
                : const Color(0xFFD6D3D1),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? const Color(0xFFEA580C)
                    : const Color(0xFF78716C),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 16,
              color: isSelected
                  ? const Color(0xFFEA580C)
                  : const Color(0xFF78716C),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderboardList() {
    if (!_isPerTest) {
      // Overall leaderboard
      if (_overallStream == null) {
        _initContextAndOverall();
        return const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return _buildSection(
        title: '🏆 Overall Leaderboard',
        child: StreamBuilder<List<LeaderboardEntry>>(
          stream: _overallStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return _emptyState('No leaderboard data yet 🕒');
            }
            return _listBody(items);
          },
        ),
      );
    } else {
      // Per-Test leaderboard
      if (_selectedTestId == null) {
        return _emptyState(
          'Select a test to view the leaderboard.',
          icon: Icons.menu_book_outlined,
        );
      }
      if (_perTestStream == null) {
        _perTestStream = _buildPerTestStream(_selectedTestId!);
      }
      return _buildSection(
        title: '📘 Per-Test Leaderboard',
        child: StreamBuilder<List<LeaderboardEntry>>(
          stream: _perTestStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return _emptyState('No results for this test yet 🕒');
            }
            return _listBody(items);
          },
        ),
      );
    }
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF292524),
              ),
            ),
          ),
          child,
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _listBody(List<LeaderboardEntry> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: items
            .map(
              (e) => _buildLeaderboardCard({
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

  Widget _emptyState(String message, {IconData icon = Icons.hourglass_empty}) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Icon(icon, size: 48, color: const Color(0xFFB45309)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF78716C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardCard(Map<String, dynamic> item) {
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
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: isCurrentUser
                ? Border.all(color: const Color(0xFFF97316), width: 2)
                : null,
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
          padding: const EdgeInsets.all(12),
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
                      color: isTopThree ? null : const Color(0xFFE7E5E4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color: isTopThree
                              ? Colors.white
                              : const Color(0xFF57534E),
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
              const SizedBox(width: 16),
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
                const SizedBox(width: 16),
              ],
              // Name with badges
              Expanded(
                child: Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Color(0xFF292524),
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
                score is int ? '$score' : score.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF292524),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.8),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                label: 'Home',
                isSelected: false,
                onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/student-dashboard',
                  (route) => false,
                ),
              ),
              _NavItem(
                icon: Icons.assignment_outlined,
                label: 'Tests',
                isSelected: false,
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/student-tests'),
              ),
              _NavItem(
                icon: Icons.workspace_premium_outlined,
                label: 'Rewards',
                isSelected: false,
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/student-rewards'),
              ),
              _NavItem(
                icon: Icons.leaderboard,
                label: 'Leaderboard',
                isSelected: true,
                isFilled: true,
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                isSelected: false,
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/student-profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterDialog(String filterType) async {
    if (filterType == 'Test Name') {
      await _ensureTestsLoaded();
      if (!mounted) return;
      final selected = await showDialog<TestModel>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Test'),
          children: _myTests
              .map(
                (t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, t),
                  child: Text(t.title),
                ),
              )
              .toList(),
        ),
      );
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
          if (list1.isNotEmpty) return list1;
          // Attempt 2: collection 'leaderboards_overall'
          final snap2 = await schoolRef
              .collection('leaderboards_overall')
              .orderBy('score', descending: true)
              .limit(100)
              .get();
          final list2 = _mapEntries(snap2.docs);
          if (list2.isNotEmpty) return list2;
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
    if (_schoolCode == null || _schoolCode!.isEmpty) {
      return const Stream.empty();
    }
    final schoolRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolCode);

    final path1Stream = schoolRef
        .collection('tests')
        .doc(testId)
        .collection('leaderboard')
        .orderBy('score', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snap) async {
          final list1 = _mapEntries(snap.docs);
          if (list1.isNotEmpty) return list1;
          return _leaderboardService.getPerTestLeaderboard(
            testId: testId,
            schoolCode: _schoolCode,
          );
        });
    return path1Stream;
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

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isFilled;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.isFilled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color iconColor = isSelected
        ? theme.colorScheme.secondary
        : theme.iconTheme.color?.withOpacity(0.7) ?? Colors.grey;
    final Color textColor = isSelected
        ? theme.colorScheme.secondary
        : theme.textTheme.bodyMedium?.color?.withOpacity(0.7) ?? Colors.grey;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 24, fill: isFilled ? 1.0 : 0.0),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
