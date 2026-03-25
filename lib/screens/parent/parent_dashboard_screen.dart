import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import '../../providers/auth_provider.dart';
import '../../providers/parent_provider.dart';
import '../../models/parent_teacher_group.dart';
import '../../models/student_model.dart';
import '../../models/reward_request_model.dart';
import '../../services/parent_teacher_group_service.dart';
import '../../widgets/notification_bell_button.dart';
import '../../widgets/pending_reward_popup.dart';
import '../common/announcement_pageview_screen.dart';
import 'parent_reward_request_detail_screen.dart';
import 'parent_rewards_screen.dart';
import 'parent_profile_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  final VoidCallback? onSwitchToRewards;
  const ParentDashboardScreen({super.key, this.onSwitchToRewards});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  // Parent green theme colors
  static const Color parentGreen = Color(0xFF14A670);
  final ParentTeacherGroupService _ptGroupService = ParentTeacherGroupService();

  Color _scaffoldBg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  Color _cardColor(BuildContext context) => Theme.of(context).cardColor;

  Color _onBackground(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  final PageController _childrenPageController = PageController();
  Future<List<_SectionGroupDisplayItem>>? _allSectionGroupsFuture;
  String _groupsSignature = '';

  // Flag to prevent popup from showing multiple times in same session
  bool _hasShownRewardPopup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeParentData();
    });
  }

  Future<void> _initializeParentData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);

    // Wait for auth to initialize first
    await authProvider.ensureInitialized();

    if (authProvider.currentUser != null) {
      // Force auth token propagation to Firestore SDK before any queries
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken(false);
      } catch (_) {}

      final parentEmail = authProvider.currentUser!.email;
      final parentId = authProvider.currentUser!.uid;

      await parentProvider.initialize(parentEmail, parentId: parentId);

      // Check for pending reward requests after initialization
      _checkPendingRewards();
    }
  }

  void _checkPendingRewards() {
    // Only show popup once per session
    if (_hasShownRewardPopup) return;

    final parentProvider = Provider.of<ParentProvider>(context, listen: false);

    // Try immediately with whatever is already loaded
    _tryShowRewardPopup(parentProvider);

    // Also listen for the first time rewardRequests becomes populated
    // (the stream may not have emitted yet when initState runs)
    void listener() {
      if (!_hasShownRewardPopup && mounted) {
        _tryShowRewardPopup(parentProvider);
      }
      if (_hasShownRewardPopup) {
        parentProvider.removeListener(listener);
      }
    }

    parentProvider.addListener(listener);

    // Auto-remove listener after 30 seconds to avoid leaks
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) parentProvider.removeListener(listener);
    });
  }

  void _tryShowRewardPopup(ParentProvider parentProvider) {
    if (_hasShownRewardPopup || !mounted) return;

    final allRequests = parentProvider.rewardRequests;
    if (allRequests.isEmpty) return;

    // Filter for pending/awaiting-approval requests belonging to this parent's children
    final childUids = parentProvider.children.map((c) => c.uid).toSet();
    final childStudentIds = parentProvider.children
        .where((c) => c.studentId != null && c.studentId!.isNotEmpty)
        .map((c) => c.studentId!)
        .toSet();

    final pendingRequests = allRequests.where((req) {
      final isPending =
          req.status == RewardRequestStatus.pending ||
          req.status == RewardRequestStatus.requested;
      final isForThisParentsChild =
          childUids.contains(req.studentId) ||
          childStudentIds.contains(req.studentId);
      return isPending && isForThisParentsChild;
    }).toList();

    if (pendingRequests.isEmpty) return;

    // Resolve any missing student names from children list
    final nameMap = <String, String>{
      for (final child in parentProvider.children)
        if (child.name.isNotEmpty) child.uid: child.name,
    };
    final resolved = pendingRequests.map((req) {
      if (req.studentName.isEmpty ||
          req.studentName.toLowerCase() == 'unknown student') {
        final childName = nameMap[req.studentId];
        if (childName != null && childName.isNotEmpty) {
          return RewardRequestModel(
            id: req.id,
            studentId: req.studentId,
            studentName: childName,
            productId: req.productId,
            productName: req.productName,
            productImageUrl: req.productImageUrl,
            amazonLink: req.amazonLink,
            price: req.price,
            pointsRequired: req.pointsRequired,
            status: req.status,
            purchaseMethod: req.purchaseMethod,
            priceEntered: req.priceEntered,
            enteredPrice: req.enteredPrice,
            pointsDeducted: req.pointsDeducted,
            requestedOn: req.requestedOn,
            parentId: req.parentId,
            approvedOn: req.approvedOn,
          );
        }
      }
      return req;
    }).toList();

    _hasShownRewardPopup = true;

    // Show popup after a short delay to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => PendingRewardPopup(
            pendingRequests: resolved,
            onApprove: _navigateToRewardsScreen,
            onLater: () {},
          ),
        );
      }
    });
  }

  void _navigateToRewardsScreen() {
    if (widget.onSwitchToRewards != null) {
      widget.onSwitchToRewards!();
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (context) => const ParentRewardsScreen()),
      );
    }
  }

  @override
  void dispose() {
    _childrenPageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer2<AuthProvider, ParentProvider>(
      builder: (context, authProvider, parentProvider, child) {
        // Show loading skeleton while initializing or loading children
        if (!authProvider.isInitialized || parentProvider.isLoadingChildren) {
          return Scaffold(
            backgroundColor: _scaffoldBg(context),
            body: _buildLoadingSkeleton(isDark),
          );
        }

        // Show message if no children found
        if (!parentProvider.hasChildren) {
          return Scaffold(
            backgroundColor: _scaffoldBg(context),
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.family_restroom,
                      size: 80,
                      color: isDark ? Colors.grey[700] : Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No children found',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : _onBackground(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Make sure your email is linked to student accounts',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => parentProvider.loadChildren(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: parentGreen,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final currentChild = parentProvider.selectedChild!;
        final performanceStats = parentProvider.performanceStats;
        _ensureAllSectionGroupsFuture(parentProvider.children);

        return Scaffold(
          backgroundColor: _scaffoldBg(context),
          body: SafeArea(
            child: Column(
              children: [
                // Header
                _buildHeader(isDark, authProvider),

                // Scrollable Content
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await parentProvider.refresh();
                      if (!mounted) return;
                      setState(() {
                        _allSectionGroupsFuture = _loadAllSectionGroups(
                          parentProvider.children,
                        );
                      });
                    },
                    color: parentGreen,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Children Profile Cards Carousel
                          _buildChildrenCarousel(isDark, parentProvider),

                          const SizedBox(height: 16),

                          // Announcements Section
                          _buildAnnouncementsSection(isDark, parentProvider),

                          const SizedBox(height: 16),

                          // Parent-Teacher Section Groups
                          _buildSectionGroupsSection(isDark, parentProvider),

                          const SizedBox(height: 16),

                          // Performance Summary
                          _buildPerformanceSummary(
                            isDark,
                            currentChild,
                            performanceStats,
                            parentProvider.attendance,
                          ),

                          const SizedBox(height: 16),

                          // Reward Requests
                          _buildRewardRequests(isDark, parentProvider),

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _ensureAllSectionGroupsFuture(List<StudentModel> children) {
    final nextSignature = children
        .map((c) => '${c.uid}|${c.className ?? ''}|${c.section ?? ''}')
        .join('||');
    if (_allSectionGroupsFuture != null && _groupsSignature == nextSignature) {
      return;
    }
    _groupsSignature = nextSignature;
    _allSectionGroupsFuture = _loadAllSectionGroups(children);
  }

  Future<List<_SectionGroupDisplayItem>> _loadAllSectionGroups(
    List<StudentModel> children,
  ) async {
    if (children.isEmpty) return const <_SectionGroupDisplayItem>[];

    final Map<String, _SectionGroupDisplayItem> byGroupId =
        <String, _SectionGroupDisplayItem>{};

    for (final child in children) {
      try {
        final group = await _ptGroupService.ensureGroupForChild(child: child);
        if (group.id.isEmpty) continue;

        final existing = byGroupId[group.id];
        if (existing == null) {
          byGroupId[group.id] = _SectionGroupDisplayItem(
            group: group,
            representativeChildName: child.name,
            representativeChildId: child.uid,
            childNames: <String>{if (child.name.isNotEmpty) child.name},
          );
        } else {
          if (child.name.isNotEmpty) {
            existing.childNames.add(child.name);
          }
        }
      } catch (_) {
        // Skip failed child-group resolution and continue with remaining children.
      }
    }

    final items = byGroupId.values.toList(growable: false)
      ..sort((a, b) => a.group.name.compareTo(b.group.name));
    return items;
  }

  Widget _buildSectionGroupsSection(
    bool isDark,
    ParentProvider parentProvider,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Parent & Teacher Groups',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : _onBackground(context),
              ),
            ),
          ),
          FutureBuilder<List<_SectionGroupDisplayItem>>(
            future: _allSectionGroupsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _cardColor(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _cardColor(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[400]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Could not load groups',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : _onBackground(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _allSectionGroupsFuture = _loadAllSectionGroups(
                              parentProvider.children,
                            );
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final items = snapshot.data ?? const <_SectionGroupDisplayItem>[];
              if (items.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _cardColor(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'No groups available',
                    style: TextStyle(
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                      fontSize: 14,
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final group = item.group;
                  final fallbackTitle =
                      '${group.className.isNotEmpty ? group.className : 'Class'} ${group.section}'
                          .trim();
                  final title = group.name.isNotEmpty
                      ? group.name
                      : '$fallbackTitle Parents & Teachers';
                  final childLabel = item.childNames.length > 1
                      ? 'For ${item.childNames.join(', ')}'
                      : 'Class: ${group.className}${group.section.isNotEmpty ? '-${group.section}' : ''} • ${item.representativeChildName}';

                  return Container(
                    decoration: BoxDecoration(
                      color: _cardColor(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.05),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/parent/section-group-chat',
                          arguments: {
                            'groupId': group.id,
                            'groupName': title,
                            'className': group.className,
                            'section': group.section,
                            'schoolCode': group.schoolCode,
                            'childName': item.representativeChildName,
                            'childId': item.representativeChildId,
                          },
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: parentGreen.withOpacity(0.12),
                              ),
                              child: const Icon(
                                Icons.chat_bubble_outline,
                                color: parentGreen,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : _onBackground(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    childLabel,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[700],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (group.lastMessage.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      group.lastMessage,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.grey[500]
                                            : Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 15,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[600],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, AuthProvider authProvider) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'Dashboard',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : _onBackground(context),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NotificationBellButton(
                    iconColor: isDark ? Colors.white : _onBackground(context),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.person,
                      size: 26,
                      color: isDark ? Colors.white : _onBackground(context),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ParentProfileScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildrenCarousel(bool isDark, ParentProvider parentProvider) {
    final children = parentProvider.children;
    final selectedIndex = parentProvider.selectedChildIndex;
    final cardColor = _cardColor(context);
    final canGoPrev = selectedIndex > 0;
    final canGoNext = selectedIndex < children.length - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          FractionallySizedBox(
            widthFactor: 0.92,
            child: Container(
              height: 124,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.04),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: parentGreen.withOpacity(0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _childrenPageController,
                      onPageChanged: (index) {
                        parentProvider.selectChild(index);
                      },
                      itemCount: children.length,
                      itemBuilder: (context, index) {
                        final child = children[index];
                        final studentName = child.name.trim().isNotEmpty
                            ? child.name
                            : 'Student';
                        final studentClass =
                            '${child.className ?? "Grade"}${child.section != null ? ' - ${child.section}' : ''}';

                        return Row(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF14A670),
                                    Color(0xFF0F8A5A),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: parentGreen.withOpacity(0.28),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDark
                                      ? const Color(0xFF141418)
                                      : Colors.white,
                                ),
                                child: ClipOval(
                                  child:
                                      child.photoUrl != null &&
                                          child.photoUrl!.trim().isNotEmpty
                                      ? Image.network(
                                          child.photoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Center(
                                            child: Text(
                                              studentName[0].toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w700,
                                                color: parentGreen,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            studentName[0].toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                              color: parentGreen,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    studentName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : _onBackground(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    studentClass,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    height: 30,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        if (index == selectedIndex) {
                                          Navigator.pushNamed(
                                            context,
                                            '/parent/child-profile',
                                          );
                                        } else {
                                          parentProvider.selectChild(index);
                                          _childrenPageController.animateToPage(
                                            index,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeInOut,
                                          );
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: parentGreen,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        minimumSize: const Size(0, 30),
                                        elevation: 0,
                                        shape: const StadiumBorder(),
                                      ),
                                      child: const Text(
                                        'View Profile',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (children.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSwitcherArrow(
                  icon: Icons.chevron_left_rounded,
                  enabled: canGoPrev,
                  onTap: () {
                    if (!canGoPrev) return;
                    final prevIndex = selectedIndex - 1;
                    parentProvider.selectChild(prevIndex);
                    _childrenPageController.animateToPage(
                      prevIndex,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
                const SizedBox(width: 12),
                _buildPageIndicator(parentProvider),
                const SizedBox(width: 12),
                _buildSwitcherArrow(
                  icon: Icons.chevron_right_rounded,
                  enabled: canGoNext,
                  onTap: () {
                    if (!canGoNext) return;
                    final nextIndex = selectedIndex + 1;
                    parentProvider.selectChild(nextIndex);
                    _childrenPageController.animateToPage(
                      nextIndex,
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitcherArrow({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? parentGreen.withOpacity(0.16)
              : Colors.grey.withOpacity(0.10),
          border: Border.all(
            color: enabled
                ? parentGreen.withOpacity(0.28)
                : Colors.grey.withOpacity(0.20),
          ),
        ),
        child: Icon(icon, size: 18, color: enabled ? parentGreen : Colors.grey),
      ),
    );
  }

  Widget _buildPageIndicator(ParentProvider parentProvider) {
    final children = parentProvider.children;
    final selectedIndex = parentProvider.selectedChildIndex;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(children.length, (index) {
        final isActive = index == selectedIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? parentGreen : parentGreen.withOpacity(0.24),
          ),
        );
      }),
    );
  }

  Widget _buildAnnouncementsSection(
    bool isDark,
    ParentProvider parentProvider,
  ) {
    // Filter announcements to only those within 24 hours or with future expiresAt
    final now = DateTime.now();
    final announcements = parentProvider.announcements.where((a) {
      final createdAt = a['createdAt'];
      final expiresAt = a['expiresAt'];
      DateTime? created;
      DateTime? expiry;
      if (createdAt is Timestamp) {
        created = createdAt.toDate();
      } else if (createdAt is DateTime) {
        created = createdAt;
      } else if (createdAt is String) {
        try {
          created = DateTime.parse(createdAt);
        } catch (_) {}
      }
      if (expiresAt is Timestamp) {
        expiry = expiresAt.toDate();
      } else if (expiresAt is DateTime) {
        expiry = expiresAt;
      } else if (expiresAt is String) {
        try {
          expiry = DateTime.parse(expiresAt);
        } catch (_) {}
      }
      // If expiry provided, use it; else fallback to 24h from created
      if (expiry != null) {
        return expiry.isAfter(now);
      }
      if (created != null) {
        return now.difference(created) < const Duration(hours: 24);
      }
      // If timestamps missing, keep to be safe
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title with Icon
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: parentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.campaign, color: parentGreen, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'Announcements',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : _onBackground(context),
                ),
              ),
            ],
          ),
        ),

        // Horizontal scrollable list of circular avatars
        SizedBox(
          height: 88,
          child: announcements.isEmpty
              ? _buildEmptyAnnouncementsList(isDark)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: announcements.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    final announcement = announcements[index];
                    return _buildAnnouncementAvatar(isDark, announcement);
                  },
                ),
        ),
      ],
    );
  }

  /// Empty announcements list
  Widget _buildEmptyAnnouncementsList(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mail_outline,
              size: 30,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 6),
            Text(
              'No announcements yet',
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual announcement avatar (circular with gradient border)
  Widget _buildAnnouncementAvatar(
    bool isDark,
    Map<String, dynamic> announcement,
  ) {
    final teacherName = announcement['teacherName'] as String? ?? 'Teacher';
    final teacherInitial = teacherName.isNotEmpty
        ? teacherName[0].toUpperCase()
        : 'T';
    final title = announcement['title'] as String? ?? 'Announcement';
    final description = announcement['description'] as String? ?? '';

    return GestureDetector(
      onTap: () {
        // Role mapping: prefer explicit role, fallback to 'teacher'
        final role =
            (announcement['role'] as String?)?.toLowerCase() ?? 'teacher';
        final postedByLabel =
            'Posted by ${role[0].toUpperCase()}${role.substring(1)}';

        // Parse timestamps
        DateTime? postedAt;
        DateTime? expiresAt;
        final createdAt = announcement['createdAt'];
        final expAt = announcement['expiresAt'];
        if (createdAt is Timestamp) {
          postedAt = createdAt.toDate();
        } else if (createdAt is DateTime) {
          postedAt = createdAt;
        } else if (createdAt is String) {
          try {
            postedAt = DateTime.parse(createdAt);
          } catch (_) {}
        }
        if (expAt is Timestamp) {
          expiresAt = expAt.toDate();
        } else if (expAt is DateTime) {
          expiresAt = expAt;
        } else if (expAt is String) {
          try {
            expiresAt = DateTime.parse(expAt);
          } catch (_) {}
        }
        // Fallback to 24h expiry if not provided
        expiresAt ??= (postedAt != null)
            ? postedAt.add(const Duration(hours: 24))
            : DateTime.now().add(const Duration(hours: 24));

        openAnnouncementPageView(
          context,
          announcements: [
            {
              'role': role,
              'title': title,
              'subtitle': description,
              'postedByLabel': postedByLabel,
              'avatarUrl': announcement['teacherPhotoUrl'] as String?,
              'postedAt': postedAt,
              'expiresAt': expiresAt,
            },
          ],
          initialIndex: 0,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with gradient border
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF14A670), Color(0xFF0F8A5A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _scaffoldBg(context),
              ),
              padding: const EdgeInsets.all(2),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: parentGreen.withOpacity(0.1),
                child: Text(
                  teacherInitial,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: parentGreen,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Teacher name (truncated to first name)
          SizedBox(
            width: 68,
            child: Text(
              teacherName.split(' ').first,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: parentGreen,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSummary(
    bool isDark,
    StudentModel child,
    Map<String, dynamic> performanceStats,
    double attendance,
  ) {
    final rewardPoints = child.rewardPoints;
    final testsCompleted = (performanceStats['completedTests'] ?? 0) as int;
    final attendancePercentage = attendance > 0
        ? attendance
        : (child.monthlyProgress * 100);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Performance Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : _onBackground(context),
              ),
            ),
          ),

          // Performance Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.emoji_events,
                  value: rewardPoints.toString(),
                  label: 'Rewards',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.history_edu,
                  value: testsCompleted.toString(),
                  label: 'Tests Attended',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  isDark: isDark,
                  icon: Icons.task_alt,
                  value: '${attendancePercentage.toStringAsFixed(0)}%',
                  label: 'Attendance',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0 : 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: parentGreen, size: 27),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : _onBackground(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.requested:
        return const Color(0xFFF59E0B);
      case RewardRequestStatus.pending:
        return const Color(0xFFF2800D);
      case RewardRequestStatus.pendingPrice:
        return const Color(0xFFEA580C);
      case RewardRequestStatus.approved:
        return const Color(0xFF16A34A);
      case RewardRequestStatus.orderPlaced:
        return const Color(0xFF0EA5E9);
      case RewardRequestStatus.delivered:
        return const Color(0xFF0D9488);
      case RewardRequestStatus.rejected:
        return const Color(0xFFEF4444);
    }
  }

  String _getStatusText(RewardRequestStatus status) {
    switch (status) {
      case RewardRequestStatus.requested:
        return 'Requested';
      case RewardRequestStatus.pending:
        return 'Pending';
      case RewardRequestStatus.pendingPrice:
        return 'Pending Price';
      case RewardRequestStatus.approved:
        return 'Approved';
      case RewardRequestStatus.orderPlaced:
        return 'Order Placed';
      case RewardRequestStatus.delivered:
        return 'Delivered';
      case RewardRequestStatus.rejected:
        return 'Rejected';
    }
  }

  Widget _buildRewardRequests(bool isDark, ParentProvider parentProvider) {
    // Show all requests (pending, approved, orderPlaced) but not rejected
    final rewardRequests = parentProvider.rewardRequests
        .where((r) => r.status != RewardRequestStatus.rejected)
        .toList();

    // Count only pending requests for the badge
    final pendingCount = rewardRequests
        .where(
          (r) =>
              r.status == RewardRequestStatus.requested ||
              r.status == RewardRequestStatus.pending ||
              r.status == RewardRequestStatus.pendingPrice,
        )
        .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Reward Requests',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : _onBackground(context),
                  ),
                ),
                if (pendingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF14A670), Color(0xFF0F8A5A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: parentGreen.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.notifications_active,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Reward Requests List
          if (rewardRequests.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _cardColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.1)
                      : Colors.transparent,
                ),
              ),
              child: Center(
                child: Text(
                  'No reward requests',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            )
          else
            ...rewardRequests.map((request) {
              IconData icon = Icons.emoji_events;
              if (request.productName.toLowerCase().contains('game')) {
                icon = Icons.sports_esports;
              } else if (request.productName.toLowerCase().contains(
                    'ice cream',
                  ) ||
                  request.productName.toLowerCase().contains('food')) {
                icon = Icons.icecream;
              } else if (request.productName.toLowerCase().contains('book')) {
                icon = Icons.book;
              } else if (request.productName.toLowerCase().contains('toy')) {
                icon = Icons.toys;
              }

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ParentRewardRequestDetailScreen(request: request),
                      ),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _cardColor(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.transparent,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0 : 0.02),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: parentGreen.withOpacity(isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: parentGreen, size: 24),
                        ),
                        const SizedBox(width: 16),

                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.productName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white
                                      : _onBackground(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '${request.pointsRequired} Points',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Status badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(
                                        request.status,
                                      ).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _getStatusText(request.status),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _getStatusColor(request.status),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Approve/Reject Buttons (only for pending)
                        if (request.status == RewardRequestStatus.pending)
                          Row(
                            children: [
                              IconButton(
                                onPressed: () async {
                                  final success = await parentProvider
                                      .approveRewardRequest(request.id);
                                  if (success && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Reward request approved!',
                                        ),
                                        backgroundColor: parentGreen,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.check_circle,
                                  color: parentGreen,
                                ),
                                tooltip: 'Approve',
                              ),
                              IconButton(
                                onPressed: () async {
                                  final success = await parentProvider
                                      .rejectRewardRequest(request.id, null);
                                  if (success && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          'Reward request rejected',
                                        ),
                                        backgroundColor: Colors.red[400],
                                      ),
                                    );
                                  }
                                },
                                icon: Icon(
                                  Icons.cancel,
                                  color: Colors.red[400],
                                ),
                                tooltip: 'Reject',
                              ),
                            ],
                          ),
                        // Arrow for approved/order placed requests
                        if (request.status != RewardRequestStatus.pending)
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Loading skeleton placeholder - similar to teacher dashboard
  Widget _buildLoadingSkeleton(bool isDark) {
    final shimmerColor = isDark ? Colors.grey[800] : Colors.grey[300];

    return Column(
      children: [
        // Header skeleton
        Container(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 200,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: shimmerColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 150,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: shimmerColor,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Child card skeleton
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: shimmerColor,
                  ),
                ),
                const SizedBox(height: 24),
                // Stats cards skeleton
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: shimmerColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: shimmerColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // More cards skeleton
                ...List.generate(
                  2,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: shimmerColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionGroupDisplayItem {
  final ParentTeacherGroup group;
  final String representativeChildName;
  final String representativeChildId;
  final Set<String> childNames;

  _SectionGroupDisplayItem({
    required this.group,
    required this.representativeChildName,
    required this.representativeChildId,
    required this.childNames,
  });
}
