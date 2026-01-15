import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/community_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/community_service.dart';
import '../messages/community_chat_page.dart';
import './institute_community_explore_screen.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E0F14) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1A1C23) : Colors.white;
    final primaryColor = const Color(0xFF146D7A);
    final tagTextColor = isDark
        ? const Color(0xFF8BD3DF)
        : const Color(0xFF0E7490);
    final borderColor = isDark
        ? const Color(0xFF27303A)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF64748B);
    final hintColor = isDark ? Colors.white54 : const Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: Column(
            children: [
              _TopBar(
                onRefresh: _loadData,
                bgColor: bgColor,
                textColor: textColor,
                subtitleColor: subtitleColor,
              ),
              Expanded(
                child: _isLoading
                    ? _LoadingList(
                        cardColor: cardColor,
                        borderColor: borderColor,
                      )
                    : _joined.isEmpty
                    ? Center(
                        child: Text(
                          'No communities joined yet\nTap "Explore Communities" below',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subtitleColor),
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
                            cardColor: cardColor,
                            borderColor: borderColor,
                            primaryColor: primaryColor,
                            tagTextColor: tagTextColor,
                            textColor: textColor,
                            subtitleColor: subtitleColor,
                            hintColor: hintColor,
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
        backgroundColor: primaryColor,
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
  const _TopBar({
    required this.onRefresh,
    required this.bgColor,
    required this.textColor,
    required this.subtitleColor,
  });

  final VoidCallback onRefresh;
  final Color bgColor;
  final Color textColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Communities',
              style: TextStyle(
                color: textColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: Icon(Icons.refresh, color: subtitleColor),
          ),
        ],
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.community,
    required this.onTap,
    required this.cardColor,
    required this.borderColor,
    required this.primaryColor,
    required this.tagTextColor,
    required this.textColor,
    required this.subtitleColor,
    required this.hintColor,
  });

  final CommunityModel community;
  final VoidCallback onTap;
  final Color cardColor;
  final Color borderColor;
  final Color primaryColor;
  final Color tagTextColor;
  final Color textColor;
  final Color subtitleColor;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 0.7),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LeadingLetter(
              letter: community.getCategoryIcon(),
              primaryColor: primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    community.name,
                    style: TextStyle(
                      color: textColor,
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
                      color: primaryColor.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      community.category,
                      style: TextStyle(
                        color: tagTextColor,
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
                    style: TextStyle(color: subtitleColor, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${community.memberCount} members • ${community.scope == 'global' ? 'Global' : 'School'}',
                    style: TextStyle(color: hintColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: hintColor),
          ],
        ),
      ),
    );
  }
}

class _LeadingLetter extends StatelessWidget {
  const _LeadingLetter({required this.letter, required this.primaryColor});

  final String letter;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: primaryColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList({required this.cardColor, required this.borderColor});

  final Color cardColor;
  final Color borderColor;

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
              color: cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 0.7),
            ),
            height: 88,
          ),
        ),
      ),
    );
  }
}
