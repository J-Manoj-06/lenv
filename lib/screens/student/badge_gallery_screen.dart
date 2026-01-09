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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: isDark ? Colors.white : const Color(0xFF1A1D21),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Badge Collection',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1A1D21),
            fontWeight: FontWeight.bold,
          ),
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
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
                            color: isSelected
                                ? Colors.black
                                : (isDark ? Colors.white70 : Colors.black54),
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
                        backgroundColor: isDark
                            ? const Color(0xFF1C1C1E)
                            : Colors.white,
                        selectedColor: const Color(0xFFFF8800),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFFFF8800)
                                : (isDark ? Colors.white24 : Colors.black12),
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
                    childAspectRatio: 0.9,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeCard(Badge badge, bool isEarned) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showBadgeDetail(badge, isEarned),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEarned
                ? const Color(0xFFFF8800)
                : (isDark ? Colors.white12 : Colors.black12),
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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                badge.emoji,
                style: TextStyle(
                  fontSize: 32,
                  color: isEarned
                      ? null
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.2)),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    badge.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: isEarned
                          ? (isDark ? Colors.white : const Color(0xFF1A1D21))
                          : (isDark ? Colors.white38 : Colors.black38),
                      fontWeight: isEarned
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (isEarned)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
      ),
    );
  }

  void _showBadgeDetail(Badge badge, bool isEarned) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
                color: isEarned
                    ? null
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.3)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isEarned
                    ? (isDark ? Colors.white : const Color(0xFF1A1D21))
                    : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black87,
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
