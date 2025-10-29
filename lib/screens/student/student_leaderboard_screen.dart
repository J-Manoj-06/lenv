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
  // Default to Overall tab selected to match the provided Overall leaderboard design
  bool _isPerTest = false;
  String _selectedSubject = 'Subject';
  String? _selectedTestId;
  String _selectedTestLabel = 'Test Name';

  final _leaderboardService = LeaderboardService();

  Future<List<LeaderboardEntry>>? _overallFuture;
  Future<List<LeaderboardEntry>>? _perTestFuture;
  List<TestModel> _myTests = const [];
  String? _schoolCode;
  String? _className;
  String? _section;
  String? _currentUid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCFBF8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Filters are only relevant for Per-Test view
                    if (_isPerTest) _buildFilters(),
                    _buildLeaderboardList(),
                  ],
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
                      'Per-Test',
                      _isPerTest,
                      () => setState(() => _isPerTest = true),
                    ),
                  ),
                  Expanded(
                    child: _buildTabButton(
                      'Overall',
                      !_isPerTest,
                      () => setState(() => _isPerTest = false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
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
                  colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEA580C).withOpacity(0.1)
              : const Color(0xFFE7E5E4).withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFFC2410C)
                    : const Color(0xFF292524),
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    _currentUid ??= auth.currentUser?.uid;

    // Lazy init: load class context and overall leaderboard once
    if (_overallFuture == null && !_isPerTest) {
      _initContextAndOverall();
    }

    if (_isPerTest) {
      if (_perTestFuture == null && _selectedTestId != null) {
        _perTestFuture = _leaderboardService.getPerTestLeaderboard(
          testId: _selectedTestId!,
          schoolCode: _schoolCode,
        );
      }
      return FutureBuilder<List<LeaderboardEntry>>(
        future: _perTestFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final items = snap.data ?? [];
          if (_selectedTestId == null) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Select a test to view the leaderboard.'),
            );
          }
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No results for this test yet.'),
            );
          }
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
                      'imageUrl': null,
                    }),
                  )
                  .toList(),
            ),
          );
        },
      );
    }

    // Overall
    return FutureBuilder<List<LeaderboardEntry>>(
      future: _overallFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No leaderboard data yet.'),
          );
        }
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
      },
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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: isTopThree
                  ? const LinearGradient(
                      colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
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
                  color: isTopThree ? Colors.white : const Color(0xFF57534E),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
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
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFBF8).withOpacity(0.8),
        border: const Border(
          top: BorderSide(color: Color(0xFFE7E5E4), width: 1),
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
          _perTestFuture = _leaderboardService.getPerTestLeaderboard(
            testId: selected.id,
            schoolCode: _schoolCode,
          );
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
        _overallFuture = _leaderboardService.getOverallLeaderboardForClass(
          schoolCode: _schoolCode!,
          className: _className!,
          section: _section,
          limit: 100,
        );
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFFEA580C)
                  : const Color(0xFF78716C),
              size: 24,
              fill: isFilled ? 1.0 : 0.0,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? const Color(0xFFEA580C)
                    : const Color(0xFF78716C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
