import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/community_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/community_service.dart';

class TeacherCommunityExploreScreen extends StatefulWidget {
  const TeacherCommunityExploreScreen({super.key});

  @override
  State<TeacherCommunityExploreScreen> createState() =>
      _TeacherCommunityExploreScreenState();
}

class _TeacherCommunityExploreScreenState
    extends State<TeacherCommunityExploreScreen> {
  final CommunityService _communityService = CommunityService();
  final TextEditingController _searchController = TextEditingController();

  List<CommunityModel> _allCommunities = [];
  List<CommunityModel> _filteredCommunities = [];
  String _selectedCategory = 'All';
  bool _isLoading = true;
  final Set<String> _joiningCommunities = {};
  Set<String> _joinedCommunities = {};

  final List<String> _categories = [
    'All',
    'Academic',
    'Sports',
    'Arts',
    'Technology',
    'General',
  ];

  @override
  void initState() {
    super.initState();
    _loadCommunities();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCommunities() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    setState(() => _isLoading = true);

    // Get teacher's school code
    final teacherDoc = await FirebaseFirestore.instance
        .collection('teachers')
        .where('email', isEqualTo: currentUser.email)
        .limit(1)
        .get();

    String schoolCode = '';
    if (teacherDoc.docs.isNotEmpty) {
      schoolCode = teacherDoc.docs.first.data()['schoolCode'] ?? '';
    }

    final communities = await _communityService.getExploreCommunitiesForTeacher(
      schoolCode: schoolCode,
    );

    // Get joined community IDs
    final joinedIds = <String>{};
    for (final community in communities) {
      final isMember = await _communityService.isMember(
        community.id,
        currentUser.uid,
      );
      if (isMember) {
        joinedIds.add(community.id);
      }
    }

    setState(() {
      _allCommunities = communities;
      _filteredCommunities = communities;
      _joinedCommunities = joinedIds;
      _isLoading = false;
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCommunities = _selectedCategory == 'All'
            ? _allCommunities
            : _allCommunities
                  .where(
                    (c) =>
                        c.category.toLowerCase() ==
                        _selectedCategory.toLowerCase(),
                  )
                  .toList();
      } else {
        _filteredCommunities = _allCommunities
            .where(
              (c) =>
                  c.name.toLowerCase().contains(query) ||
                  c.description.toLowerCase().contains(query),
            )
            .where(
              (c) =>
                  _selectedCategory == 'All' ||
                  c.category.toLowerCase() == _selectedCategory.toLowerCase(),
            )
            .toList();
      }
    });
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
      _onSearchChanged();
    });
  }

  Future<void> _joinCommunity(CommunityModel community) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    setState(() => _joiningCommunities.add(community.id));

    // Get teacher data
    final teacherDoc = await FirebaseFirestore.instance
        .collection('teachers')
        .where('email', isEqualTo: currentUser.email)
        .limit(1)
        .get();

    if (teacherDoc.docs.isEmpty) {
      setState(() => _joiningCommunities.remove(community.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Teacher data not found'),
            backgroundColor: Color(0xFFEF5350),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final teacherData = teacherDoc.docs.first.data();
    final success = await _communityService.joinCommunityAsTeacher(
      communityId: community.id,
      teacherId: currentUser.uid,
      teacherName: teacherData['name'] ?? '',
      teacherEmail: currentUser.email,
      schoolCode: teacherData['schoolCode'] ?? '',
    );

    setState(() => _joiningCommunities.remove(community.id));

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Joined ${community.name}!'),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Mark as joined
      setState(() {
        _joinedCommunities.add(community.id);
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to join community'),
          backgroundColor: Color(0xFFEF5350),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: theme.textTheme.bodyLarge?.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Explore Communities',
          style: TextStyle(
            color: theme.textTheme.bodyLarge?.color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surface
                    : theme.colorScheme.surfaceContainerHighest.withOpacity(
                        0.6,
                      ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search communities',
                  hintStyle: TextStyle(color: theme.textTheme.bodySmall?.color),
                  prefixIcon: Icon(
                    Icons.search,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),

          // Category Filter
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;

                return GestureDetector(
                  onTap: () => _onCategorySelected(category),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF7A5CFF)
                          : (isDark
                                ? theme.colorScheme.surface
                                : theme.colorScheme.surfaceContainerHighest
                                      .withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF7A5CFF)
                            : theme.dividerColor.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : theme.textTheme.bodySmall?.color,
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Communities List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: theme.primaryColor),
                  )
                : _filteredCommunities.isEmpty
                ? _buildEmptyState(theme)
                : RefreshIndicator(
                    onRefresh: _loadCommunities,
                    color: theme.primaryColor,
                    backgroundColor: theme.cardColor,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredCommunities.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final community = _filteredCommunities[index];
                        return _buildCommunityCard(community, theme);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Icon(Icons.search_off, size: 50, color: theme.primaryColor),
          ),
          const SizedBox(height: 24),
          Text(
            'No Communities Found',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(
              color: theme.textTheme.bodySmall?.color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(CommunityModel community, ThemeData theme) {
    final isJoined = _joinedCommunities.contains(community.id);
    final isJoining = _joiningCommunities.contains(community.id);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF7A5CFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    community.getCategoryIcon(),
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          community.scope == 'global'
                              ? Icons.public
                              : Icons.school,
                          size: 14,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          community.scope == 'global' ? 'Global' : 'School',
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.people,
                          size: 14,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${community.memberCount} members',
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color
                                ?.withOpacity(0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            community.description,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              fontSize: 14,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF7A5CFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  community.category.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF7A5CFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Join Button
              if (isJoined)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF4CAF50),
                      width: 1.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Color(0xFF4CAF50),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Joined',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton(
                  onPressed: isJoining ? null : () => _joinCommunity(community),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7A5CFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child: isJoining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Join',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
