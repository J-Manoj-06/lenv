import 'dart:io';
import 'package:flutter/material.dart';

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

  final double bubbleRadius;
  final double tileRadius;
  final double gap;
  final double maxScrollableHeight; // for >4 images

  const MultiImageMessageBubble({
    super.key,
    required this.imageUrls,
    required this.isMe,
    required this.onImageTap,
    this.bubbleRadius = 18,
    this.tileRadius = 14,
    this.gap = 6,
    this.maxScrollableHeight = 240,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.7; // 70% of screen

    final bubbleColor = isDark
        ? const Color(0xFF11141B)
        : const Color(0xFFF6F7FA);
    final borderColor = const Color(0xFFFFA929).withOpacity(0.6);

    final content = _buildContent(context);
    final count = imageUrls.length;
    final useIntrinsic = count <= 4; // Only for small grids, not GridView
//summa
    final bubbleContent = Container(
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(bubbleRadius),
        border: Border.all(color: borderColor, width: 4),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(isDark ? 0.14 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(gap),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(bubbleRadius - 2),
        child: content,
      ),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: useIntrinsic
            ? IntrinsicWidth(child: bubbleContent)
            : bubbleContent,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final count = imageUrls.length;
    final screenWidth = MediaQuery.of(context).size.width;

    // Single image
    if (count == 1) {
      return AspectRatio(
        aspectRatio: 1,
        child: _ImageTile(
          url: imageUrls[0],
          index: 0,
          radius: tileRadius,
          onTap: onImageTap,
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
      physics: const BouncingScrollPhysics(),
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

  const _ThreeImageLayout({
    required this.imageUrls,
    required this.gap,
    required this.tileRadius,
    required this.onTap,
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

  const _ImageTile({
    required this.url,
    required this.index,
    required this.radius,
    required this.onTap,
    this.showOverlay = false,
    this.overlayCount = 0,
  });

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: GestureDetector(
        onTap: () => widget.onTap(widget.index),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Skeleton placeholder
            AnimatedOpacity(
              opacity: _loaded ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                decoration: BoxDecoration(color: Colors.grey.shade800),
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
    if (url.startsWith('/')) {
      // Local file path
      final file = File(url);
      _markLoadedAsync();
      return Image.file(
        file,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _errorFallback(),
      );
    }

    // Network image with loadingBuilder to update skeleton visibility
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      loadingBuilder: (context, child, progress) {
        if (progress == null) _markLoadedAsync();
        return child; // skeleton remains visible via AnimatedOpacity
      },
      errorBuilder: (_, __, ___) => _errorFallback(),
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
    return Container(
      color: Colors.grey.shade800,
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.white54, size: 36),
      ),
    );
  }
}
