import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_dp_provider.dart';
import '../screens/common/full_screen_dp_viewer.dart';
import '../services/profile_dp_service.dart';

/// Reusable circular profile avatar widget.
///
/// Features:
/// - Shows user DP from URL, or initials fallback
/// - Shimmer placeholder while loading
/// - Optional tap to open full-screen viewer
/// - Configurable size
class ProfileAvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  const ProfileAvatarWidget({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 40,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final avatarColor = Color(ProfileDPService.getAvatarColor(name));
    final initials = ProfileDPService.getInitials(name);
    final avatarWidget = GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: avatarColor.withOpacity(0.15),
          border: showBorder
              ? Border.all(
                  color: borderColor ?? avatarColor.withOpacity(0.5),
                  width: borderWidth,
                )
              : null,
        ),
        child: ClipOval(
          child: hasImage
              ? CachedNetworkImage(
                  imageUrl: imageUrl!,
                  cacheKey: imageUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 250),
                  fadeInCurve: Curves.easeIn,
                  placeholder: (context, url) =>
                      _ShimmerCircle(size: size, color: avatarColor),
                  errorWidget: (context, url, error) => _InitialsAvatar(
                    initials: initials,
                    size: size,
                    color: avatarColor,
                  ),
                )
              : _InitialsAvatar(
                  initials: initials,
                  size: size,
                  color: avatarColor,
                ),
        ),
      ),
    );

    return avatarWidget;
  }
}

/// Large tappable profile avatar for profile pages with edit overlay.
///
/// Shows an edit/camera icon when [showEditOverlay] is true.
class ProfileDPCircle extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final VoidCallback? onTap;
  final bool showEditOverlay;
  final bool isUploading;
  final int uploadProgress;

  /// Optional override for the circle background colour (replaces name-hash colour).
  final Color? circleBackgroundColor;

  /// Optional override for the initials text colour.
  final Color? initialsColor;

  const ProfileDPCircle({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 128,
    this.onTap,
    this.showEditOverlay = false,
    this.isUploading = false,
    this.uploadProgress = 0,
    this.circleBackgroundColor,
    this.initialsColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final avatarColor = Color(ProfileDPService.getAvatarColor(name));
    final initials = ProfileDPService.getInitials(name);
    // Use overrides when provided, otherwise fall back to name-hash colour.
    final bgColor = circleBackgroundColor ?? avatarColor;
    final txtColor = initialsColor ?? avatarColor;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor.withOpacity(
                circleBackgroundColor != null ? 1.0 : 0.15,
              ),
              border: Border.all(
                color: bgColor.withOpacity(
                  circleBackgroundColor != null ? 0.6 : 0.4,
                ),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: isUploading
                  ? _UploadProgressAvatar(
                      progress: uploadProgress,
                      color: avatarColor,
                      size: size,
                    )
                  : hasImage
                  ? CachedNetworkImage(
                      imageUrl: imageUrl!,
                      cacheKey: imageUrl,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 250),
                      fadeInCurve: Curves.easeIn,
                      placeholder: (context, url) =>
                          _ShimmerCircle(size: size, color: avatarColor),
                      errorWidget: (context, url, error) => _InitialsAvatar(
                        initials: initials,
                        size: size,
                        color: bgColor,
                        textColor: txtColor,
                      ),
                    )
                  : _InitialsAvatar(
                      initials: initials,
                      size: size,
                      color: bgColor,
                      textColor: txtColor,
                    ),
            ),
          ),
          // Edit overlay badge
          if (showEditOverlay && !isUploading)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: txtColor,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
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
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final Color color;
  final Color? textColor;

  const _InitialsAvatar({
    required this.initials,
    required this.size,
    required this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: color.withOpacity(0.18),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.33,
          fontWeight: FontWeight.bold,
          color: textColor ?? color,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _ShimmerCircle extends StatefulWidget {
  final double size;
  final Color color;

  const _ShimmerCircle({required this.size, required this.color});

  @override
  State<_ShimmerCircle> createState() => _ShimmerCircleState();
}

class _ShimmerCircleState extends State<_ShimmerCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        width: widget.size,
        height: widget.size,
        color: widget.color.withOpacity(_animation.value),
      ),
    );
  }
}

