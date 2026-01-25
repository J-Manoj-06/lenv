import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/community.dart';
import '../../providers/unread_count_provider.dart';
import '../../services/group_messaging_service.dart';
import '../../utils/chat_type_config.dart';
import '../../widgets/unread_badge_widget.dart';
import 'community_chat_page.dart';

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Orange accent bar on the left
            Container(
              width: 4,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFF8800),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 16),

            // Community Icon
            Text(community.icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 16),

            // Community Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    community.description,
                    style: const TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Arrow Icon
            SizedBox(
              width: 56,
              child: Align(
                alignment: Alignment.centerRight,
                child: Consumer<UnreadCountProvider>(
                  builder: (_, provider, __) {
                    final count = provider.getUnreadCount(community.id);
                    return UnreadBadge(count: count);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
