import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  bool _isLongPressing = false;
  final Map<int, bool> _imageLoadedState = {}; // Track which images are loaded
  bool _isPreloadingImages = true; // Show loading while preloading
  bool _hasPreloadedImages = false; // Track if preloading has been initiated

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
        // Only if PageController is attached and has positions
        if (_pageController.hasClients &&
            _currentIndex < widget.announcements.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else if (_currentIndex >= widget.announcements.length - 1) {
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload images after context is fully available
    if (!_hasPreloadedImages) {
      _hasPreloadedImages = true;
      _preloadImages();
    }
  }

  /// Preload all announcement images to ensure smooth display
  Future<void> _preloadImages() async {
    final imagesToPreload = <Future<void>>[];

    for (int i = 0; i < widget.announcements.length; i++) {
      final announcement = widget.announcements[i];
      final imageUrl = announcement['avatarUrl'] as String?;

      if (imageUrl != null && imageUrl.isNotEmpty) {
        // Precache network image
        imagesToPreload.add(
          precacheImage(CachedNetworkImageProvider(imageUrl), context)
              .then((_) {
                if (mounted) {
                  setState(() {
                    _imageLoadedState[i] = true;
                  });
                }
              })
              .catchError((error) {
                // Mark as loaded even on error so UI doesn't hang
                if (mounted) {
                  setState(() {
                    _imageLoadedState[i] = true;
                  });
                }
              }),
        );
      } else {
        // No image to load
        _imageLoadedState[i] = true;
      }
    }

    // Wait for all images to preload (or at least the first one)
    if (imagesToPreload.isNotEmpty) {
      // Wait for first image at minimum
      await Future.any([
        imagesToPreload.first,
        Future.delayed(const Duration(seconds: 3)), // Timeout after 3s
      ]);
    }

    if (mounted) {
      setState(() {
        _isPreloadingImages = false;
      });
    }
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
    // Show circular loading while preloading images
    if (_isPreloadingImages) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            strokeWidth: 3,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (!_isLongPressing) {
            setState(() {
              _verticalDragOffset += details.delta.dy;
            });
          }
        },
        onVerticalDragEnd: (details) {
          if (!_isLongPressing && _verticalDragOffset > 100) {
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
                    setState(() {
                      _isLongPressing = true;
                    });
                    _progressController.stop();
                  },
                  onLongPressEnd: (_) {
                    // Resume progress when released
                    setState(() {
                      _isLongPressing = false;
                    });
                    _progressController.forward();
                  },
                  onTapUp: (details) {
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
                                        CachedNetworkImage(
                                          imageUrl: announcement['avatarUrl']!,
                                          fit: BoxFit.contain,
                                          placeholder: (context, url) => Container(
                                            color: Colors.black,
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(Colors.white54),
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                                color: Colors.grey.shade900,
                                                child: const Icon(
                                                  Icons.image_not_supported,
                                                  size: 64,
                                                  color: Colors.white54,
                                                ),
                                              ),
                                        )
                                      else if ((announcement['title']
                                                  as String?)
                                              ?.isNotEmpty ??
                                          false)
                                        // Show text only if no image
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
                                        )
                                      else
                                        Container(color: Colors.black),
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
                          top: 60,
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
