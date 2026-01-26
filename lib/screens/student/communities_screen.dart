import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/unread_count_provider.dart';
import '../../utils/unread_count_mixins.dart';
import '../../utils/chat_type_config.dart';
import '../../models/community_model.dart';
import '../../providers/student_provider.dart';
import '../../services/community_service.dart';
import 'community_explore_screen.dart';
import 'community_chat_screen.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen>
    with UnreadCountMixin<CommunitiesScreen>, AutomaticKeepAliveClientMixin {
  final CommunityService _communityService = CommunityService();
  bool _isLoading = true;
  List<CommunityModel> _myCommunities = [];
  final Map<String, int> _lastMessageTs = {}; // communityId -> latest timestamp
  final Map<String, dynamic> _messageListeners =
      {}; // Store listeners for cleanup
  bool _hasLoadedOnce = false;

  @override
  bool get wantKeepAlive => true;

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

  @override
  void dispose() {
    // Cancel all message listeners
    for (final listener in _messageListeners.values) {
      listener?.cancel?.call();
    }
    _messageListeners.clear();
    super.dispose();
  }

  void _listenForCommunityMessageUpdates(String communityId) {
    // Listen to all messages, not just the latest one, to ensure we catch every update
    final query = FirebaseFirestore.instance
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .orderBy('createdAt', descending: true);

    // Store the listener so we can cancel it on dispose
    _messageListeners[communityId] = query.snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty && mounted) {
        final newTs =
            (snapshot.docs.first.data()['createdAt'] as Timestamp?)
                ?.millisecondsSinceEpoch ??
            0;

        // Update timestamp and resort immediately
        _lastMessageTs[communityId] = newTs;
        _resortCommunities();

        // Refresh unread count for this community
        try {
          final unread = Provider.of<UnreadCountProvider>(
            context,
            listen: false,
          );
          unread.loadUnreadCount(
            chatId: communityId,
            chatType: ChatTypeConfig.communityChat,
          );
        } catch (_) {}
      }
    }, onError: (e) => {});
  }

  void _resortCommunities() {
    if (mounted) {
      setState(() {
        _myCommunities.sort((a, b) {
          final at = _lastMessageTs[a.id] ?? 0;
          final bt = _lastMessageTs[b.id] ?? 0;
          return bt.compareTo(at);
        });
      });
    }
  }

  Future<void> _loadMyCommunities() async {
    final studentProvider = Provider.of<StudentProvider>(
      context,
      listen: false,
    );
    final student = studentProvider.currentStudent;

    if (student == null) return;

    setState(() => _isLoading = true);

    // Ensure unread provider has user (fallback to student uid if Auth not ready)
    try {
      final unread = Provider.of<UnreadCountProvider>(context, listen: false);
      final uid = studentProvider.currentStudent?.uid;
      if (uid != null && uid.isNotEmpty) {
        unread.initialize(uid);
      }
    } catch (_) {}

    final communities = await _communityService.getMyComm(student.uid);

    // Fetch latest message timestamp for each community
    for (final c in communities) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('communities')
            .doc(c.id)
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final ts =
              (snap.docs.first.data()['createdAt'] as Timestamp?)
                  ?.millisecondsSinceEpoch ??
              0;
          _lastMessageTs[c.id] = ts;
        } else {
          _lastMessageTs[c.id] = 0;
        }
      } catch (_) {
        _lastMessageTs[c.id] = 0;
      }
    }

    setState(() {
      _myCommunities = communities;
      // Sort by latest message
      _myCommunities.sort((a, b) {
        final at = _lastMessageTs[a.id] ?? 0;
        final bt = _lastMessageTs[b.id] ?? 0;
        return bt.compareTo(at);
      });
      _isLoading = false;
    });

    // Load unread counts for all joined communities
    final chatIds = communities.map((c) => c.id).toList();
    final chatTypes = {
      for (final c in communities) c.id: ChatTypeConfig.communityChat,
    };
    await loadUnreadCountsForChats(chatIds: chatIds, chatTypes: chatTypes);

    // Cancel old listeners before setting up new ones
    for (final listener in _messageListeners.values) {
      listener?.cancel?.call();
    }
    _messageListeners.clear();

    // Set up real-time listeners for all communities to resort on new messages
    for (final c in communities) {
      _listenForCommunityMessageUpdates(c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
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
        heroTag: 'student_communities_explore_fab',
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CommunityExploreScreen(),
            ),
          );
          // Reload if any communities were joined
          if (result == true) {
            await _loadMyCommunities();
          }
        },
        backgroundColor: const Color(0xFFF2800D),
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
            'Join communities to connect with\nstudents and teachers',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CommunityExploreScreen(),
                ),
              );
              if (result == true) {
                await _loadMyCommunities();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2800D),
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
    final isDark = theme.brightness == Brightness.dark;
    final color = _getCategoryColor(community.category);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CommunityChatScreen(community: community),
          ),
        ).then((_) {
          // Optimistically clear unread, then refresh from backend
          final unreadProvider = Provider.of<UnreadCountProvider>(
            context,
            listen: false,
          );
          unreadProvider.markChatAsRead(community.id);
          unreadProvider.refreshChat(community.id);
          unreadProvider.loadUnreadCount(
            chatId: community.id,
            chatType: ChatTypeConfig.communityChat,
          );
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 0),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222222) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                // Orange vertical line
                Container(
                  width: 4,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8800),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                // Icon with gradient
                const SizedBox(width: 12),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
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
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Category Tag
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white12
                                  : theme.dividerColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              community.category,
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[700],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Member Count
                          Icon(
                            Icons.people,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${community.memberCount} member${community.memberCount != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey[700],
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Arrow Icon
                Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    final s = category.toLowerCase();
    if (s.contains('career')) return const Color(0xFF4A90E2);
    if (s.contains('sport')) return const Color(0xFF2ECC71);
    if (s.contains('coding') || s.contains('tech')) {
      return const Color(0xFF3498DB);
    }
    if (s.contains('music')) return const Color(0xFF9B59B6);
    if (s.contains('arts') || s.contains('art')) return const Color(0xFFE67E22);
    if (s.contains('health')) return const Color(0xFFE74C3C);
    return const Color(0xFFF2800D);
  }
}
