import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/media_availability_service.dart';
import '../services/background_download_service.dart';
import '../core/constants/app_colors.dart';

/// WhatsApp-style multi-image message bubble with centralized download.
/// Features:
/// - Centralized download button for all images
/// - Blur background for non-cached images
/// - In-place downloading (stays on chat page)
/// - Shows download progress overlay
/// - Only allows viewing after download completes
/// - Role-specific border colors for image grid
class MultiImageMessageBubble extends StatefulWidget {
  final List<String> imageUrls;
  final bool isMe;
  final void Function(int index, Map<int, String> cachedPaths) onImageTap;
  final List<double?>?
  uploadProgress; // Upload progress for each image (0.0-1.0)

  final double bubbleRadius;
  final double tileRadius;
  final double gap;
  final double maxScrollableHeight; // for >4 images
  final String? userRole; // User role to determine border color

  const MultiImageMessageBubble({
    super.key,
    required this.imageUrls,
    required this.isMe,
    required this.onImageTap,
    this.uploadProgress,
    this.bubbleRadius = 4,
    this.tileRadius = 0,
    this.gap = 1,
    this.maxScrollableHeight = 240,
    this.userRole,
  });

  @override
  State<MultiImageMessageBubble> createState() =>
      _MultiImageMessageBubbleState();
}

class _MultiImageMessageBubbleState extends State<MultiImageMessageBubble> {
  final MediaAvailabilityService _availabilityService =
      MediaAvailabilityService();
  final BackgroundDownloadService _downloadService =
      BackgroundDownloadService();

  // Track which images are cached
  final Map<int, bool> _cachedStatus = {};
  final Map<int, String> _cachedPaths = {};

  // Download state
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _downloadedCount = 0;
  int _totalToDownload = 0;

  bool _allCached = false;

  /// Get border color based on user role
  Color _getBorderColor() {
    switch (widget.userRole?.toLowerCase()) {
      case 'teacher':
        return AppColors.teacherColor;
      case 'student':
        return AppColors.studentColor;
      case 'parent':
        return AppColors.parentColor;
      case 'principal':
      case 'institute':
        return AppColors.instituteColor;
      default:
        return const Color(0xFF9E9E9E); // Grey fallback
    }
  }

  @override
  void initState() {
    super.initState();
    _checkAllCacheStatus();
  }

  /// Check cache status for all images
  Future<void> _checkAllCacheStatus() async {
    bool allCached = true;

    for (int i = 0; i < widget.imageUrls.length; i++) {
      final url = widget.imageUrls[i];

      // Skip local file paths (already available)
      if (url.startsWith('/')) {
        final file = File(url);
        if (await file.exists()) {
          _cachedStatus[i] = true;
          _cachedPaths[i] = url;
          continue;
        }
      }

      // Extract r2Key from URL
      String r2Key = url;
      if (r2Key.startsWith('http')) {
        final uri = Uri.parse(r2Key);
        r2Key = uri.path.replaceFirst('/', '');
      }

      // Check availability
      final availability = await _availabilityService.checkMediaAvailability(
        r2Key,
      );

      if (availability.isCached) {
        final path = await _availabilityService.getCachedFilePath(r2Key);
        if (path != null) {
          _cachedStatus[i] = true;
          _cachedPaths[i] = path;
        } else {
          _cachedStatus[i] = false;
          allCached = false;
        }
      } else {
        _cachedStatus[i] = false;
        allCached = false;
      }
    }

    if (mounted) {
      setState(() {
        _allCached = allCached;
      });
    }
  }

