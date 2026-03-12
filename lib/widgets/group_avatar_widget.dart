import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_dp_provider.dart';
import '../services/profile_dp_service.dart';
import '../widgets/dp_options_bottom_sheet.dart';
import '../screens/common/full_screen_dp_viewer.dart';

/// Circular avatar for a group chat — shows group image or icon fallback.
///
/// Used in chat lists, chat headers, and group info screens.
class GroupAvatarWidget extends StatelessWidget {
  final String groupId;
  final String groupName;
  final double size;
  final bool isTeacher;
  final VoidCallback? onTap;
  final String? icon; // emoji icon fallback

  const GroupAvatarWidget({
    super.key,
    required this.groupId,
    required this.groupName,
    this.size = 48,
    this.isTeacher = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileDPProvider>(
      builder: (ctx, dpProvider, _) {
        // Subscribe for real-time update
        dpProvider.watchGroupDP(groupId);
        final imageUrl = dpProvider.getGroupDP(groupId);
        final hasImage = imageUrl != null && imageUrl.isNotEmpty;
        final avatarColor = Color(ProfileDPService.getAvatarColor(groupName));

        return GestureDetector(
          onTap:
              onTap ??
              (hasImage
                  ? () => Navigator.of(context).push(
                      FullScreenDPViewer.route(
                        imageUrl: imageUrl,
                        userName: groupName,
                      ),
                    )
                  : null),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarColor.withOpacity(0.15),
                  border: Border.all(
                    color: avatarColor.withOpacity(0.35),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: dpProvider.isUploading
                      ? _buildUploadProgress(dpProvider, avatarColor)
                      : hasImage
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          cacheKey: dpProvider.getGroupCacheKey(groupId),
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 250),
                          fadeInCurve: Curves.easeIn,
                          placeholder: (_, __) => _buildShimmer(avatarColor),
                          errorWidget: (_, __, ___) =>
                              _buildFallback(avatarColor),
                        )
                      : _buildFallback(avatarColor),
                ),
              ),
              // Edit overlay (teachers only)
              if (isTeacher)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: size * 0.28,
                    height: size * 0.28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: avatarColor,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: size * 0.15,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallback(Color avatarColor) {
    if (icon != null && icon!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        color: avatarColor.withOpacity(0.15),
        alignment: Alignment.center,
        child: Text(icon!, style: TextStyle(fontSize: size * 0.45)),
      );
    }
    // Use initials
    final initials = ProfileDPService.getInitials(groupName);
    return Container(
      width: size,
      height: size,
      color: avatarColor.withOpacity(0.15),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.33,
          fontWeight: FontWeight.bold,
          color: avatarColor,
        ),
      ),
    );
  }

  Widget _buildShimmer(Color color) {
    return _ShimmerBox(width: size, height: size, color: color);
  }

  Widget _buildUploadProgress(ProfileDPProvider provider, Color color) {
    return Container(
      width: size,
      height: size,
      color: color.withOpacity(0.12),
      alignment: Alignment.center,
      child: CircularProgressIndicator(
        value: provider.uploadProgress / 100,
        color: color,
        strokeWidth: 2,
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width, height;
  final Color color;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);
  late final Animation<double> _anim = Tween<double>(
    begin: 0.25,
    end: 0.65,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        color: widget.color.withOpacity(_anim.value),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group Info Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Screen shown when a user taps the group header — displays group info
/// and allows teachers to manage the group DP.
class GroupInfoScreen extends StatelessWidget {
  final String groupId;
  final String groupName;
  final String subjectName;
  final String className;
  final String? section;
  final bool isTeacher;
  final String? icon;
  final List<Map<String, dynamic>> members;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.subjectName,
    required this.className,
    this.section,
    this.isTeacher = false,
    this.icon,
    this.members = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
        backgroundColor: isDark ? Colors.black : const Color(0xFF355872),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Group header with DP
            _buildGroupHeader(context, isDark),
            const SizedBox(height: 16),
            // Members section
            if (members.isNotEmpty) _buildMembersList(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Group DP circle
          GroupAvatarWidget(
            groupId: groupId,
            groupName: groupName,
            size: 128,
            isTeacher: isTeacher,
            icon: icon,
            onTap: isTeacher
                ? () => DPOptionsBottomSheet.show(
                    context: context,
                    userId: groupId,
                    userName: groupName,
                    currentImageUrl: context
                        .read<ProfileDPProvider>()
                        .getGroupDP(groupId),
                    isGroupDP: true,
                    groupId: groupId,
                  )
                : () {
                    final url = context.read<ProfileDPProvider>().getGroupDP(
                      groupId,
                    );
                    if (url != null && url.isNotEmpty) {
                      Navigator.of(context).push(
                        FullScreenDPViewer.route(
                          imageUrl: url,
                          userName: groupName,
                        ),
                      );
                    }
                  },
          ),
          const SizedBox(height: 16),
          Text(
            groupName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subjectName,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            section != null && section!.isNotEmpty
                ? '$className \u2013 Section $section'
                : className,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          if (isTeacher) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => DPOptionsBottomSheet.show(
                context: context,
                userId: groupId,
                userName: groupName,
                currentImageUrl: context.read<ProfileDPProvider>().getGroupDP(
                  groupId,
                ),
                isGroupDP: true,
                groupId: groupId,
              ),
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('Change Group Photo'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF355872),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMembersList(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '${members.length} Members',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : Colors.black45,
              ),
            ),
          ),
          ...members.map((m) => _MemberTile(member: m, isDark: isDark)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool isDark;

  const _MemberTile({required this.member, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final name = member['name'] as String? ?? 'Unknown';
    final role = member['role'] as String? ?? '';
    final uid = member['uid'] as String? ?? '';

    return Consumer<ProfileDPProvider>(
      builder: (ctx, dpProvider, _) {
        final dpUrl = dpProvider.getCachedUserDP(uid);
        final cacheKey = dpProvider.getUserCacheKey(uid);
        final avatarColor = Color(ProfileDPService.getAvatarColor(name));
        final initials = ProfileDPService.getInitials(name);

        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarColor.withOpacity(0.15),
            ),
            child: ClipOval(
              child: dpUrl != null && dpUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: dpUrl,
                      cacheKey: cacheKey,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 200),
                      fadeInCurve: Curves.easeIn,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: avatarColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: avatarColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
            ),
          ),
          title: Text(
            name,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: role.isNotEmpty
              ? Text(
                  role,
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 12,
                  ),
                )
              : null,
        );
      },
    );
  }
}
