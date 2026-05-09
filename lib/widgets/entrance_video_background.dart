import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class EntranceVideoBackground extends StatefulWidget {
  final Widget child;
  final List<Color> overlayColors;
  final double overlayOpacity;
  final double videoOpacity;
  final Alignment begin;
  final Alignment end;

  const EntranceVideoBackground({
    super.key,
    required this.child,
    this.overlayColors = const [Color(0xFF0F0F0F), Color(0xFF1A1205)],
    this.overlayOpacity = 0.72,
    this.videoOpacity = 0.92,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  @override
  State<EntranceVideoBackground> createState() =>
      _EntranceVideoBackgroundState();
}

class _EntranceVideoBackgroundState extends State<EntranceVideoBackground> {
  static VideoPlayerController? _controller;
  static Future<void>? _initialization;
  static bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _ensureController();
  }

  Future<void> _ensureController() async {
    if (_controller == null && !_initializing) {
      _initializing = true;
      _controller = VideoPlayerController.asset('assets/enter_video.mp4')
        ..setLooping(true)
        ..setVolume(0);
      _initialization = _controller!.initialize().then((_) {
        _controller?.play();
      }).catchError((_) {
        // Fallback to a static background if video init fails.
      });
      await _initialization;
      _initializing = false;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (_controller != null &&
        _controller!.value.isInitialized &&
        !_controller!.value.isPlaying) {
      _controller!.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoLayer(),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: widget.begin,
              end: widget.end,
              colors: widget.overlayColors
                  .map((color) => color.withValues(alpha: widget.overlayOpacity))
                  .toList(),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }

  Widget _buildVideoLayer() {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return Container(color: const Color(0xFF0F0F0F));
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: Opacity(
              opacity: widget.videoOpacity,
              child: VideoPlayer(controller),
            ),
          ),
        ),
      ),
    );
  }
}