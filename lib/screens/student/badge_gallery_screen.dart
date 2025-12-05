import 'package:flutter/material.dart' hide Badge;
import '../../badges/badge_model.dart';
import '../../badges/badge_master.dart';
import '../../services/badge_service.dart';

class BadgeGalleryScreen extends StatefulWidget {
  final String studentId;

  const BadgeGalleryScreen({super.key, required this.studentId});

  @override
  State<BadgeGalleryScreen> createState() => _BadgeGalleryScreenState();
}

class _BadgeGalleryScreenState extends State<BadgeGalleryScreen> {
  final BadgeService _badgeService = BadgeService();
  String _selectedCategory = 'all';

  final Map<String, String> _categoryLabels = {
    'all': 'All Badges',
    'test': 'Test Performance',
    'challenge': 'Daily Challenges',
    'milestone': 'Milestones',
    'streak': 'Streaks',
    'community': 'Community',
    'competition': 'Competition',
    'productivity': 'Productivity',
    'attendance': 'Attendance',
    'rewards': 'Rewards',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16171A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Badge Collection',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<List<Badge>>(
        future: _badgeService.fetchEarnedBadges(widget.studentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8800)),
            );
          }

          final earnedBadges = snapshot.data ?? [];
          final earnedIds = earnedBadges.map((b) => b.id).toSet();

          // Filter badges by category
          final filteredBadges = _selectedCategory == 'all'
              ? badgeMasterList
              : badgeMasterList
                    .where((b) => b.category == _selectedCategory)
                    .toList();

          final totalBadges = badgeMasterList.length;
          final earnedCount = earnedBadges.length;

          return Column(
            children: [
              // Stats Header
              Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF8800), width: 2),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      'Earned',
                      '$earnedCount',
                      const Color(0xFFFF8800),
                    ),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _buildStatItem('Total', '$totalBadges', Colors.white70),
                    Container(width: 1, height: 40, color: Colors.white24),
                    _buildStatItem(
                      'Progress',
                      '${((earnedCount / totalBadges) * 100).toInt()}%',
                      const Color(0xFF4CAF50),
                    ),
                  ],
                ),
              ),

              // Category Filter
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: _categoryLabels.entries.map((entry) {
                    final isSelected = _selectedCategory == entry.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(
                          entry.value,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = entry.key;
                          });
                        },
                        backgroundColor: const Color(0xFF1C1C1E),
                        selectedColor: const Color(0xFFFF8800),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFFFF8800)
                                : Colors.white24,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 10),

              // Badges Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filteredBadges.length,
                  itemBuilder: (context, index) {
                    final badge = filteredBadges[index];
                    final isEarned = earnedIds.contains(badge.id);
                    return _buildBadgeCard(badge, isEarned);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildBadgeCard(Badge badge, bool isEarned) {
    return GestureDetector(
      onTap: () => _showBadgeDetail(badge, isEarned),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEarned ? const Color(0xFFFF8800) : Colors.white12,
            width: isEarned ? 2 : 1,
          ),
          boxShadow: isEarned
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF8800).withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              badge.emoji,
              style: TextStyle(
                fontSize: 36,
                color: isEarned ? null : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                badge.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isEarned ? Colors.white : Colors.white38,
                  fontWeight: isEarned ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (isEarned)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '✓',
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showBadgeDetail(Badge badge, bool isEarned) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              badge.emoji,
              style: TextStyle(
                fontSize: 64,
                color: isEarned ? null : Colors.white.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isEarned ? Colors.white : Colors.white54,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isEarned
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                    : Colors.white12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isEarned ? Icons.check_circle : Icons.lock,
                    color: isEarned ? const Color(0xFF4CAF50) : Colors.white38,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEarned ? 'Earned' : 'Locked',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isEarned
                          ? const Color(0xFF4CAF50)
                          : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