  /// Download all non-cached images
  Future<void> _downloadAllImages() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadedCount = 0;
    });

    // Count how many need downloading
    final toDownload = <int>[];
    for (int i = 0; i < widget.imageUrls.length; i++) {
      if (_cachedStatus[i] != true) {
        toDownload.add(i);
      }
    }

    _totalToDownload = toDownload.length;

    if (_totalToDownload == 0) {
      setState(() {
        _isDownloading = false;
        _allCached = true;
      });
      return;
    }

    // Use background download service with notifications
    final results = await _downloadService.downloadMultipleImages(
      urls: widget.imageUrls,
      onProgress: (downloaded, total, progress) {
        if (mounted) {
          setState(() {
            _downloadedCount = downloaded;
            _totalToDownload = total;
            _downloadProgress = progress;
          });
        }
      },
    );

    // Update cached paths with results
    results.forEach((index, path) {
      _cachedPaths[index] = path;
      _cachedStatus[index] = true;
    });

    // Re-check cache status
    await _checkAllCacheStatus();

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.7; // 70% of screen

    // Check if any image is still uploading
    bool isUploading = false;
    double overallProgress = 0.0;

    if (widget.uploadProgress != null && widget.uploadProgress!.isNotEmpty) {
      final activeUploads = widget.uploadProgress!
          .where((p) => p != null && p < 1.0)
          .toList();
      if (activeUploads.isNotEmpty) {
        isUploading = true;
        final progressValues = widget.uploadProgress!
            .where((p) => p != null)
            .cast<double>()
            .toList();
        if (progressValues.isNotEmpty) {
          overallProgress =
              progressValues.reduce((a, b) => a + b) / progressValues.length;
        }
      }
    }

    final content = _buildContent(context);

    final bubbleContent = Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.bubbleRadius),
      ),
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.bubbleRadius),
            child: content,
          ),

          // Upload overlay
          if (isUploading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.bubbleRadius),
                child: Container(
                  color: Colors.black.withOpacity(0.65),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 70,
                          height: 70,
                          child: CircularProgressIndicator(
                            value: overallProgress.clamp(0.0, 1.0),
                            strokeWidth: 5,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFFFA929),
                            ),
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${(overallProgress * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Download overlay (minimal blur to preserve border visibility)
          if (!_allCached && !isUploading && !_isDownloading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.bubbleRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                  child: Container(color: Colors.black.withOpacity(0.25)),
                ),
              ),
            ),

          // Download button (on top of blur)
          if (!_allCached && !isUploading && !_isDownloading)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _downloadAllImages,
                            customBorder: const CircleBorder(),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Icon(
                                Icons.cloud_download,
                                size: 40,
                                color: theme.primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Tap to download',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Downloading progress overlay
          if (_isDownloading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.bubbleRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withOpacity(0.4),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: CircularProgressIndicator(
                              value: _downloadProgress,
                              strokeWidth: 6,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Downloading $_downloadedCount/$_totalToDownload',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(_downloadProgress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: bubbleContent,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final count = widget.imageUrls.length;
    final screenWidth = MediaQuery.of(context).size.width;

    // Single image - display with same width as multi-image grid
    if (count == 1) {
      final tileSize = (screenWidth * 0.7 - widget.gap) / 2;
      final gridSize = (tileSize * 2) + widget.gap;
      return SizedBox(
        width: gridSize,
        height: gridSize,
        child: _ImageTile(
          url: widget.imageUrls[0],
          index: 0,
          radius: widget.tileRadius,
          onTap: _allCached
              ? (index) => widget.onImageTap(index, _cachedPaths)
              : (_) {}, // Disable if not cached
          uploadProgress: widget.uploadProgress?[0],
          fit: BoxFit.cover,
          isCached: _cachedStatus[0] ?? false,
          cachedPath: _cachedPaths[0],
          showBlur: !_allCached,
          borderColor: _getBorderColor(),
        ),
      );
    }

    // Two images: side by side
    if (count == 2) {
      return IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: _ImageTile(
                  url: widget.imageUrls[0],
                  index: 0,
                  radius: widget.tileRadius,
                  onTap: _allCached
                      ? (index) => widget.onImageTap(index, _cachedPaths)
                      : (_) {},
                  uploadProgress: widget.uploadProgress?[0],
                  isCached: _cachedStatus[0] ?? false,
                  cachedPath: _cachedPaths[0],
                  showBlur: !_allCached,
                  borderColor: _getBorderColor(),
                  margin: EdgeInsets.only(right: widget.gap / 2),
                ),
              ),
            ),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: _ImageTile(
                  url: widget.imageUrls[1],
                  index: 1,
                  radius: widget.tileRadius,
                  onTap: _allCached
                      ? (index) => widget.onImageTap(index, _cachedPaths)
                      : (_) {},
                  uploadProgress: widget.uploadProgress?[1],
                  isCached: _cachedStatus[1] ?? false,
                  cachedPath: _cachedPaths[1],
                  showBlur: !_allCached,
                  borderColor: _getBorderColor(),
                  margin: EdgeInsets.only(left: widget.gap / 2),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Special case for 3 items
    if (count == 3) {
      return _ThreeImageLayout(
        imageUrls: widget.imageUrls,
        gap: widget.gap,
        tileRadius: widget.tileRadius,
        onTap: _allCached
            ? (index) => widget.onImageTap(index, _cachedPaths)
            : (_) {},
        uploadProgress: widget.uploadProgress,
        cachedStatus: _cachedStatus,
        cachedPaths: _cachedPaths,
        showBlur: !_allCached,
        borderColor: _getBorderColor(),
      );
    }

    // Four images: 2x2 grid
    if (count == 4) {
      return IntrinsicHeight(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _ImageTile(
                        url: widget.imageUrls[0],
                        index: 0,
                        radius: widget.tileRadius,
                        onTap: _allCached
                            ? (index) => widget.onImageTap(index, _cachedPaths)
                            : (_) {},
                        uploadProgress: widget.uploadProgress?[0],
                        isCached: _cachedStatus[0] ?? false,
                        cachedPath: _cachedPaths[0],
                        showBlur: !_allCached,
                        borderColor: _getBorderColor(),
                        margin: EdgeInsets.only(
                          right: widget.gap / 2,
                          bottom: widget.gap / 2,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _ImageTile(
                        url: widget.imageUrls[1],
                        index: 1,
                        radius: widget.tileRadius,
                        onTap: _allCached
                            ? (index) => widget.onImageTap(index, _cachedPaths)
                            : (_) {},
                        uploadProgress: widget.uploadProgress?[1],
                        isCached: _cachedStatus[1] ?? false,
                        cachedPath: _cachedPaths[1],
                        showBlur: !_allCached,
                        borderColor: _getBorderColor(),
                        margin: EdgeInsets.only(
                          left: widget.gap / 2,
                          bottom: widget.gap / 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _ImageTile(
                        url: widget.imageUrls[2],
                        index: 2,
                        radius: widget.tileRadius,
                        onTap: _allCached
                            ? (index) => widget.onImageTap(index, _cachedPaths)
                            : (_) {},
                        uploadProgress: widget.uploadProgress?[2],
                        isCached: _cachedStatus[2] ?? false,
                        cachedPath: _cachedPaths[2],
                        showBlur: !_allCached,
                        borderColor: _getBorderColor(),
                        margin: EdgeInsets.only(
                          right: widget.gap / 2,
                          top: widget.gap / 2,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _ImageTile(
                        url: widget.imageUrls[3],
                        index: 3,
                        radius: widget.tileRadius,
                        onTap: _allCached
                            ? (index) => widget.onImageTap(index, _cachedPaths)
                            : (_) {},
                        uploadProgress: widget.uploadProgress?[3],
                        isCached: _cachedStatus[3] ?? false,
                        cachedPath: _cachedPaths[3],
                        showBlur: !_allCached,
                        borderColor: _getBorderColor(),
                        margin: EdgeInsets.only(
                          left: widget.gap / 2,
                          top: widget.gap / 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 5+ images: grid (limited to 4 visible, rest shown via overlay)
    final tileSize = (screenWidth * 0.7 - (widget.gap * 3)) / 2;
    final gridWidth = (tileSize * 2) + widget.gap;

    // Calculate rows needed (show max 4 images: 2x2 grid)
    final displayCount = count > 4 ? 4 : count;
    final rows = (displayCount / 2).ceil();
    final gridHeight = (tileSize * rows) + (widget.gap * (rows - 1));

    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: widget.gap,
        mainAxisSpacing: widget.gap,
        childAspectRatio: 1,
      ),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        final url = widget.imageUrls[index];
        final showOverlay = (index == 3) && (count > 4);
        final overlayCount = showOverlay ? (count - 4) : 0;

        return _ImageTile(
          url: url,
          index: index,
          radius: widget.tileRadius,
          onTap: _allCached
              ? (index) => widget.onImageTap(index, _cachedPaths)
              : (_) {},
          showOverlay: showOverlay,
          overlayCount: overlayCount,
          uploadProgress:
              widget.uploadProgress != null &&
                  index < widget.uploadProgress!.length
              ? widget.uploadProgress![index]
              : null,
          isCached: _cachedStatus[index] ?? false,
          cachedPath: _cachedPaths[index],
          showBlur: !_allCached,
          borderColor: _getBorderColor(),
        );
      },
    );

    return SizedBox(width: gridWidth, height: gridHeight, child: grid);
  }
}

class _ThreeImageLayout extends StatelessWidget {
  final List<String> imageUrls;
  final double gap;
  final double tileRadius;
  final void Function(int) onTap;
  final List<double?>? uploadProgress;
  final Map<int, bool> cachedStatus;
  final Map<int, String> cachedPaths;
  final bool showBlur;
  final Color borderColor;

  const _ThreeImageLayout({
    required this.imageUrls,
    required this.gap,
    required this.tileRadius,
    required this.onTap,
    required this.borderColor,
    this.uploadProgress,
    required this.cachedStatus,
    required this.cachedPaths,
    required this.showBlur,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _ImageTile(
                      url: imageUrls[0],
                      index: 0,
                      radius: tileRadius,
                      onTap: onTap,
                      uploadProgress: uploadProgress?[0],
                      isCached: cachedStatus[0] ?? false,
                      cachedPath: cachedPaths[0],
                      showBlur: showBlur,
                      borderColor: borderColor,
                      margin: EdgeInsets.only(right: gap / 2, bottom: gap / 2),
                    ),
                  ),
                ),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _ImageTile(
                      url: imageUrls[1],
                      index: 1,
                      radius: tileRadius,
                      onTap: onTap,
                      uploadProgress: uploadProgress?[1],
                      isCached: cachedStatus[1] ?? false,
                      cachedPath: cachedPaths[1],
                      showBlur: showBlur,
                      borderColor: borderColor,
                      margin: EdgeInsets.only(left: gap / 2, bottom: gap / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _ImageTile(
              url: imageUrls[2],
              index: 2,
              radius: tileRadius,
              onTap: onTap,
              uploadProgress: uploadProgress?[2],
              isCached: cachedStatus[2] ?? false,
              cachedPath: cachedPaths[2],
              showBlur: showBlur,
              borderColor: borderColor,
              margin: EdgeInsets.only(top: gap / 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageTile extends StatefulWidget {
  final String url;
  final int index;
  final double radius;
  final void Function(int) onTap;
  final bool showOverlay;
  final int overlayCount;
  final double? uploadProgress;
  final BoxFit? fit;
  final bool isCached;
  final String? cachedPath;
  final bool showBlur;
  final Color borderColor; // Border color based on user role
  final EdgeInsets? margin; // Margin for spacing in grids

  const _ImageTile({
    required this.url,
    required this.index,
    required this.radius,
    required this.onTap,
    required this.borderColor,
    this.showOverlay = false,
    this.overlayCount = 0,
    this.uploadProgress,
    this.fit,
    this.isCached = false,
    this.cachedPath,
    this.showBlur = false,
    this.margin,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile>
    with AutomaticKeepAliveClientMixin {
  bool _loaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Must call super for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: widget.borderColor, width: 3.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: GestureDetector(
          onTap: () => widget.onTap(widget.index),
          child: Stack(
            fit: widget.fit == BoxFit.contain
                ? StackFit.passthrough
                : StackFit.expand,
            children: [
              // Skeleton placeholder
              AnimatedOpacity(
                opacity: _loaded ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),

              // Image (network or file)
              _buildImage(widget.url),

              // "+N" overlay on 4th tile when total > 4
              // (Individual progress overlays removed - use unified overlay at bubble level)
              if (widget.showOverlay)
                Container(
                  color: Colors.black.withOpacity(0.55),
                  child: Center(
                    child: Text(
                      '+${widget.overlayCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String url) {
    // Handle empty URLs (pending uploads)
    if (url.isEmpty) {
      if (widget.uploadProgress != null && widget.uploadProgress! < 1.0) {
        return _loadingSkeleton();
      } else {
        return _errorFallback();
      }
    }

    if (url.startsWith('/')) {
      // Local file path (from pending message)
      final file = File(url);
      if (file.existsSync()) {
        _markLoadedAsync();
        return RepaintBoundary(
          child: Image.file(
            file,
            fit: widget.fit ?? BoxFit.cover,
            filterQuality: FilterQuality.high,
            cacheWidth: 800, // Cache optimization
            errorBuilder: (_, __, ___) => _errorFallback(),
          ),
        );
      } else {
        // File not found - if uploading, show loading skeleton, else show download prompt
        if (widget.uploadProgress != null && widget.uploadProgress! < 1.0) {
          // Currently uploading, show skeleton (upload overlay will appear on top)
          return _loadingSkeleton();
        } else {
          // Not uploading and file missing, show download prompt
          return _downloadPromptFallback();
        }
      }
    }

    // Check if image is cached locally first
    // ✅ If cached locally, load from file
    // ⚪ If NOT cached, show download button without auto-downloading
    if (widget.isCached && widget.cachedPath != null) {
      final file = File(widget.cachedPath!);
      if (file.existsSync()) {
        debugPrint('✅ Loading image from local cache: ${widget.cachedPath}');
        _markLoadedAsync();
        Widget imageWidget = RepaintBoundary(
          child: Image.file(
            file,
            fit: widget.fit ?? BoxFit.cover,
            filterQuality: FilterQuality.high,
            cacheWidth: 800,
            errorBuilder: (_, __, ___) => _errorFallback(),
          ),
        );

        // Apply blur if needed (during download of other images)
        if (widget.showBlur) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                imageWidget,
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.black.withOpacity(0.3)),
                ),
              ],
            ),
          );
        }

        return imageWidget;
      }
    }

    // NOT cached locally - show download prompt WITHOUT attempting network load
    if (!widget.isCached) {
      debugPrint('⚪ Image NOT in local cache, showing download button: $url');
      return _downloadPromptFallback();
    }

    // Fallback: attempt network loading (should not reach here in normal flow)
    debugPrint('🔄 Falling back to network image: $url');
    return RepaintBoundary(
      child: CachedNetworkImage(
        imageUrl: url,
        key: ValueKey(url), // Add key for widget identity
        cacheKey: url, // Explicit cache key
        fit: widget.fit ?? BoxFit.cover,
        filterQuality: FilterQuality.high,
        memCacheWidth: 800, // Memory cache optimization
        maxWidthDiskCache: 800, // Disk cache optimization
        fadeInDuration: const Duration(
          milliseconds: 0,
        ), // No fade for cached images
        fadeOutDuration: const Duration(milliseconds: 0),
        useOldImageOnUrlChange:
            true, // Keep showing old image while new one loads
        placeholder: (context, url) {
          // Keep skeleton visible during initial load only
          return const SizedBox.shrink();
        },
        imageBuilder: (context, imageProvider) {
          _markLoadedAsync();
          return Image(
            image: imageProvider,
            fit: widget.fit ?? BoxFit.cover,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true, // Seamless transition
          );
        },
        errorWidget: (context, url, error) => _downloadPromptFallback(),
      ),
    );
  }

  void _markLoadedAsync() {
    if (_loaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loaded) {
        setState(() => _loaded = true);
      }
    });
  }

  Widget _errorFallback() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.broken_image,
          color: isDark ? Colors.white54 : Colors.grey.shade600,
          size: 36,
        ),
      ),
    );
  }

  Widget _loadingSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: const Center(
        child: SizedBox.shrink(), // Empty - the upload overlay will show on top
      ),
    );
  }

  Widget _downloadPromptFallback() {
    _markLoadedAsync();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
    );
  }
}
