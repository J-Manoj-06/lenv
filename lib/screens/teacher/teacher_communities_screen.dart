import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/community_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/community_service.dart';
import 'teacher_community_explore_screen.dart';
import 'teacher_community_chat_screen.dart';

class TeacherCommunitiesScreen extends StatefulWidget {
  const TeacherCommunitiesScreen({super.key});

  @override
  State<TeacherCommunitiesScreen> createState() =>
      _TeacherCommunitiesScreenState();
}

class _TeacherCommunitiesScreenState extends State<TeacherCommunitiesScreen>
    with AutomaticKeepAliveClientMixin {
  final CommunityService _communityService = CommunityService();
  bool _isLoading = true;
  List<CommunityModel> _myCommunities = [];
  bool _hasLoadedOnce = false;

  @override
  bool get wantKeepAlive => true; // ✅ Preserve state when switching tabs

  @override
  void initState() {
    super.initState();
    // Load immediately on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasLoadedOnce) {
        _hasLoadedOnce = true;
        _loadMyCommunities();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fallback if not loaded yet
    if (!_hasLoadedOnce) {
      _hasLoadedOnce = true;
      _loadMyCommunities();
    }
  }

  Future<void> _loadMyCommunities() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    setState(() => _isLoading = true);

    final communities = await _communityService.getMyComm(currentUser.uid);

    setState(() {
      _myCommunities = communities;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _myCommunities.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadMyCommunities,
              color: theme.colorScheme.primary,
              backgroundColor: theme.cardColor,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _myCommunities.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final community = _myCommunities[index];
                  return _buildCommunityCard(community);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'teacher_communities_explore_fab',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TeacherCommunityExploreScreen(),
            ),
          ).then((_) => _loadMyCommunities()); // Reload after exploring
        },
        backgroundColor: const Color(0xFF7A5CFF),
        icon: const Icon(Icons.explore, color: Colors.white),
        label: Text(
          'Explore Communities',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              Icons.groups,
              size: 60,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Communities Yet',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Join communities to connect with\nteachers and educators',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TeacherCommunityExploreScreen(),
                ),
              ).then((_) => _loadMyCommunities());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7A5CFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.explore, color: Colors.white),
            label: const Text(
              'Explore Communities',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(CommunityModel community) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                TeacherCommunityChatScreen(community: community),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.15),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          community.name,
                          style: TextStyle(
                            color: theme.textTheme.bodyLarge?.color,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (community.memberCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people,
                                size: 12,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${community.memberCount}',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (community.lastMessagePreview.isNotEmpty)
                    Text(
                      community.lastMessagePreview,
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      community.description,
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          community.category.toUpperCase(),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        community.scope == 'global'
                            ? Icons.public
                            : Icons.school,
                        size: 14,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.4,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        community.scope == 'global' ? 'Global' : 'School',
                        style: TextStyle(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.4,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Arrow
            Icon(
              Icons.arrow_forward_ios,
              color: theme.iconTheme.color?.withOpacity(0.3),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
