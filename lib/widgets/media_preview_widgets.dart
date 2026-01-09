import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_message.dart';

/// WhatsApp-style image preview widget
/// Shows thumbnail with tap to open full image
class MediaImagePreview extends StatefulWidget {
  final MediaMessage media;
  final VoidCallback? onTap;
  final double maxWidth;
  final bool showSenderInfo;

  const MediaImagePreview({
    super.key,
    required this.media,
    this.onTap,
    this.maxWidth = 300,
    this.showSenderInfo = true,
  });

  @override
  State<MediaImagePreview> createState() => _MediaImagePreviewState();
}

class _MediaImagePreviewState extends State<MediaImagePreview> {
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    // Calculate aspect ratio for proper sizing
    final width = widget.maxWidth;
    final aspectRatio =
        (widget.media.width ?? 1920) / (widget.media.height ?? 1080);
    final height = width / aspectRatio;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[300],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Thumbnail or full image
            _buildImageWidget(width, height),

            // Loading indicator
            if (_isLoading)
              Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.7),
                  ),
                ),
              ),

            // Tap to open hint
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.fullscreen, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageWidget(double width, double height) {
    if (widget.media.thumbnailUrl != null &&
        widget.media.thumbnailUrl!.isNotEmpty) {
      // Use thumbnail URL from R2
      if (widget.media.thumbnailUrl!.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: widget.media.thumbnailUrl!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          placeholder: (context, url) => _buildPlaceholder(),
          errorWidget: (context, url, error) => _buildError(),
          imageBuilder: (context, imageProvider) {
            Future.delayed(Duration.zero, () {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            });
            return Image(image: imageProvider, fit: BoxFit.cover);
          },
        );
      } else {
        // Base64 encoded thumbnail - use simple Image.memory
        return Image.memory(
          Uri.dataFromString(
            'data:image/jpg;base64,${widget.media.thumbnailUrl}',
          ).data!.contentAsBytes(),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildError(),
        );
      }
    } else {
      // Fallback to full image URL
      return CachedNetworkImage(
        imageUrl: widget.media.r2Url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildError(),
        imageBuilder: (context, imageProvider) {
          Future.delayed(Duration.zero, () {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          });
          return Image(image: imageProvider, fit: BoxFit.cover);
        },
      );
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[400],
      child: Center(child: Icon(Icons.image, color: Colors.grey[600])),
    );
  }

  Widget _buildError() {
    return Container(
      color: Colors.grey[400],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, color: Colors.red),
            SizedBox(height: 8),
            Text(
              'Failed to load',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style PDF preview widget
/// Green card with icon, filename, and size
class MediaPdfPreview extends StatelessWidget {
  final MediaMessage media;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;
  final double maxWidth;

  const MediaPdfPreview({
    super.key,
    required this.media,
    this.onTap,
    this.onDownload,
    this.maxWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: maxWidth,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF34B7F1), Color(0xFF25A55E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // PDF Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  Icons.picture_as_pdf,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            SizedBox(width: 12),
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        media.formattedSize,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                      if (media.uploadFailed) ...[
                        SizedBox(width: 8),
                        Icon(Icons.error, color: Colors.red, size: 14),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            // Download icon
            GestureDetector(
              onTap: onDownload,
              child: Icon(Icons.download, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic media message tile for conversation list
/// Shows preview thumbnail + last message indicator
class MediaMessageTile extends StatelessWidget {
  final MediaMessage media;
  final VoidCallback onTap;
  final bool isOwner; // sent by current user

  const MediaMessageTile({
    super.key,
    required this.media,
    required this.onTap,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: isOwner ? Color(0xFFE8F5E9) : Color(0xFFF5F5F5),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(isOwner ? 12 : 2),
            bottomRight: Radius.circular(isOwner ? 2 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media preview
            if (media.isImage)
              MediaImagePreview(media: media, maxWidth: 250, onTap: onTap)
            else if (media.isPdf)
              MediaPdfPreview(media: media, maxWidth: 250, onTap: onTap),
            SizedBox(height: 8),
            // Metadata
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.fileName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        media.formattedSize,
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      if (media.isPending)
                        Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Uploading...',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        )
                      else if (media.uploadFailed)
                        Row(
                          children: [
                            Icon(Icons.error, size: 12, color: Colors.red),
                            SizedBox(width: 4),
                            Text(
                              'Failed',
                              style: TextStyle(fontSize: 10, color: Colors.red),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Media preview dialog for full-screen viewing
class MediaPreviewDialog extends StatefulWidget {
  final MediaMessage media;
  final List<MediaMessage> allMedia; // For swiping between media
  final int initialIndex;

  const MediaPreviewDialog({
    super.key,
    required this.media,
    required this.allMedia,
    this.initialIndex = 0,
  });

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.media.fileName),
        actions: [
          IconButton(
            icon: Icon(Icons.download),
            onPressed: () {
              // TODO: Implement download
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemCount: widget.allMedia.length,
        itemBuilder: (context, index) {
          final media = widget.allMedia[index];

          if (media.isImage) {
            return InteractiveViewer(
              child: Center(
                child: Image.network(
                  media.r2Url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white, size: 64),
                        SizedBox(height: 16),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          } else if (media.isPdf) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_as_pdf, color: Colors.white, size: 64),
                  SizedBox(height: 16),
                  Text(
                    media.fileName,
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(Icons.download),
                    label: Text('Download PDF'),
                    onPressed: () {
                      // TODO: Implement PDF download
                    },
                  ),
                ],
              ),
            );
          }

          return SizedBox.shrink();
        },
      ),
    );
  }
}
