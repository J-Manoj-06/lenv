import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';

/// WhatsApp-style full-screen profile photo viewer.
///
/// Features:
/// - Zoom (pinch/double-tap)
/// - Dark background
/// - User name in header
/// - Swipe down to close
class FullScreenDPViewer extends StatefulWidget {
  final String imageUrl;
  final String userName;
  final bool showViewProfileOption;
  final VoidCallback? onViewProfile;

  const FullScreenDPViewer({
    super.key,
    required this.imageUrl,
    required this.userName,
    this.showViewProfileOption = false,
    this.onViewProfile,
  });

  /// Open as a route.
  static Route<void> route({
    required String imageUrl,
    required String userName,
    bool showViewProfileOption = false,
    VoidCallback? onViewProfile,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, _, _) => FullScreenDPViewer(
        imageUrl: imageUrl,
        userName: userName,
        showViewProfileOption: showViewProfileOption,
        onViewProfile: onViewProfile,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  @override
  State<FullScreenDPViewer> createState() => _FullScreenDPViewerState();
}

class _FullScreenDPViewerState extends State<FullScreenDPViewer>
    with SingleTickerProviderStateMixin {
  late AnimationController _dragController;
  double _dragOffset = 0.0;
  double _opacity = 1.0;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _dragController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _dragController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() {
      _dragOffset += details.delta.dy;
      // Fade out while dragging down
      _opacity = 1.0 - (_dragOffset.abs() / 300).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    if (_dragOffset > 80 ||
        details.primaryVelocity != null && details.primaryVelocity! > 500) {
      Navigator.of(context).pop();
    } else {
      // Snap back
      setState(() {
        _dragOffset = 0.0;
        _opacity = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: Duration.zero,
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Container(
              color: Colors.black,
              child: Column(
                children: [
                  // Header
                  _buildHeader(context),
                  // Image viewer
                  Expanded(child: _buildImageViewer()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        color: Colors.black.withOpacity(0.8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.userName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.showViewProfileOption && widget.onViewProfile != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onViewProfile?.call();
                },
                child: const Text(
                  'View Profile',
                  style: TextStyle(
                    color: Color(0xFF4FC3F7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageViewer() {
    return PhotoView(
      imageProvider: CachedNetworkImageProvider(widget.imageUrl),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
      basePosition: Alignment.center,
      enablePanAlways: false,
      tightMode: true,
      scaleStateChangedCallback: (state) {
        final zoomed =
            state == PhotoViewScaleState.zoomedIn ||
            state == PhotoViewScaleState.covering ||
            state == PhotoViewScaleState.originalSize;
        if (mounted && _isZoomed != zoomed) {
          setState(() {
            _isZoomed = zoomed;
            if (!zoomed) {
              _dragOffset = 0.0;
              _opacity = 1.0;
            }
          });
        }
      },
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => Center(
        child: CircularProgressIndicator(
          value: event == null || event.expectedTotalBytes == null
              ? null
              : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
          color: Colors.white,
          strokeWidth: 2,
        ),
      ),
      errorBuilder: (context, error, stackTrace) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load image',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
