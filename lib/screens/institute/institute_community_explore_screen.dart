import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/community_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/community_service.dart';
import '../../services/network_service.dart';
import '../../repositories/principal_dashboard_repository.dart';

class InstituteCommunityExploreScreen extends StatefulWidget {
  const InstituteCommunityExploreScreen({super.key});

  @override
  State<InstituteCommunityExploreScreen> createState() =>
      _InstituteCommunityExploreScreenState();
}

class _InstituteCommunityExploreScreenState
    extends State<InstituteCommunityExploreScreen>
    with WidgetsBindingObserver {
  final CommunityService _communityService = CommunityService();
  final PrincipalDashboardRepository _dashboardRepo =
      PrincipalDashboardRepository();
  final NetworkService _networkService = NetworkService();
  final TextEditingController _searchController = TextEditingController();

  List<CommunityModel> _allCommunities = [];
  List<CommunityModel> _filteredCommunities = [];
  String _selectedCategory = 'All';
  bool _isLoading = true;
  bool _isOnline = true;
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
    WidgetsBinding.instance.addObserver(this);
    _checkConnectivity();
    _loadCommunities();
    _searchController.addListener(_onSearchChanged);
  }

  /// Check network connectivity
  Future<void> _checkConnectivity() async {
    final isOnline = await _networkService.isConnected();
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reload when app resumes to refresh joined status
      _checkConnectivity();
      _loadCommunities();
    }
  }

  Future<void> _loadCommunities() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    final schoolCode = user?.instituteId ?? '';

    if (user == null || schoolCode.isEmpty) return;

    setState(() => _isLoading = true);

    // Use repository for offline-first approach
    final communities = await _dashboardRepo.fetchInstituteCommunities(
      schoolCode: schoolCode,
    );

    // Get joined community IDs
    final joinedIds = <String>{};
    for (final community in communities) {
      final isMember = await _communityService.isMember(community.id, user.uid);
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
    final user = authProvider.currentUser;
    final schoolCode = user?.instituteId ?? '';

    if (user == null || schoolCode.isEmpty) return;

    setState(() => _joiningCommunities.add(community.id));

    final success = await _communityService.joinCommunityAsInstitute(
      communityId: community.id,
      userId: user.uid,
      userName: user.name,
      userEmail: user.email,
      schoolCode: schoolCode,
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

      // Small delay to ensure Firestore write propagates
      await Future.delayed(const Duration(milliseconds: 500));
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
    const primaryColor = Color(0xFF146D7A); // Institute teal

    return WillPopScope(
      onWillPop: () async {
        // Return true if any communities were joined to trigger refresh
        Navigator.of(context).pop(_joinedCommunities.isNotEmpty);
        return false;
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: theme.iconTheme.color),
            onPressed: () =>
                Navigator.pop(context, _joinedCommunities.isNotEmpty),
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
            // Offline indicator banner
            if (!_isOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: Colors.orange.shade700,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Offline Mode - Showing cached communities',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
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
                    hintStyle: TextStyle(
                      color: theme.textTheme.bodySmall?.color,
                    ),
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
                separatorBuilder: (_, _) => const SizedBox(width: 8),
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
                            ? primaryColor
                            : (isDark
                                  ? theme.colorScheme.surface
                                  : theme.colorScheme.surfaceContainerHighest
                                        .withOpacity(0.4)),
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
                            fontWeight: FontWeight.w600,
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
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredCommunities.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.groups_outlined,
                            size: 80,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No communities found',
                            style: TextStyle(
                              color: theme.textTheme.bodyLarge?.color,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
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
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _filteredCommunities.length,
                      itemBuilder: (context, index) {
                        final community = _filteredCommunities[index];
                        final isJoined = _joinedCommunities.contains(
                          community.id,
                        );
                        final isJoining = _joiningCommunities.contains(
                          community.id,
                        );

                        return _CommunityCard(
                          community: community,
                          isJoined: isJoined,
                          isJoining: isJoining,
                          onJoin: () => _joinCommunity(community),
                          primaryColor: primaryColor,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    required this.isJoined,
    required this.isJoining,
    required this.onJoin,
    required this.primaryColor,
  });

  final CommunityModel community;
  final bool isJoined;
  final bool isJoining;
  final VoidCallback onJoin;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withOpacity(0.2)
              : theme.colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Community Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    community.getCategoryIcon(),
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Community Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            community.category,
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.people_outline,
                          size: 14,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${community.memberCount}',
                          style: TextStyle(
                            color: theme.textTheme.bodySmall?.color,
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
          // Description
          Text(
            community.description,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 14,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          // Join/Joined Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isJoined || isJoining ? null : onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: isJoined ? Colors.grey[700] : primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              child: isJoining
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isJoined ? Icons.check : Icons.add, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isJoined ? 'Joined' : 'Join Community',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
