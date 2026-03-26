import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/community_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/community_service.dart';
import '../messages/community_chat_page.dart';
import './institute_community_explore_screen.dart';
import '../../services/offline_data_service.dart';
import '../../services/offline_cache_manager.dart';
import '../../widgets/principal_dashboard_header.dart';

class InstituteCommunityScreen extends StatefulWidget {
  const InstituteCommunityScreen({super.key});

  @override
  State<InstituteCommunityScreen> createState() =>
      _InstituteCommunityScreenState();
}

class _InstituteCommunityScreenState extends State<InstituteCommunityScreen>
    with AutomaticKeepAliveClientMixin {
  final CommunityService _communityService = CommunityService();
  final OfflineDataService _offlineService = OfflineDataService();
  final OfflineCacheManager _cacheManager = OfflineCacheManager();
  bool _isLoading = false;
  List<CommunityModel> _joined = [];
  bool _dataLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Load immediately on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Try to load if we haven't successfully loaded yet
    if (!_dataLoaded && !_isLoading) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    final userId = user?.uid ?? '';
    final String schoolCode = (user?.instituteId?.isNotEmpty == true)
        ? (user!.instituteId ?? '')
        : (_cacheManager.getLastPrincipalSchoolCode() ?? '');

    // ✅ Try loading from cache first for instant display
    List<Map<String, dynamic>>? cachedCommunities;
    if (userId.isNotEmpty) {
      cachedCommunities = _offlineService.getCachedInstituteCommunities(userId);
    }

    if ((cachedCommunities == null || cachedCommunities.isEmpty) &&
        schoolCode.isNotEmpty) {
      cachedCommunities = _cacheManager.getCachedInstituteCommunities(
        schoolCode,
      );
    }

    if (cachedCommunities != null && cachedCommunities.isNotEmpty) {
      final cachedList = cachedCommunities;
      if (mounted) {
        setState(() {
          _joined = cachedList
              .map((data) => CommunityModel.fromJson(data))
              .toList();
          _isLoading = false;
          _dataLoaded = true;
        });
      }
    }

    // Only show loading if we don't already have cached data
    if (mounted && _joined.isEmpty) {
      setState(() => _isLoading = true);
    }

    // If auth user is unavailable (offline cold start), keep cached UI and skip network.
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _dataLoaded = _joined.isNotEmpty;
        });
      }
      return;
    }

    try {
      // 🌐 Add 8-second timeout for network fetch - fallback to cache if timeout
      final joinedRaw = await _communityService
          .getMyComm(userId)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint(
                '⏱️ Network timeout loading communities - using cache',
              );
              return [];
            },
          );
      final joined = joinedRaw
          .where((c) => _isEligible(c, schoolCode))
          .toList();

      // ✅ Cache communities for offline access
      if (joined.isNotEmpty) {
        final communitiesData = joined.map((c) => c.toJson()).toList();
        await _offlineService.cacheInstituteCommunities(
          instituteId: userId,
          communities: communitiesData,
        );
        if (schoolCode.isNotEmpty) {
          await _cacheManager.cacheInstituteCommunities(
            schoolCode: schoolCode,
            communities: communitiesData,
          );
        }

        if (mounted) {
          setState(() {
            _joined = joined;
            _isLoading = false;
            _dataLoaded = true; // Mark as successfully loaded
          });
        }
      } else if (_joined.isEmpty) {
        // Network returned empty AND no cached data - show empty state
        if (mounted) {
          setState(() {
            _joined = [];
            _isLoading = false;
            _dataLoaded = true;
          });
        }
      } else {
        // Network returned empty but we have cached data - keep showing it
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading communities from network: $e');
      // ✅ If network fails but we have cached data, keep showing it
      if (mounted && _joined.isEmpty) {
        List<Map<String, dynamic>>? cachedCommunities;
        if (userId.isNotEmpty) {
          cachedCommunities = _offlineService.getCachedInstituteCommunities(
            userId,
          );
        }
        if ((cachedCommunities == null || cachedCommunities.isEmpty) &&
            schoolCode.isNotEmpty) {
          cachedCommunities = _cacheManager.getCachedInstituteCommunities(
            schoolCode,
          );
        }
        if (cachedCommunities != null && cachedCommunities.isNotEmpty) {
          final fallbackList = cachedCommunities;
          setState(() {
            _joined = fallbackList
                .map((data) => CommunityModel.fromJson(data))
                .toList();
            _dataLoaded = true;
            debugPrint(
              '✅ Fallback: Loaded ${_joined.length} communities from cache due to network error',
            );
          });
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

  void _openChat(CommunityModel community) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityChatPage(
          communityId: community.id,
          communityName: community.name,
          icon: community.getCategoryIcon(),
        ),
      ),
    );

    // Refresh the list when returning (user may have left the community)
    if (mounted) {
      _loadData();
    }
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Listen to AuthProvider changes and trigger load when user becomes available
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;

    // If we have user data but haven't loaded communities yet, trigger load
    if (user != null && !_dataLoaded && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadData();
      });
    }

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
              PrincipalDashboardHeader(
                title: 'Communities',
                subtitle: 'Manage school communities',
                icon: Icons.groups_rounded,
                actionIcon: Icons.explore_rounded,
                onActionTap: _openExplore,
              ),
              Expanded(
                child: _isLoading && _joined.isEmpty
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
        constraints: const BoxConstraints(minHeight: 80),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 0.8),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Icon
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _LeadingLetter(
                letter: community.getCategoryIcon(),
                primaryColor: primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            community.name,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right, color: hintColor, size: 20),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Category tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            community.category,
                            style: TextStyle(
                              color: tagTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Member count
                        Icon(Icons.people, size: 14, color: hintColor),
                        const SizedBox(width: 4),
                        Text(
                          '${community.memberCount} members',
                          style: TextStyle(
                            color: hintColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
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
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(child: Text(letter, style: const TextStyle(fontSize: 28))),
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
