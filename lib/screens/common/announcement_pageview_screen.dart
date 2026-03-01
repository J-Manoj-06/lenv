import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  // Track current image index within each announcement (for multi-image support)
  final Map<int, int> _announcementImageIndex = {};

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

      // Check for multi-image announcements
      final imageCaptions =
          announcement['imageCaptions'] as List<Map<String, String>>?;

      if (imageCaptions != null && imageCaptions.isNotEmpty) {
        // Preload all images in multi-image announcement
        for (final imageData in imageCaptions) {
          final imageUrl = imageData['url'];
          if (imageUrl != null && imageUrl.isNotEmpty) {
            imagesToPreload.add(
              precacheImage(
                CachedNetworkImageProvider(imageUrl),
                context,
              ).catchError((error) {
                // Ignore errors to prevent hanging
              }),
            );
          }
        }
        _imageLoadedState[i] = true;
      } else {
        // Legacy single image
        final imageUrl = announcement['avatarUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
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
                  if (mounted) {
                    setState(() {
                      _imageLoadedState[i] = true;
                    });
                  }
                }),
          );
        } else {
          // No image - mark as loaded immediately
          _imageLoadedState[i] = true;
        }
      }
    }

    // Always wait with a timeout to ensure we don't get stuck on loading
    try {
      if (imagesToPreload.isNotEmpty) {
        await Future.any([
          Future.wait(imagesToPreload),
          Future.delayed(const Duration(seconds: 2)),
        ]);
      } else {
        // No images to preload, but still add a small delay for UI stability
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      // Ignore any errors
    }

    // Always set preloading to false
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

  /// Build progress bars - shows segments for images in multi-image announcements
  Widget _buildProgressBars(
    Map<String, dynamic> announcement,
    _RoleTheme theme,
  ) {
    final imageCaptions =
        announcement['imageCaptions'] as List<Map<String, String>>?;

    // If announcement has multiple images, show progress for each image
    if (imageCaptions != null && imageCaptions.isNotEmpty) {
      final currentImageIndex = _announcementImageIndex[_currentIndex] ?? 0;

      return Row(
        children: List.generate(
          imageCaptions.length,
          (i) => Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(
                  i < currentImageIndex
                      ? 1.0
                      : // Completed images: fully visible
                        i == currentImageIndex
                      ? 0.8
                      : // Current image: slightly visible
                        0.2, // Future images: barely visible
                ),
                borderRadius: BorderRadius.circular(9999),
              ),
              clipBehavior: Clip.antiAlias,
              child: i == currentImageIndex
                  ? AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _progress.value,
                            child: Container(color: theme.primary),
                          ),
                        );
                      },
                    )
                  : i < currentImageIndex
                  ? Container(color: theme.primary) // Completed: filled
                  : null, // Future: empty
            ),
          ),
        ),
      );
    }

    // Otherwise show progress for announcements (default behavior)
    return Row(
      children: List.generate(
        widget.announcements.length,
        (i) => Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(i == _currentIndex ? 0.8 : 0.2),
              borderRadius: BorderRadius.circular(9999),
            ),
            clipBehavior: Clip.antiAlias,
            child: i == _currentIndex
                ? AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _progress.value,
                          child: Container(color: theme.primary),
                        ),
                      );
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// Build announcement content with multi-image support
  Widget _buildAnnouncementContent(
    Map<String, dynamic> announcement,
    int announcementIndex,
  ) {
    final imageCaptions =
        announcement['imageCaptions'] as List<Map<String, String>>?;

    // Check if we have multiple images
    if (imageCaptions != null && imageCaptions.isNotEmpty) {
      // Initialize image index for this announcement if not set
      _announcementImageIndex.putIfAbsent(announcementIndex, () => 0);
      final currentImageIndex = _announcementImageIndex[announcementIndex]!;

      // Get current image data
      final imageData = imageCaptions[currentImageIndex];
      final imageUrl = imageData['url'] ?? '';
      final caption = imageData['caption'] ?? '';

      return Stack(
        fit: StackFit.expand,
        children: [
          // Display current image with tap navigation
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final width = MediaQuery.of(context).size.width;
              final dx = details.globalPosition.dx;

              if (dx < width * 0.33 && currentImageIndex > 0) {
                // Tap left third: Previous image
                setState(() {
                  _announcementImageIndex[announcementIndex] =
                      currentImageIndex - 1;
                });
                // Restart progress for new image
                _progressController.reset();
                _progressController.forward();
              } else if (dx > width * 0.67 &&
                  currentImageIndex < imageCaptions.length - 1) {
                // Tap right third: Next image
                setState(() {
                  _announcementImageIndex[announcementIndex] =
                      currentImageIndex + 1;
                });
                // Restart progress for new image
                _progressController.reset();
                _progressController.forward();
              }
            },
            child: imageUrl.isEmpty
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image
                      CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        fadeInDuration: const Duration(milliseconds: 200),
                        fadeOutDuration: const Duration(milliseconds: 200),
                        placeholder: (context, url) => Container(
                          color: Colors.black,
                          child: const Center(
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white54,
                                ),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade900,
                          child: const Icon(
                            Icons.image_not_supported,
                            size: 64,
                            color: Colors.white54,
                          ),
                        ),
                        // Cache configuration
                        memCacheHeight: 1080,
                        memCacheWidth: 1920,
                        maxHeightDiskCache: 1080,
                        maxWidthDiskCache: 1920,
                      ),

                      // Caption overlay at bottom (if caption exists)
                      if (caption.isNotEmpty)
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
                                  Colors.black.withOpacity(0.3),
                                  Colors.black.withOpacity(0.7),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                            child: Text(
                              caption,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // Counter badge showing current image position
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swipe, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${currentImageIndex + 1}/${imageCaptions.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Left arrow hint (if not on first image)
          if (currentImageIndex > 0)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          // Right arrow hint (if not on last image)
          if (currentImageIndex < imageCaptions.length - 1)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // Fallback to legacy single image
    if (announcement['avatarUrl'] != null &&
        (announcement['avatarUrl'] as String).isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: announcement['avatarUrl']!,
        fit: BoxFit.contain,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => Container(
          color: Colors.black,
          child: const Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                strokeWidth: 2,
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey.shade900,
          child: const Icon(
            Icons.image_not_supported,
            size: 64,
            color: Colors.white54,
          ),
        ),
        // Cache configuration
        memCacheHeight: 1080,
        memCacheWidth: 1920,
        maxHeightDiskCache: 1080,
        maxWidthDiskCache: 1920,
      );
    }

    // Show text only if no images
    if ((announcement['title'] as String?)?.isNotEmpty ?? false) {
      final title = announcement['title'] as String;

      return _ExpandablePostText(
        text: title,
        textColor: Colors.white,
        accentColor: const Color(0xFF355872),
      );
    }

    // Empty announcement
    return Container(color: Colors.black);
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
            physics:
                const NeverScrollableScrollPhysics(), // Disable swipe - use tap navigation only
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
                                  // Progress bars for announcements or images
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildProgressBars(
                                      announcement,
                                      theme,
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
                                              announcement['avatarUrl'] !=
                                                      null &&
                                                  announcement['avatarUrl']!
                                                      .isNotEmpty
                                              ? DecorationImage(
                                                  image: NetworkImage(
                                                    announcement['avatarUrl']!,
                                                  ),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                          color:
                                              announcement['avatarUrl'] ==
                                                      null ||
                                                  announcement['avatarUrl']!
                                                      .isEmpty
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
                                  child: _buildAnnouncementContent(
                                    announcement,
                                    index,
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

/// Adaptive expandable post text widget that fills available space
class _ExpandablePostText extends StatefulWidget {
  final String text;
  final Color textColor;
  final Color accentColor;

  const _ExpandablePostText({
    required this.text,
    required this.textColor,
    required this.accentColor,
  });

  @override
  State<_ExpandablePostText> createState() => _ExpandablePostTextState();
}

class _ExpandablePostTextState extends State<_ExpandablePostText> {
  bool _needsReadMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfNeedsReadMore();
    });
  }

  void _checkIfNeedsReadMore() {
    final availableHeight = MediaQuery.of(context).size.height - 200;
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: const TextStyle(fontSize: 18, height: 1.6),
      ),
      textDirection: ui.TextDirection.ltr,
    );

    textPainter.layout(maxWidth: MediaQuery.of(context).size.width - 48);

    if (mounted) {
      setState(() {
        _needsReadMore = textPainter.height > availableHeight;
      });
    }
  }

  void _showExpandedContent() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.95,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 24),
                  const Text(
                    'Full Announcement',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      fontSize: 24,
                      color: widget.textColor,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          color: Colors.black,
          child: _needsReadMore
              ? // Long text: scrollable with Read More button
                Column(
                  children: [
                    // Text content - scrollable
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            widget.text,
                            style: TextStyle(
                              fontSize: 24,
                              color: widget.textColor,
                              height: 1.6,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ),
                    ),
                    // Read More button
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 32,
                        left: 24,
                        right: 24,
                        top: 16,
                      ),
                      child: GestureDetector(
                        onTap: _showExpandedContent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: widget.accentColor,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Read More',
                            style: TextStyle(
                              fontSize: 16,
                              color: widget.accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : // Short text: centered nicely
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Text(
                      widget.text,
                      style: TextStyle(
                        fontSize: 24,
                        color: widget.textColor,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Old widget - keeping for compatibility
class _ExpandableAnnouncementText extends StatefulWidget {
  final String text;
  final Color textColor;
  final Color accentColor;
  final int maxCollapsedLines;

  const _ExpandableAnnouncementText({
    required this.text,
    required this.textColor,
    required this.accentColor,
    this.maxCollapsedLines =3,
  });

  @override
  State<_ExpandableAnnouncementText> createState() =>
      _ExpandableAnnouncementTextState();
}

class _ExpandableAnnouncementTextState
    extends State<_ExpandableAnnouncementText> {
  bool _isExpanded = false;
  bool _needsReadMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfNeedsReadMore();
    });
  }

  void _checkIfNeedsReadMore() {
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: const TextStyle(fontSize: 20, height: 1.5),
      ),
      maxLines: widget.maxCollapsedLines,
      textDirection: ui.TextDirection.ltr,
    );

    textPainter.layout(maxWidth: MediaQuery.of(context).size.width - 48);

    if (mounted) {
      setState(() {
        _needsReadMore = textPainter.didExceedMaxLines;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpanded) {
      // Expanded view: scrollable full content with Read Less button
      return SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: 20,
                  color: widget.textColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_needsReadMore)
              Padding(
                padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  child: Text(
                    'Read Less',
                    style: TextStyle(
                      fontSize: 18,
                      color: widget.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      // Collapsed view: centered content with ellipsis + Read More button at bottom
      return Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      fontSize: 20,
                      color: widget.textColor,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: widget.maxCollapsedLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          if (_needsReadMore)
            Padding(
              padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Text(
                  'Read More',
                  style: TextStyle(
                    fontSize: 18,
                    color: widget.accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      );
    }
  }
}
