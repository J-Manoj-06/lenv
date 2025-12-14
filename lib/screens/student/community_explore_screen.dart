import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/community_model.dart';
import '../../providers/student_provider.dart';
import '../../services/community_service.dart';

class CommunityExploreScreen extends StatefulWidget {
  const CommunityExploreScreen({super.key});

  @override
  State<CommunityExploreScreen> createState() => _CommunityExploreScreenState();
}

class _CommunityExploreScreenState extends State<CommunityExploreScreen> {
  final CommunityService _communityService = CommunityService();
  final TextEditingController _searchController = TextEditingController();

  List<CommunityModel> _allCommunities = [];
  List<CommunityModel> _filteredCommunities = [];
  String _selectedCategory = 'All';
  bool _isLoading = true;
  Set<String> _joiningCommunities = {};
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
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    final student = studentProvider.currentStudent;

    if (student == null) return;

    setState(() => _isLoading = true);

    final communities = await _communityService.getExploreCommunities(student);

    // Get joined community IDs
    final joinedIds = <String>{};
    for (final community in communities) {
      final isMember = await _communityService.isMember(
        community.id,
        student.uid,
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
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    final student = studentProvider.currentStudent;

    if (student == null) return;

    setState(() => _joiningCommunities.add(community.id));

    final success = await _communityService.joinCommunity(
      community.id,
      student,
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
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
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
                    : theme.colorScheme.surfaceVariant.withOpacity(0.6),
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

          // Category Filters
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = category == _selectedCategory;

                return GestureDetector(
                  onTap: () => _onCategorySelected(category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF7A5CFF)
                          : (isDark
                                ? theme.colorScheme.surface
                                : theme.colorScheme.surfaceVariant.withOpacity(
                                    0.4,
                                  )),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : theme.textTheme.bodySmall?.color,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
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
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isNotEmpty
                              ? 'No communities found'
                              : 'No communities available',
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredCommunities.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final community = _filteredCommunities[index];
                      final isJoining = _joiningCommunities.contains(
                        community.id,
                      );
                      final isJoined = _joinedCommunities.contains(
                        community.id,
                      );

                      return _buildCommunityCard(
                        community,
                        isJoining,
                        isJoined,
                        theme,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(
    CommunityModel community,
    bool isJoining,
    bool isJoined,
    ThemeData theme,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFA929).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                community.getCategoryIcon(),
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  community.name,
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  community.description,
                  style: TextStyle(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA929).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        community.category,
                        style: const TextStyle(
                          color: Color(0xFFFFA929),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Join/Joined Button
          isJoined
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
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
                      SizedBox(width: 4),
                      Text(
                        'Joined',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                    ],
                  ),
                )
              : ElevatedButton(
                  onPressed: isJoining ? null : () => _joinCommunity(community),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFA929),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFFFFA929,
                    ).withValues(alpha: 0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: isJoining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
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
    );
  }
}
