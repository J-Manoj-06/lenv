import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// WhatsApp-style multi-image message bubble.
/// UI-only: no backend or state changes. Use in any chat screen.
///
/// Layout rules:
/// - Bubble width max = 70% of screen, aligned by `isMe`
/// - Rounded bubble with internal padding and clipped tiles
/// - Grid: 1,2,4 use clean squares; 3 uses 2+1 (full-width bottom)
/// - 5+ shows 2x2 initially with "+N" overlay on 4th tile; scrolls vertically
class MultiImageMessageBubble extends StatelessWidget {
  final List<String> imageUrls;
  final bool isMe;
  final void Function(int index) onImageTap;
  final List<double?>?
  uploadProgress; // Upload progress for each image (0.0-1.0)

  final double bubbleRadius;
  final double tileRadius;
  final double gap;
  final double maxScrollableHeight; // for >4 images

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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.7; // 70% of screen

    // Check if any image is still uploading - use more stable calculation
    bool isUploading = false;
    double overallProgress = 0.0;

    if (uploadProgress != null && uploadProgress!.isNotEmpty) {
      final activeUploads = uploadProgress!
          .where((p) => p != null && p < 1.0)
          .toList();
      if (activeUploads.isNotEmpty) {
        isUploading = true;
        // Calculate average progress across ALL images (not just active ones)
        final progressValues = uploadProgress!
            .where((p) => p != null)
            .cast<double>()
            .toList();
        if (progressValues.isNotEmpty) {
          // Average of all progress values for stable calculation
          overallProgress =
              progressValues.reduce((a, b) => a + b) / progressValues.length;
        }
      }
    }

    final content = _buildContent(context);

    final bubbleContent = Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(bubbleRadius),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(isDark ? 0.03 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(bubbleRadius),
            child: content,
          ),
          // Unified loading overlay when uploading - properly sized and centered
          if (isUploading)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(bubbleRadius),
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
        ],
      ),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: bubbleContent,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final count = imageUrls.length;
    final screenWidth = MediaQuery.of(context).size.width;

    // Single image
    if (count == 1) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenWidth * 0.7,
          maxHeight:
              screenWidth * 0.9, // Limit height to prevent extreme tall images
        ),
        child: _ImageTile(
          url: imageUrls[0],
          index: 0,
          radius: tileRadius,
          onTap: onImageTap,
          uploadProgress: uploadProgress?[0],
          fit: BoxFit.contain, // Preserve aspect ratio for single images
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
                  url: imageUrls[0],
                  index: 0,
                  radius: tileRadius,
                  onTap: onImageTap,
                  uploadProgress: uploadProgress?[0],
                ),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: _ImageTile(
                  url: imageUrls[1],
                  index: 1,
                  radius: tileRadius,
                  onTap: onImageTap,
                  uploadProgress: uploadProgress?[1],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Special case for 3 items (WhatsApp: 2 top + 1 bottom full-width)
    if (count == 3) {
      return _ThreeImageLayout(
        imageUrls: imageUrls,
        gap: gap,
        tileRadius: tileRadius,
        onTap: onImageTap,
        uploadProgress: uploadProgress,
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
                        url: imageUrls[0],
                        index: 0,
                        radius: tileRadius,
                        onTap: onImageTap,
                        uploadProgress: uploadProgress?[0],
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _ImageTile(
                        url: imageUrls[1],
                        index: 1,
                        radius: tileRadius,
                        onTap: onImageTap,
                        uploadProgress: uploadProgress?[1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _ImageTile(
                        url: imageUrls[2],
                        index: 2,
                        radius: tileRadius,
                        onTap: onImageTap,
                        uploadProgress: uploadProgress?[2],
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _ImageTile(
                        url: imageUrls[3],
                        index: 3,
                        radius: tileRadius,
                        onTap: onImageTap,
                        uploadProgress: uploadProgress?[3],
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

    // 5+ images: scrollable 2x2 grid with overlay
    // Calculate explicit width: 2 tiles + 1 gap between them
    final tileSize =
        (screenWidth * 0.7 - (gap * 3)) / 2; // maxBubbleWidth - padding - gap
    final gridWidth = (tileSize * 2) + gap;

    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        childAspectRatio: 1,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final url = imageUrls[index];
        final showOverlay = (index == 3) && (count > 4);
        final overlayCount = showOverlay ? (count - 4) : 0;

        return _ImageTile(
          url: url,
          index: index,
          radius: tileRadius,
          onTap: onImageTap,
          showOverlay: showOverlay,
          overlayCount: overlayCount,
          uploadProgress:
              uploadProgress != null && index < uploadProgress!.length
              ? uploadProgress![index]
              : null,
        );
      },
    );

    return SizedBox(width: gridWidth, height: maxScrollableHeight, child: grid);
  }
}

class _ThreeImageLayout extends StatelessWidget {
  final List<String> imageUrls;
  final double gap;
  final double tileRadius;
  final void Function(int) onTap;
  final List<double?>? uploadProgress;

  const _ThreeImageLayout({
    required this.imageUrls,
    required this.gap,
    required this.tileRadius,
    required this.onTap,
    this.uploadProgress,
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
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _ImageTile(
                      url: imageUrls[1],
                      index: 1,
                      radius: tileRadius,
                      onTap: onTap,
                      uploadProgress: uploadProgress?[1],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
          // Bottom full-width tile (16:9 looks balanced inside bubble)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _ImageTile(
              url: imageUrls[2],
              index: 2,
              radius: tileRadius,
              onTap: onTap,
              uploadProgress: uploadProgress?[2],
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
  final double? uploadProgress; // 0.0 to 1.0, null means completed
  final BoxFit? fit; // Add fit parameter

  const _ImageTile({
    required this.url,
    required this.index,
    required this.radius,
    required this.onTap,
    this.showOverlay = false,
    this.overlayCount = 0,
    this.uploadProgress,
    this.fit, // Optional fit parameter
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile>
    with AutomaticKeepAliveClientMixin {
  bool _loaded = false;

  @override
  bool get wantKeepAlive => true; // Keep the widget alive

  @override
  Widget build(BuildContext context) {
    super.build(context); // Must call super for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
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
      // Local file path
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

    // Network image with caching
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
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
              size: 32,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap to download',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
