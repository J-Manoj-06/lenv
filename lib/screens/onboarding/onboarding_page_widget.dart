import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../constants/app_colors.dart';

/// Reusable onboarding page widget
class OnboardingPage extends StatelessWidget {
  final String title;
  final String? description;
  final List<String>? bulletPoints;
  final IconData? icon;
  final VideoPlayerController? videoController;
  final String? videoAssetPath;
  final LinearGradient? backgroundGradient;

  const OnboardingPage({
    super.key,
    required this.title,
    this.description,
    this.bulletPoints,
    this.icon,
    this.videoController,
    this.videoAssetPath,
    this.backgroundGradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasVideoBackground = videoController != null || videoAssetPath != null;

    if (hasVideoBackground) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildFullScreenVideoBackground(
            videoController: videoController,
            assetPath: videoAssetPath,
          ),
          Container(color: Colors.black.withOpacity(0.35)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.28),
                  Colors.black.withOpacity(0.05),
                  Colors.black.withOpacity(0.40),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Spacer(flex: 2),
                    const SizedBox(height: 120),
                    const SizedBox(height: 40),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ) ??
                          const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 20),
                    if (bulletPoints != null)
                      _buildBulletPoints(bulletPoints!, false)
                    else if (description != null)
                      _buildDescription(
                        description!,
                        false,
                        overrideColor: Colors.white.withOpacity(0.9),
                      ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: backgroundGradient,
        color: isDark ? AppColors.darkBackground : AppColors.background,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top spacing
              const Spacer(flex: 2),

              // Icon/Illustration (if provided)
              if (icon != null)
                _buildIcon(icon!, isDark)
              else
                const SizedBox(height: 120),

              const SizedBox(height: 40),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.textLight : AppColors.textDark,
                    ) ??
                    const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              // Description or Bullet Points
              if (bulletPoints != null)
                _buildBulletPoints(bulletPoints!, isDark)
              else if (description != null)
                _buildDescription(description!, isDark),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  /// Build autoplaying entrance video as a full-bleed background layer.
  Widget _buildFullScreenVideoBackground({
    VideoPlayerController? videoController,
    String? assetPath,
  }) {
    if (videoController != null) {
      return _SharedOnboardingVideoBackground(controller: videoController);
    }
    return _OnboardingVideoBackground(assetPath: assetPath!);
  }

  /// Build icon widget with gradient background
  Widget _buildIcon(IconData icon, bool isDark) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.2),
            AppColors.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
      ),
      child: Icon(icon, size: 60, color: AppColors.primary),
    );
  }

  /// Build description text
  Widget _buildDescription(
    String description,
    bool isDark, {
    Color? overrideColor,
  }) {
    return Text(
      description,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 16,
        color: overrideColor ??
            (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
        height: 1.6,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  /// Build bullet points list
  Widget _buildBulletPoints(List<String> points, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        points.length,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  points[index],
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingVideoBackground extends StatefulWidget {
  final String assetPath;

  const _OnboardingVideoBackground({required this.assetPath});

  @override
  State<_OnboardingVideoBackground> createState() =>
      _OnboardingVideoBackgroundState();
}

class _OnboardingVideoBackgroundState
    extends State<_OnboardingVideoBackground> {
  VideoPlayerController? _controller;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.assetPath)
      ..setLooping(true)
      ..setVolume(0);
    _initialization = _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller?.play();
    }).catchError((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        final isReady = controller != null && controller.value.isInitialized;

        if (!isReady) {
          return Container(
            color: Colors.black,
            child: const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }

        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SharedOnboardingVideoBackground extends StatelessWidget {
  final VideoPlayerController controller;

  const _SharedOnboardingVideoBackground({required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
