import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _isMyRewards = false; // default to Catalogue
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Badges',
    'Points',
    'Certificates',
    'Gifts',
    'Custom',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final studentId = authProvider.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                      const SizedBox(height: 16),
                      _buildSearchBar(),
                      const SizedBox(height: 12),
                      _buildCategoryChips(),
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
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
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
          Text(
            'Rewards',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
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
              'Catalogue',
              !_isMyRewards,
              () => setState(() => _isMyRewards = false),
            ),
          ),
          Expanded(
            child: _tabButton(
              'My Rewards',
              _isMyRewards,
              () => setState(() => _isMyRewards = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool isSelected, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey.shade300 : Colors.grey.shade500),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() {}),
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search rewards...',
          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = category;
                });
              },
              backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              selectedColor: const Color(0xFFF97316),
              labelStyle: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          );
        },
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        StreamBuilder<List<RewardModel>>(
          stream: FirestoreService().getRewardsByStudent(studentId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFFF27F0D)),
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
              children: rewards
                  .map((reward) => _buildRewardCard(reward))
                  .toList(),
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
              color: Theme.of(context).iconTheme.color?.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No Rewards Yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete tests and earn rewards!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                          style: Theme.of(context).textTheme.bodySmall,
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final studentId = authProvider.currentUser?.uid ?? '';

    return StreamBuilder<List<RewardModel>>(
      stream: FirestoreService().getRewardCatalogForStudent(studentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFFF27F0D)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading catalog',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        }

        final catalogRewards = snapshot.data ?? [];

        if (catalogRewards.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  Icon(
                    Icons.card_giftcard_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Rewards Available',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ask your parents to create rewards for you!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: catalogRewards.length,
          itemBuilder: (context, index) {
            return _buildCatalogCard(catalogRewards[index]);
          },
        );
      },
    );
  }

  Widget _buildCatalogCard(RewardModel reward) {
    return Container(
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
              color: const Color(0xFFFCFAF8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: reward.imageUrl != null && reward.imageUrl!.isNotEmpty
                  ? Image.network(
                      reward.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.card_giftcard,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                    )
                  : Icon(
                      Icons.card_giftcard,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          // Title
          Text(
            reward.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
                '${reward.points ?? 0} pts',
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
              onPressed: () => _redeemReward(reward),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Redeem Now',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
        color: Theme.of(context).cardColor.withOpacity(0.7),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.8),
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
                onTap: () =>
                    Navigator.pushReplacementNamed(context, '/student-tests'),
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
                onTap: () => Navigator.pushReplacementNamed(
                  context,
                  '/student-leaderboard',
                ),
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
                await FirestoreService().updateReward(reward.id, {
                  'status': RewardStatus.accepted.toString().split('.').last,
                  'acceptedAt': DateTime.now(),
                });
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
            Text(reward.description, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Text(
              'From: ${reward.senderName} (${reward.senderRole})',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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

  void _redeemReward(RewardModel reward) async {
    // Check if reward status is pending (available for redemption)
    if (reward.status != RewardStatus.pending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This reward is ${reward.status.toString().split('.').last}',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Redeem ${reward.title}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will cost ${reward.points ?? 0} points.'),
            if (reward.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(reward.description),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF27F0D),
            ),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Update reward status to accepted
    try {
      await FirestoreService().updateReward(reward.id, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${reward.title} redeemed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to redeem reward: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isSelected
        ? const Color(0xFFF59E0B)
        : (isDark
            ? Theme.of(context).iconTheme.color?.withOpacity(0.6)
            : const Color(0xFF9C7349));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