class _UploadProgressAvatar extends StatelessWidget {
  final int progress;
  final Color color;
  final double size;

  const _UploadProgressAvatar({
    required this.progress,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: color.withOpacity(0.15),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size * 0.4,
            height: size * 0.4,
            child: CircularProgressIndicator(
              value: progress / 100,
              color: color,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$progress%',
            style: TextStyle(
              fontSize: size * 0.12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat sender avatar widget (small, shown next to chat messages)
// ─────────────────────────────────────────────────────────────────────────────

/// Small circular avatar shown next to a chat message.
///
/// - Automatically fetches and caches the sender's profile picture
/// - Tapping opens the full-screen DP viewer
/// - Falls back to initials if no DP is available
class ChatSenderAvatarWidget extends StatefulWidget {
  final String senderId;
  final String senderName;
  final double size;

  const ChatSenderAvatarWidget({
    super.key,
    required this.senderId,
    required this.senderName,
    this.size = 34,
  });

  @override
  State<ChatSenderAvatarWidget> createState() => _ChatSenderAvatarWidgetState();
}

class _ChatSenderAvatarWidgetState extends State<ChatSenderAvatarWidget> {
  String? _dpUrl;
  String? _cacheKey;

  @override
  void initState() {
    super.initState();
    _loadDP();
  }

  @override
  void didUpdateWidget(ChatSenderAvatarWidget old) {
    super.didUpdateWidget(old);
    if (old.senderId != widget.senderId) {
      _dpUrl = null;
      _cacheKey = null;
      _loadDP();
    }
  }

  Future<void> _loadDP() async {
    try {
      final provider = context.read<ProfileDPProvider>();
      // Check cache first (synchronous)
      final cached = provider.getCachedUserDP(widget.senderId);
      if (cached != null || _isAlreadyCached(provider)) {
        if (mounted) {
          setState(() {
            _dpUrl = cached;
            _cacheKey = provider.getUserCacheKey(widget.senderId);
          });
        }
        return;
      }
      // Fetch async
      final url = await provider.getUserDP(widget.senderId);
      if (mounted) {
        setState(() {
          _dpUrl = url;
          _cacheKey = provider.getUserCacheKey(widget.senderId);
        });
      }
    } catch (_) {
      // Leave _dpUrl as null — fallback initials will be shown
    }
  }

  bool _isAlreadyCached(ProfileDPProvider provider) {
    return provider.getCachedUserDP(widget.senderId) != null;
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = Color(
      ProfileDPService.getAvatarColor(widget.senderName),
    );
    final initials = ProfileDPService.getInitials(widget.senderName);
    final size = widget.size;

    return GestureDetector(
      onTap: _dpUrl != null && _dpUrl!.isNotEmpty
          ? () => Navigator.of(context).push(
              FullScreenDPViewer.route(
                imageUrl: _dpUrl!,
                userName: widget.senderName,
              ),
            )
          : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: avatarColor.withOpacity(0.12),
        ),
        child: ClipOval(
          child: _dpUrl != null && _dpUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: _dpUrl!,
                  cacheKey: _cacheKey ?? _dpUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  fadeInCurve: Curves.easeIn,
                  placeholder: (_, _) =>
                      _ShimmerCircle(size: size, color: avatarColor),
                  errorWidget: (_, _, _) =>
                      _buildInitials(initials, avatarColor, size),
                )
              : _buildInitials(initials, avatarColor, size),
        ),
      ),
    );
  }

  Widget _buildInitials(String initials, Color color, double size) {
    return Container(
      color: color.withOpacity(0.15),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
