import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/reward_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';

class StudentRewardsScreen extends StatefulWidget {
  const StudentRewardsScreen({super.key});

  @override
  State<StudentRewardsScreen> createState() => _StudentRewardsScreenState();
}

class _StudentRewardsScreenState extends State<StudentRewardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isMyRewards = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final studentId = authProvider.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFCFAF8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTabSelector(),
                      const SizedBox(height: 24),
                      _isMyRewards
                          ? _buildMyRewards(studentId)
                          : _buildRewardCatalog(),
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
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFFFCFAF8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_back, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Text(
            'Rewards',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              'My Rewards',
              _isMyRewards,
              () => setState(() => _isMyRewards = true),
            ),
          ),
          Expanded(
            child: _tabButton(
              'Reward Catalog',
              !_isMyRewards,
              () => setState(() => _isMyRewards = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF97316) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF97316).withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade500,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildMyRewards(String studentId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'My Rewards',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        StreamBuilder<List<RewardModel>>(
          stream: FirestoreService().getRewardsByStudent(studentId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                    color: Color(0xFFF27F0D),
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Error loading rewards',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              );
            }

            final rewards = snapshot.data ?? [];

            if (rewards.isEmpty) {
              return _buildEmptyState();
            }

            return Column(
              children: rewards.map((reward) => _buildRewardCard(reward)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No Rewards Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete tests and earn rewards!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardCard(RewardModel reward) {
    final isUsed = reward.status == RewardStatus.accepted;
    final isAvailable = reward.status == RewardStatus.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Opacity(
        opacity: isUsed ? 0.6 : 1.0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Reward Image
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: reward.imageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(reward.imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                  color: reward.imageUrl == null
                      ? const Color(0xFFF27F0D).withOpacity(0.1)
                      : null,
                ),
                child: reward.imageUrl == null
                    ? Icon(
                        _getRewardIcon(reward.type),
                        size: 32,
                        color: const Color(0xFFF27F0D),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              // Reward Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildStatusBadge(reward.status),
                    if (isUsed && reward.acceptedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Used on: ${DateFormat('dd MMM yyyy').format(reward.acceptedAt!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9C7349),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Action Button
              if (isAvailable)
                TextButton(
                  onPressed: () => _useReward(reward),
                  child: const Text(
                    'Use Now',
                    style: TextStyle(
                      color: Color(0xFFF27F0D),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (reward.status == RewardStatus.pending)
                TextButton(
                  onPressed: () => _viewRewardDetails(reward),
                  child: const Text(
                    'View Details',
                    style: TextStyle(
                      color: Color(0xFFF27F0D),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(RewardStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case RewardStatus.pending:
        bgColor = const Color(0xFFDCFCE7);
        textColor = const Color(0xFF16A34A);
        label = 'Available';
        break;
      case RewardStatus.accepted:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade600;
        label = 'Used';
        break;
      case RewardStatus.rejected:
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade600;
        label = 'Expired';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  IconData _getRewardIcon(RewardType type) {
    switch (type) {
      case RewardType.badge:
        return Icons.emoji_events;
      case RewardType.points:
        return Icons.stars;
      case RewardType.certificate:
        return Icons.card_membership;
      case RewardType.gift:
        return Icons.redeem;
      case RewardType.custom:
        return Icons.emoji_events;
    }
  }

  Widget _buildRewardCatalog() {
    // Sample catalog data - in production, this would come from Firestore
    final catalogItems = [
      {
        'title': 'Extra Game Time',
        'points': 50,
        'available': false, // Insufficient points
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuCpZ6VqS2F8oNFeCVBMtr7yFM7urS79MqW_AVAJpmRcVSOGYd_G2sxsZhne0z3c-MfzHsozKeqPxc9Bqw9bSDQbHtY5_hdpaqZvcSWbS2it3bSqaRV11McuxUXr7A_7V17GqjuW9zoWWY3FPgHqPkLHNigFsRb1UWPucdBEwWrn57vxzK_wQA-PjYyKF9WIrzm-X8_PjlKAwY1xQaDulTJQCPybJUXU7-FT6UxksiTq8w4tmBrXHOm5Oc1rGkaTfvuqeYJCyQ9sWcc',
      },
      {
        'title': 'Movie Night',
        'points': 100,
        'available': true,
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBCmvl09BL1tM-y_GafQbgSCTc-17ncIF_BKN2EMmxc0qLaYbQuyhTBIHJyTKhVWKEgfN2hBoHD5m0yR_vjeONIkwf7N1VY52TC1tz4EgZFWk6swfTAET3QOSQfw_tYDEpYCnhmRH-cRL8jb_8m8jBGhIgVUujf5gwVyqjVwFe_u-sa-iV-PTKewCukNiKbftxCF0MWah8_8ElQamdoIy2Ldrh2n0G02dH3czsVa3Q9P6J4gEjDiSjTMG6TsgMYi-3xJAA4DaUwfGc',
      },
      {
        'title': 'Ice Cream Treat',
        'points': 75,
        'available': true,
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBNb08VMnGnPYyrJX93WRRkoXoE8HhWB0oKSPUq5migxAHqkssENBTagiYRBdh1b0FSMUsrnFoCEd7NJComtOcStRedTbPNZiyZYtR19b4BLy6ltHNq84AW7_6qCRYIZ2bQje7pZbIcgx8QBKgO-uefAW2BLxKyIQyfwNTAbWHahMEcABX-D0zWytBEuMbicpHk3vH47ZIX7NV_-OjgoJlhUUKqOl0Lu0O3YBFYd1_kpooLRsW1SkVhmpnAzopumwBxW6NFaBAd_aU',
      },
      {
        'title': 'New Book',
        'points': 150,
        'available': true,
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBNb08VMnGnPYyrJX93WRRkoXoE8HhWB0oKSPUq5migxAHqkssENBTagiYRBdh1b0FSMUsrnFoCEd7NJComtOcStRedTbPNZiyZYtR19b4BLy6ltHNq84AW7_6qCRYIZ2bQje7pZbIcgx8QBKgO-uefAW2BLxKyIQyfwNTAbWHahMEcABX-D0zWytBEuMbicpHk3vH47ZIX7NV_-OjgoJlhUUKqOl0Lu0O3YBFYd1_kpooLRsW1SkVhmpnAzopumwBxW6NFaBAd_aU',
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: catalogItems.length,
      itemBuilder: (context, index) {
        return _buildCatalogCard(catalogItems[index]);
      },
    );
  }

  Widget _buildCatalogCard(Map<String, dynamic> item) {
    final bool isAvailable = item['available'] as bool;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Image
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: NetworkImage(item['image']),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Title
          Text(
            item['title'],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // Points
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.workspace_premium,
                size: 18,
                color: Color(0xFFFBBF24),
              ),
              const SizedBox(width: 4),
              Text(
                '${item['points']} pts',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF97316),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Redeem Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isAvailable ? () => _redeemReward(item) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFF97316).withOpacity(0.5),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Redeem Now',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: const Color(0xFFF4EDE7),
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
                icon: Icons.checklist,
                label: 'Tests',
                isSelected: false,
                onTap: () => Navigator.pushNamed(context, '/student-tests'),
              ),
              _NavItem(
                icon: Icons.emoji_events,
                label: 'Rewards',
                isSelected: true,
                onTap: () {},
              ),
              _NavItem(
                icon: Icons.leaderboard,
                label: 'Leaderboard',
                isSelected: false,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Leaderboard coming soon!')),
                  );
                },
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: 'Profile',
                isSelected: false,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile coming soon!')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _useReward(RewardModel reward) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Use ${reward.title}?'),
        content: Text(
          'Are you sure you want to use this reward now?\n\n${reward.description}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirestoreService().updateReward(
                  reward.id,
                  {
                    'status': RewardStatus.accepted.toString().split('.').last,
                    'acceptedAt': DateTime.now(),
                  },
                );
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${reward.title} has been used!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF27F0D),
            ),
            child: const Text('Use Now'),
          ),
        ],
      ),
    );
  }

  void _viewRewardDetails(RewardModel reward) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reward.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reward.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  reward.imageUrl!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              reward.description,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'From: ${reward.senderName} (${reward.senderRole})',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (reward.points != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF27F0D).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.stars,
                        size: 16,
                        color: Color(0xFFF27F0D),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${reward.points} Points',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF27F0D),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _redeemReward(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Redeem ${item['title']}?'),
        content: Text(
          'This will cost ${item['points']} points.\n\n${item['description']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reward redemption coming soon!'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF27F0D),
            ),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
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
              color: isSelected ? const Color(0xFFF27F0D) : const Color(0xFF9C7349),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? const Color(0xFFF27F0D) : const Color(0xFF9C7349),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
