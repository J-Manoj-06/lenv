import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/community_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/community_service.dart';
import '../messages/community_chat_page.dart';
import './institute_community_explore_screen.dart';

const Color _background = Color(0xFF0E0F14);
const Color _card = Color(0xFF1A1C23);
const Color _primary = Color(0xFF146D7A); // institute teal
const Color _tagText = Color(0xFF8BD3DF);
const Color _border = Color(0xFF27303A);

class InstituteMessagesScreen extends StatefulWidget {
  const InstituteMessagesScreen({super.key});

  @override
  State<InstituteMessagesScreen> createState() =>
      _InstituteMessagesScreenState();
}

class _InstituteMessagesScreenState extends State<InstituteMessagesScreen> {
  final CommunityService _communityService = CommunityService();
  bool _isLoading = true;
  List<CommunityModel> _joined = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    final schoolCode = user?.instituteId ?? '';
    if (user == null || schoolCode.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    final joinedRaw = await _communityService.getMyComm(user.uid);
    final joined = joinedRaw.where((c) => _isEligible(c, schoolCode)).toList();

    setState(() {
      _joined = joined;
      _isLoading = false;
    });
  }

  bool _isEligible(CommunityModel c, String schoolCode) {
    // Check for both 'institute' and 'principal' role names
    final audienceOk =
        c.audienceRoles.contains('institute') ||
        c.audienceRoles.contains('principal');
    final scopeOk =
        c.scope == 'global' ||
        (c.scope == 'school' && c.schoolCode == schoolCode);
    return audienceOk && scopeOk;
  }

  void _openChat(CommunityModel community) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatPage(
          communityId: community.id,
          communityName: community.name,
          icon: community.getCategoryIcon(),
        ),
      ),
    );
  }

  Future<void> _openExplore() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InstituteCommunityExploreScreen(),
      ),
    );

    // Refresh if user joined any communities
    if (result == true && mounted) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: Column(
            children: [
              _TopBar(onRefresh: _loadData),
              Expanded(
                child: _isLoading
                    ? _LoadingList()
                    : _joined.isEmpty
                    ? const Center(
                        child: Text(
                          'No communities joined yet\nTap "Explore Communities" below',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _joined.length,
                        itemBuilder: (context, index) {
                          final community = _joined[index];
                          return _CommunityCard(
                            community: community,
                            onTap: () => _openChat(community),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openExplore,
        backgroundColor: _primary,
        icon: const Icon(Icons.explore, color: Colors.white),
        label: const Text(
          'Explore Communities',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Communities',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.community, required this.onTap});

  final CommunityModel community;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 0.7),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LeadingLetter(letter: community.getCategoryIcon()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      community.category,
                      style: const TextStyle(
                        color: _tagText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    community.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${community.memberCount} members • ${community.scope == 'global' ? 'Global' : 'School'}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

class _LeadingLetter extends StatelessWidget {
  const _LeadingLetter({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _primary.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: _primary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border, width: 0.7),
            ),
            height: 88,
          ),
        ),
      ),
    );
  }
}
