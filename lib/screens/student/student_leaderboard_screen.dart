import 'package:flutter/material.dart';

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
  String _selectedTest = 'Test Name';

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
            _selectedTest,
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
    // Sample leaderboard data
    final leaderboardItems = [
      {
        'rank': 1,
        'name': 'Amelia',
        'score': 98,
        'hasVerified': true,
        'isCurrentUser': false,
        'imageUrl': null,
      },
      {
        'rank': 2,
        'name': 'You',
        'score': 95,
        'hasVerified': false,
        'isCurrentUser': true,
        'imageUrl':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuAgOeDqb10QybQCjfb8Z2JK-NrsB49M9PfVCpfGrbJaPOC4gsilGd2fmuuCNkoOkrQ1adku_bj8dqoawtN7rhA1GSB7ZMd9KmkCjUnsGqoiL9nJjOzhHSNDHMM1wFTlan_41jbAXxU3vysoeEznnF9741IWAxpUDgohEr-HHYcUaRQAj1tUAGB3GLe43hFmbfD6uGtNZTPEEl6Fu51QFOJBwzDNBzWqEQOKAGVcbY5COYbUvgpsk9JZW1TsjHvmynvhgoqEVuulT54',
      },
      {
        'rank': 3,
        'name': 'Olivia',
        'score': 92,
        'hasVerified': false,
        'isCurrentUser': false,
        'imageUrl':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuC31iICWqlv7iufcGqYLUe5lyAorM4z4DhoqAwFBZQNnC9L1yNU-m0w6RSNVdxOyNffej5eYC5-0xSYD2OXepCKu1XgetRxyt79mSRHAjrwI1li_BbhAGgY9l10v3NGiWWFYiwHQ6XhcpBdvxRezFWct96AvbW_I7vWvt1m13c39EPfY-1IHthmMnH9GLNOkxFSTESccNEPFCPzRfgPEETGVvMIbUlyRe4SquUvROozu42VynOg9wGAl86BCxaCEl9eyP2HVV0zyrE',
      },
      {
        'rank': 4,
        'name': 'Noah',
        'score': 90,
        'hasVerified': false,
        'isCurrentUser': false,
        'imageUrl':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBMNcghC6-AWNsBY76q9d9ifPePS71oyBrqeabDDCNAo9MSUd_XYgstphgReb7-_GDvj1Ppb72qYWO6wN1nudA6bhfe3VnYjwVd5GSJfd1UY2GcyZbKO9ib2be899hHXjRWnnghVFUR9W4fv4Y5K37qO2YGa76XeKlXwgDB5yvjmnB7M5A2GenrXfzZthAw1FkvIrl12rw7l51E_0BK9e6mIeCXm1JlPMwNn_BEHRx74wPdO_RFODE99qFn9y-pnxbfotFGwAxKqY',
      },
      {
        'rank': 5,
        'name': 'Ava',
        'score': 88,
        'hasFire': true,
        'isCurrentUser': false,
        'imageUrl':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuDVVfVAw2g3b75RaYj-OXrOkKMzdX2MHsWDyaxFNYusUdeFdLn76R6Qhj7YMojcBr2HpR_2E910B-WXMqDJkfSEXFc1nM_l63ITmvbb3WKy4qycp3SqKV7SmhrxLtKvOWjBYtq-XEnelU_CzZu3WN6Vam3AG7kvw3A699qL-mFH3K31vvb8XhFaIVy4x59g3IsvXPBy8k334f7BKsYIzLs359yTgEySB3kmfTyJlKUPV59zf1igqfuQQbUMqlojfW4D2CZJmK_8sCQ',
      },
      {
        'rank': 6,
        'name': 'Liam',
        'score': 85,
        'hasVerified': false,
        'isCurrentUser': false,
        'imageUrl':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuCu1GaIAeQ53IfZRtF2_PWBl1NHiCPcYyYdTXO-e-SYB0GtbUDdZlX7ceDFDblxkwhUGMPUMo4BZwYBlqTNKSYZVdk1ZYQmafXQbl9VECzTQMqEz3iGk2wIpcFIZNv86CB6j6MoU-lVddO9sLQQLTazIHqyxIVdAGLR69WdjG98XSm6-atXKBt_--ywKgS72Y2jfrb17qF22er1RD_l1McN42h08tiqzODWz_fNzJoarNT94WvbxME-HNVa3b--EyZHpZLcvPz4bP4',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: leaderboardItems
            .map((item) => _buildLeaderboardCard(item))
            .toList(),
      ),
    );
  }

  Widget _buildLeaderboardCard(Map<String, dynamic> item) {
    final int rank = item['rank'];
    final String name = item['name'];
    final int score = item['score'];
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
            '$score',
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
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student-tests',
                ),
              ),
              _NavItem(
                icon: Icons.workspace_premium_outlined,
                label: 'Rewards',
                isSelected: false,
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student-rewards',
                ),
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
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student-profile',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterDialog(String filterType) {
    // Placeholder for filter dialog
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$filterType filter coming soon!')));
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
