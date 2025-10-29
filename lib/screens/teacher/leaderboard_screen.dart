import 'package:flutter/material.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _selectedStandard = 'all';
  String _selectedSection = 'all';
  int _selectedNavIndex = 3;

  final List<Map<String, dynamic>> _allStudents = [
    {
      'name': 'Ava Williams',
      'class': '10A',
      'standard': '10',
      'section': 'A',
      'points': 9410,
      'rank': 4,
      'imageUrl':
          'https://lh3.googleusercontent.com/aida-public/AB6AXuAjTYfVvLZoo3X2a5eEymwbd1ngX9tIz_lf0KGqqghj3giXJ4331bNdfvpcizq3Mwg6CDbYY2AMdTu_d0iOrJ29EmTewcQ6xz6P9s9YbZ4SvSOFkA8SSlZ2oS1k3fDJZHS33CZLcN7svaUuxQCHYcdwX9QJy2KREORbyYlAYkTO-gicuSvfeYgMAnbleQyPmYv6VgirPmiQbpFRNZwQHVdY07qutMwpkIAmPz4O_yxj9Qsr4CwM89m2UnYUGEPYrCOjiO6pZBitbpU',
    },
    {
      'name': 'Liam Johnson',
      'class': '11B',
      'standard': '11',
      'section': 'B',
      'points': 9320,
      'rank': 5,
      'imageUrl':
          'https://cdn.usegalileo.ai/stability/8c5c3e1f-7f45-4b2b-b8c9-4e1f7a3c9b2d.png',
    },
    {
      'name': 'Emma Davis',
      'class': '10A',
      'standard': '10',
      'section': 'A',
      'points': 9280,
      'rank': 6,
      'imageUrl':
          'https://cdn.usegalileo.ai/stability/1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d.png',
    },
    {
      'name': 'Noah Martinez',
      'class': '12C',
      'standard': '12',
      'section': 'C',
      'points': 9150,
      'rank': 7,
      'imageUrl':
          'https://cdn.usegalileo.ai/stability/9d8c7b6a-5e4f-3d2c-1b0a-9e8d7c6b5a4f.png',
    },
    {
      'name': 'Isabella Brown',
      'class': '11A',
      'standard': '11',
      'section': 'A',
      'points': 9080,
      'rank': 8,
      'imageUrl':
          'https://cdn.usegalileo.ai/stability/7f6e5d4c-3b2a-1f0e-9d8c-7b6a5f4e3d2c.png',
    },
  ];

  List<Map<String, dynamic>> get _filteredStudents {
    return _allStudents.where((student) {
      final matchesStandard =
          _selectedStandard == 'all' ||
          student['standard'] == _selectedStandard;
      final matchesSection =
          _selectedSection == 'all' || student['section'] == _selectedSection;
      return matchesStandard && matchesSection;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopPerformersSection(),
                  _buildFilters(),
                  _buildStudentRankings(),
                ],
              ),
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Leaderboard',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.ios_share),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share leaderboard')),
                  );
                },
                color: Theme.of(context).iconTheme.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopPerformersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Overall Top Performers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildTopPerformer(
                rank: 2,
                name: 'Benjamin C.',
                points: '9,750 pts',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuC7VrBk4py2Pa8Tva_PYg2dTtl5NhtAL6zP5M_wvOkH_MX1v0BjyIliNK3iiZ6nXyoxv3cXY0NLh9Jn-GDVdxD9gcn0VoiEyTybu3qa2TQUPrr-G2Cq9Gy3ym5LuJIn-cnPlj3Kmg-D-0_ICHmfm6GGOwWkH2mNS0hq2ToZGdB7_v7ZKNFHeogDQ8WomcswDJ2MfTRLPo09_YLdy8_bjqOJHF-K7TcUoZHOWkDBWiEU_Cml_xWRXZO0uQrdV6Q8dLFsZacF9sBrLR0',
                borderColor: const Color(0xFFC0C0C0), // Silver
                badgeColor: const Color(0xFFC0C0C0),
                size: 80,
                marginTop: 16,
              ),
              _buildTopPerformer(
                rank: 1,
                name: 'Olivia Chen',
                points: '9,980 pts',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuDp7J7VZr4TSqVWQZF56-dR1ee2Zc75CnuSGw2L0xAGgTIF9zBAy503NQ3ZMWVbXvSUERLmRBnqOS4RWfQStI1i91G-JiYF95XVUGSp4JCUrr6lP0lD2I6q_FqwEjSwIGO3nprCfKUHraH_aUVJ2MO4Vj_lADwscOevuRw8tfvZ2_9Hh1W2QGoVzFBwLYW-OqVaP1g8SeDEYUJl2qJ4ZQ6pr4ZpE1ExOlJaProRBqU8efyha7p30aOHsG7q3nIjDrNTIJbT-3VJgio',
                borderColor: const Color(0xFFFFD700), // Gold
                badgeColor: const Color(0xFFFFD700),
                size: 96,
                marginTop: 0,
              ),
              _buildTopPerformer(
                rank: 3,
                name: 'Sophia R.',
                points: '9,540 pts',
                imageUrl:
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuAhfbXtIdj2F6GnDrpBGuvLlf8bGVgaiW2Jbs4Q8fsCgAoBVkaHHfdPp1VrkBLGmPPk0YlSr1ETmZFLw6NEqWcm9dMTnxRDg4GupixNU1z39aKPz435OU-R-Hd6kfviED36R6cL0pC5CE4eSRArCUbYeiq6Pt_MgEpGh3dFxVYlRBm_BXolNw-3m085kYFhDQdHD12L-z8DlTarPFfTjh5NNJCLXXFhCm9Q0QoMrNNX_Tz1aPxxMIGioyZTCin9_cDXjRT5Hzo90mU',
                borderColor: const Color(0xFFCD7F32), // Bronze
                badgeColor: const Color(0xFFCD7F32),
                size: 80,
                marginTop: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopPerformer({
    required int rank,
    required String name,
    required String points,
    required String imageUrl,
    required Color borderColor,
    required Color badgeColor,
    required double size,
    required double marginTop,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(top: marginTop),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 4),
                ),
                child: ClipOval(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[300],
                        child: Icon(
                          Icons.person,
                          size: size * 0.5,
                          color: Theme.of(
                            context,
                          ).iconTheme.color?.withOpacity(0.7),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                bottom: -8,
                left: size / 2 - 16,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            points,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Standard',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStandard,
                      isExpanded: true,
                      icon: Icon(
                        Icons.expand_more,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.6),
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Standards'),
                        ),
                        DropdownMenuItem(value: '10', child: Text('10')),
                        DropdownMenuItem(value: '11', child: Text('11')),
                        DropdownMenuItem(value: '12', child: Text('12')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedStandard = value!;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Section',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedSection,
                      isExpanded: true,
                      icon: Icon(
                        Icons.expand_more,
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withOpacity(0.6),
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All Sections'),
                        ),
                        DropdownMenuItem(value: 'A', child: Text('A')),
                        DropdownMenuItem(value: 'B', child: Text('B')),
                        DropdownMenuItem(value: 'C', child: Text('C')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedSection = value!;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentRankings() {
    final filteredStudents = _filteredStudents;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: filteredStudents.map((student) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
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
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${student['rank']}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(
                      student['imageUrl'],
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        final isDark =
                            Theme.of(context).brightness == Brightness.dark;
                        return Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[300],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person,
                            size: 24,
                            color: Theme.of(
                              context,
                            ).iconTheme.color?.withOpacity(0.7),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['name'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Class ${student['class']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${student['points']}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.space_dashboard_outlined, 'Dashboard', 0, () {
              Navigator.pushReplacementNamed(context, '/teacher-dashboard');
            }),
            _buildNavItem(Icons.school_outlined, 'Classes', 1, () {
              Navigator.pushReplacementNamed(context, '/classes');
            }),
            _buildNavItem(Icons.assignment_outlined, 'Tests', 2, () {
              Navigator.pushReplacementNamed(context, '/tests');
            }),
            _buildNavItem(Icons.leaderboard, 'Leaderboard', 3, () {}),
            _buildNavItem(Icons.person_outline, 'Profile', 4, () {
              Navigator.pushReplacementNamed(context, '/profile');
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    int index,
    VoidCallback onTap,
  ) {
    final isSelected = _selectedNavIndex == index;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : Theme.of(context).iconTheme.color?.withOpacity(0.6),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
