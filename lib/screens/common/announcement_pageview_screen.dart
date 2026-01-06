import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/media_repository.dart';

/// Multi-announcement viewer with swipe navigation
/// Supports navigating through multiple announcements left/right
class AnnouncementPageViewScreen extends StatefulWidget {
  final List<Map<String, dynamic>>
  announcements; // List of {role, title, subtitle, postedByLabel, avatarUrl, postedAt, expiresAt, creatorId}
  final int initialIndex;
  final String? currentUserId; // Current user ID for permission checks
  final Function(int)?
  onIndexChanged; // Callback when user swipes to new announcement
  final Function(int)?
  onAnnouncementViewed; // Callback when announcement is viewed
  final Function(int)? onDelete; // Callback to delete announcement by index

  const AnnouncementPageViewScreen({
    super.key,
    required this.announcements,
    this.initialIndex = 0,
    this.currentUserId,
    this.onIndexChanged,
    this.onAnnouncementViewed,
    this.onDelete,
  });

  @override
  State<AnnouncementPageViewScreen> createState() =>
      _AnnouncementPageViewScreenState();
}

class _AnnouncementPageViewScreenState extends State<AnnouncementPageViewScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  late AnimationController _progressController;
  late Animation<double> _progress;
  bool _showTapHints = true;
  double _verticalDragOffset = 0.0;
  final MediaRepository _mediaRepository = MediaRepository();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(
      initialPage: widget.initialIndex,
      viewportFraction: 1,
    );
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progress = CurvedAnimation(
      parent: _progressController,
      curve: Curves.linear,
    );
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Auto-advance to next announcement when progress completes
        if (_currentIndex < widget.announcements.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          // Finished last announcement, close viewer
          if (mounted) Navigator.of(context).maybePop();
        }
      }
    });
    _progressController.forward();

    // Mark as viewed
    widget.onAnnouncementViewed?.call(_currentIndex);

    // Hide tap hints after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showTapHints = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    // Reset progress animation
    _progressController.reset();
    _progressController.forward();
    widget.onIndexChanged?.call(index);
    widget.onAnnouncementViewed?.call(index);
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(dt);
  }

  String _expiryText(DateTime? expiresAt) {
    if (expiresAt == null) return '';
    final now = DateTime.now();
    final diff = expiresAt.difference(now);
    if (diff.isNegative) return 'Expired';
    if (diff.inHours >= 24) {
      final days = (diff.inHours / 24).floor();
      return 'Expires in ${days}d';
    }
    return 'Expires in ${diff.inHours} hrs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragUpdate: (details) {
          setState(() {
            _verticalDragOffset += details.delta.dy;
          });
        },
        onVerticalDragEnd: (details) {
          if (_verticalDragOffset > 100) {
            // Swipe down to dismiss
            Navigator.of(context).maybePop();
          } else {
            setState(() {
              _verticalDragOffset = 0.0;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.translationValues(
            0,
            _verticalDragOffset.clamp(0.0, 200.0),
            0,
          ),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: widget.announcements.length,
            itemBuilder: (context, index) {
              final announcement = widget.announcements[index];
              final role = announcement['role'] as String? ?? 'principal';
              final theme = _RoleTheme.forRole(role);
              final isLight = theme.useLightBackground;
              final bgColor = isLight ? theme.bgLight : theme.bgDark;

              return Scaffold(
                backgroundColor: bgColor,
                body: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPressStart: (_) {
                    // Pause progress when holding
                    _progressController.stop();
                  },
                  onLongPressEnd: (_) {
                    // Resume progress when released
                    _progressController.forward();
                  },
                  onTapDown: (details) {
                    final width = MediaQuery.of(context).size.width;
                    final dx = details.globalPosition.dx;
                    if (dx < width * 0.33) {
                      // Tap left: go to previous
                      if (_currentIndex > 0) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      }
                    } else if (dx > width * 0.67) {
                      // Tap right: go to next
                      if (_currentIndex < widget.announcements.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      } else {
                        // Last item: close
                        Navigator.of(context).maybePop();
                      }
                    }
                  },
                  child: Stack(
                    children: [
                      // Black background
                      Positioned.fill(child: Container(color: Colors.black)),

                      // Content
                      SafeArea(
                        child: Column(
                          children: [
                            // Header with progress bars
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                12,
                              ),
                              child: Column(
                                children: [
                                  // Progress bars for announcements
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      children: List.generate(
                                        widget.announcements.length,
                                        (i) => Expanded(
                                          child: Container(
                                            height: 3,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                i == _currentIndex ? 0.8 : 0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(9999),
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: i == _currentIndex
                                                ? AnimatedBuilder(
                                                    animation: _progress,
                                                    builder: (context, _) {
                                                      return Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child:
                                                            FractionallySizedBox(
                                                              widthFactor:
                                                                  _progress
                                                                      .value,
                                                              child: Container(
                                                                color: theme
                                                                    .primary,
                                                              ),
                                                            ),
                                                      );
                                                    },
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Avatar + metadata row
                                  Row(
                                    children: [
                                      Container(
                                        height: 40,
                                        width: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: theme.primary.withOpacity(
                                              0.5,
                                            ),
                                            width: 2,
                                          ),
                                          image:
                                              announcement['avatarUrl'] != null
                                              ? DecorationImage(
                                                  image: NetworkImage(
                                                    announcement['avatarUrl']!,
                                                  ),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                          color:
                                              announcement['avatarUrl'] == null
                                              ? Colors.grey.shade400
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              announcement['postedByLabel'] ??
                                                  '',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.8,
                                                ),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _relativeTime(
                                                announcement['postedAt']
                                                    as DateTime?,
                                              ),
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.6,
                                                ),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Center content
                            Expanded(
                              child: Container(
                                color: Colors.black,
                                child: Center(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // Background image (if available)
                                      if (announcement['avatarUrl'] != null &&
                                          (announcement['avatarUrl'] as String)
                                              .isNotEmpty)
                                        _buildCachedImage(
                                          announcement['avatarUrl']!,
                                          'announcement_${announcement['id'] ?? _currentIndex}.jpg',
                                        )
                                      else
                                        Container(color: Colors.black),

                                      // Text overlay (centered if no image, at bottom if image)
                                      if ((announcement['title'] as String?)
                                              ?.isNotEmpty ??
                                          false)
                                        if (announcement['avatarUrl'] != null &&
                                            (announcement['avatarUrl']
                                                    as String)
                                                .isNotEmpty)
                                          // Text at bottom if image exists
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withOpacity(
                                                      0.3,
                                                    ),
                                                    Colors.black.withOpacity(
                                                      0.7,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    24,
                                                    80,
                                                    24,
                                                    24,
                                                  ),
                                              child: Text(
                                                announcement['title'] ?? '',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          // Text centered if no image
                                          Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(32),
                                              child: Text(
                                                announcement['title'] ?? '',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 32,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Footer with expiry and counter
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                24,
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(9999),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.08),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.schedule,
                                          size: 16,
                                          color: Colors.white70,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _expiryText(
                                            announcement['expiresAt']
                                                as DateTime?,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.announcements.length > 1) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      '${_currentIndex + 1} / ${widget.announcements.length}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tap zone (invisible, for navigation only)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: true,
                          child: Container(),
                        ),
                      ),

                      // Swipe down hint at top
                      if (_showTapHints)
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _showTapHints ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 500),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.keyboard_arrow_down,
                                        color: Colors.white70,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Swipe down to close',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Delete button at top right (only for creator)
                      if (widget.currentUserId != null &&
                          widget.currentUserId!.isNotEmpty &&
                          announcement['creatorId'] != null &&
                          (announcement['creatorId'] as String).isNotEmpty &&
                          announcement['creatorId'] == widget.currentUserId)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: SafeArea(
                            child: Material(
                              color: Colors.transparent,
                              child: GestureDetector(
                                onTap: () {
                                  if (widget.onDelete != null) {
                                    widget.onDelete!(_currentIndex);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.8),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Build cached image widget - downloads and caches on first view
  Widget _buildCachedImage(String imageUrl, String fileName) {
    return FutureBuilder<String?>(
      future: _getImagePath(imageUrl, fileName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show loading while checking cache/downloading
          return Container(
            color: Colors.grey.shade900,
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          // Show error if download failed
          return Container(
            color: Colors.grey.shade900,
            child: const Icon(
              Icons.image_not_supported,
              size: 64,
              color: Colors.white54,
            ),
          );
        }

        // Show cached image
        return Image.file(
          File(snapshot.data!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade900,
              child: const Icon(
                Icons.image_not_supported,
                size: 64,
                color: Colors.white54,
              ),
            );
          },
        );
      },
    );
  }

  /// Get image path - from cache or download if needed
  Future<String?> _getImagePath(String imageUrl, String fileName) async {
    try {
      // Extract R2 key from URL (if it's a Cloudflare R2 URL)
      String r2Key;
      if (imageUrl.contains('files.lenv1.tech')) {
        final uri = Uri.parse(imageUrl);
        r2Key = uri.path.substring(1); // Remove leading /
      } else {
        // For other URLs, use a hash or simple key
        r2Key = 'announcements/${imageUrl.hashCode}_$fileName';
      }

      // Check if already cached
      final localPath = await _mediaRepository.getLocalFilePath(r2Key);
      if (localPath != null) {
        debugPrint('✅ Announcement image cached: $fileName');
        return localPath;
      }

      // Download and cache
      debugPrint('📥 Downloading announcement image: $fileName');
      final result = await _mediaRepository.downloadMedia(
        r2Key: r2Key,
        fileName: fileName,
        mimeType: 'image/jpeg',
      );

      if (result.success && result.localPath != null) {
        debugPrint('✅ Announcement image downloaded and cached: $fileName');
        return result.localPath;
      }

      debugPrint('❌ Failed to download announcement image: ${result.message}');
      return null;
    } catch (e) {
      debugPrint('❌ Error loading announcement image: $e');
      return null;
    }
  }
}

class _RoleTheme {
  final Color primary;
  final Color bgLight;
  final Color bgDark;
  final bool useLightBackground;

  const _RoleTheme({
    required this.primary,
    required this.bgLight,
    required this.bgDark,
    required this.useLightBackground,
  });

  static _RoleTheme forRole(String role) {
    final r = role.toLowerCase();
    switch (r) {
      case 'teacher':
        return const _RoleTheme(
          primary: Color(0xFF7E57C2),
          bgLight: Color(0xFFF3E5F5),
          bgDark: Color(0xFF120F23),
          useLightBackground: true,
        );
      case 'principal':
      case 'institute':
        return const _RoleTheme(
          primary: Color(0xFF1976D2),
          bgLight: Color(0xFFE3F2FD),
          bgDark: Color(0xFF101214),
          useLightBackground: true,
        );
      case 'parent':
        return const _RoleTheme(
          primary: Color(0xFF009688),
          bgLight: Color(0xFFE0F2F1),
          bgDark: Color(0xFF151022),
          useLightBackground: true,
        );
      case 'student':
      default:
        return const _RoleTheme(
          primary: Color(0xFFF27F0D),
          bgLight: Color(0xFFFFF5EB),
          bgDark: Color(0xFF221910),
          useLightBackground: false,
        );
    }
  }
}

/// Helper to open multi-announcement viewer
Future<void> openAnnouncementPageView(
  BuildContext context, {
  required List<Map<String, dynamic>> announcements,
  int initialIndex = 0,
  String? currentUserId,
  Function(int)? onIndexChanged,
  Function(int)? onAnnouncementViewed,
  Function(int)? onDelete,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AnnouncementPageViewScreen(
        announcements: announcements,
        initialIndex: initialIndex,
        currentUserId: currentUserId,
        onIndexChanged: onIndexChanged,
        onAnnouncementViewed: onAnnouncementViewed,
        onDelete: onDelete,
      ),
    ),
  );
}
