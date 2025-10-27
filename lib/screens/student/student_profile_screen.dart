import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7ED),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildProfileHeader(user),
                    _buildStatsCards(),
                    _buildPersonalInfoSection(user),
                    const SizedBox(height: 80), // Bottom nav spacing
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
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF97316),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Icon(
                Icons.school,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          // Title
          const Expanded(
            child: Text(
              'My Profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF292524),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(dynamic user) {
    final String name = user?.name ?? 'Alex Johnson';
    final String? imageUrl = user?.profileImage;

    // Sample data for demo - these fields would come from StudentModel in a real app
    const String className = 'Class 10-B';
    const String rollNo = '24';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile image with camera button
          Stack(
            children: [
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(64),
                  image: imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: imageUrl == null ? const Color(0xFFE7E5E4) : null,
                ),
                child: imageUrl == null
                    ? const Icon(
                        Icons.person,
                        size: 64,
                        color: Color(0xFF78716C),
                      )
                    : null,
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _onChangePhoto,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF97316),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.photo_camera,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Name and class info
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF292524),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$className | Roll No. $rollNo',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF78716C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    // Sample data - replace with actual data from Firestore
    final stats = [
      {'label': 'Tests Taken', 'value': '12'},
      {'label': 'Average Score', 'value': '88%'},
      {'label': 'Class Rank', 'value': '3'},
      {'label': 'Attendance', 'value': '95%'},
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: stats.map((stat) => _buildStatCard(stat)).toList(),
      ),
    );
  }

  Widget _buildStatCard(Map<String, String> stat) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Two cards per row with spacing
    final cardWidth = (screenWidth - 48) / 2;

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFED7AA),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat['label']!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF78716C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            stat['value']!,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF292524),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection(dynamic user) {
    // Sample data for demo - these fields would come from StudentModel in a real app
    final String email = user?.email ?? 'alex.j@email.com';
    const String phone = '+1 234 567 890';
    const String schoolName = 'Springfield High';
    const String dateOfBirth = '15 Aug 2008';
    const String guardianPhone = '+1 098 765 432';
    return Column(
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Personal Information',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF292524),
                ),
              ),
              GestureDetector(
                onTap: _onEditProfile,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.edit,
                        size: 18,
                        color: Color(0xFFF97316),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF97316),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Info table
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFED7AA),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  'Email',
                  email,
                  isFirst: true,
                ),
                _buildInfoRow(
                  'Phone',
                  phone,
                ),
                _buildInfoRow(
                  'School Name',
                  schoolName,
                ),
                _buildInfoRow(
                  'Date of Birth',
                  dateOfBirth,
                ),
                _buildInfoRow(
                  'Guardian',
                  guardianPhone,
                  isLast: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value,
      {bool isFirst = false, bool isLast = false}) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(
                  color: Color(0xFFFED7AA),
                  width: 1,
                ),
              ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF78716C),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF292524),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED).withOpacity(0.9),
        border: const Border(
          top: BorderSide(
            color: Color(0xFFFED7AA),
            width: 1,
          ),
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
                icon: Icons.quiz_outlined,
                label: 'Tests',
                isSelected: false,
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student-tests',
                ),
              ),
              _NavItem(
                icon: Icons.redeem_outlined,
                label: 'Rewards',
                isSelected: false,
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student-rewards',
                ),
              ),
              _NavItem(
                icon: Icons.leaderboard_outlined,
                label: 'Leaderboard',
                isSelected: false,
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student-leaderboard',
                ),
              ),
              _NavItem(
                icon: Icons.person,
                label: 'Profile',
                isSelected: true,
                isFilled: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onChangePhoto() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Change photo coming soon!')),
    );
  }

  void _onEditProfile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit profile coming soon!')),
    );
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
              color:
                  isSelected ? const Color(0xFFF97316) : const Color(0xFF78716C),
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
                    ? const Color(0xFFF97316)
                    : const Color(0xFF78716C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
