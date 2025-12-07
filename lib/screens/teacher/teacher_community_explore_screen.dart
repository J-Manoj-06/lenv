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
  Set<String> _joiningCommunities = {};
  Set<String> _joinedCommunities = {};
  String? _teacherSchoolCode;

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
      _teacherSchoolCode = schoolCode;
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
      teacherEmail: currentUser.email ?? '',
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
    return Scaffold(
      backgroundColor: const Color(0xFF16171A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16171A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Explore Communities',
          style: TextStyle(
            color: Colors.white,
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
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search communities',
                  hintStyle: TextStyle(color: Colors.white54),
                  prefixIcon: Icon(Icons.search, color: Colors.white54),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
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
                          ? const Color(0xFF6A4FF7)
                          : const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6A4FF7)
                            : Colors.white.withValues(alpha: 0.1),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        category,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
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
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6A4FF7)),
                  )
                : _filteredCommunities.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadCommunities,
                    color: const Color(0xFF6A4FF7),
                    backgroundColor: const Color(0xFF1C1C1E),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredCommunities.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final community = _filteredCommunities[index];
                        return _buildCommunityCard(community);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Icon(
              Icons.search_off,
              size: 50,
              color: Color(0xFF6A4FF7),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Communities Found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your search or filters',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(CommunityModel community) {
    final isJoined = _joinedCommunities.contains(community.id);
    final isJoining = _joiningCommunities.contains(community.id);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
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
                  color: const Color(0xFF6A4FF7).withValues(alpha: 0.2),
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
                      style: const TextStyle(
                        color: Colors.white,
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
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          community.scope == 'global' ? 'Global' : 'School',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.people,
                          size: 14,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${community.memberCount} members',
                          style: const TextStyle(
                            color: Colors.white38,
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
            style: const TextStyle(
              color: Colors.white70,
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
                  color: const Color(0xFF6A4FF7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  community.category.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF6A4FF7),
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
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
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
                    backgroundColor: const Color(0xFF6A4FF7),
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
