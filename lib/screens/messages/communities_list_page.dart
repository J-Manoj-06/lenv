import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/community.dart';
import '../../providers/unread_count_provider.dart';
import '../../services/group_messaging_service.dart';
import '../../utils/chat_type_config.dart';
import 'community_chat_page.dart';

// Helper for category-to-color mapping
Color _getCategoryColor(String description) {
  final s = description.toLowerCase();
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

class CommunitiesListPage extends StatefulWidget {
  final String studentId;

  const CommunitiesListPage({super.key, required this.studentId});

  @override
  State<CommunitiesListPage> createState() => _CommunitiesListPageState();
}

class _CommunitiesListPageState extends State<CommunitiesListPage>
    with WidgetsBindingObserver {
  final GroupMessagingService _messagingService = GroupMessagingService();
  List<Community> _communities = [];
  bool _isLoading = true;
  final Map<String, StreamSubscription?> _messageListeners = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCommunities();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh unread when app resumes
    if (state == AppLifecycleState.resumed) {
      _refreshUnreadCounts();
    }
  }

  void _refreshUnreadCounts() {
    try {
      final unread = Provider.of<UnreadCountProvider>(context, listen: false);
      for (final community in _communities) {
        unread.refreshChat(community.id);
      }
    } catch (_) {}
  }

  Future<void> _loadCommunities() async {
    setState(() => _isLoading = true);

    try {
      final communities = await _messagingService.getAllCommunities();

      setState(() {
        _communities = communities;
        _isLoading = false;
      });

      // Listen for message updates to refresh badges
      for (final c in communities) {
        _listenForCommunityMessages(c.id);
      }

      // Load unread counts in batch for all communities
      try {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        final ids = communities.map((c) => c.id).toList();
        final types = {
          for (final c in communities) c.id: ChatTypeConfig.communityChat,
        };
        await unread.loadUnreadCountsBatch(chatIds: ids, chatTypes: types);
      } catch (_) {}
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _listenForCommunityMessages(String communityId) {
    // Cancel previous listener if any
    _messageListeners[communityId]?.cancel();

    final query = FirebaseFirestore.instance
        .collection('communities')
        .doc(communityId)
        .collection('messages')
        .orderBy('createdAt', descending: true);

    _messageListeners[communityId] = query.snapshots().listen((snapshot) {
      if (!mounted) return;
      try {
        final unread = Provider.of<UnreadCountProvider>(context, listen: false);
        unread.loadUnreadCount(
          chatId: communityId,
          chatType: ChatTypeConfig.communityChat,
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    for (final sub in _messageListeners.values) {
      sub?.cancel();
    }
    _messageListeners.clear();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8800)),
      );
    }

    if (_communities.isEmpty) {
      return const Center(
        child: Text(
          'No communities available yet.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _communities.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final community = _communities[index];
        return _CommunityCard(
          community: community,
          onTap: () {
            // Optimistically mark as read before navigating
            try {
              final unread = Provider.of<UnreadCountProvider>(
                context,
                listen: false,
              );
              unread.markChatAsRead(community.id);
            } catch (_) {}
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CommunityChatPage(
                  communityId: community.id,
                  communityName: community.name,
                  icon: community.icon,
                ),
              ),
            ).then((_) {
              // Ensure badge stays cleared immediately after return
              try {
                final unread = Provider.of<UnreadCountProvider>(
                  context,
                  listen: false,
                );
                unread.markChatAsRead(community.id);
                unread.refreshChat(community.id);
                unread.loadUnreadCount(
                  chatId: community.id,
                  chatType: ChatTypeConfig.communityChat,
                );
              } catch (_) {}
            });
          },
        );
      },
    );
  }
}

class _CommunityCard extends StatelessWidget {
  final Community community;
  final VoidCallback onTap;

  const _CommunityCard({required this.community, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _getCategoryColor(community.description);

    return Container(
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
          onTap: onTap,
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
              const SizedBox(width: 12),
              // Icon with gradient
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
                    community.icon,
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
                            community.description,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
    );
  }
}
