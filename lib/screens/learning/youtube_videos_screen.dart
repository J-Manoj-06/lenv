import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/video_controller.dart';
import '../../models/video_model.dart';

class YouTubeVideosScreen extends StatefulWidget {
  const YouTubeVideosScreen({super.key});

  @override
  State<YouTubeVideosScreen> createState() => _YouTubeVideosScreenState();
}

class _YouTubeVideosScreenState extends State<YouTubeVideosScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load default videos on initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VideoController>().loadDefaultVideos();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      context.read<VideoController>().clearSearch();
    } else {
      context.read<VideoController>().searchVideos(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primary = Color(0xFFF27F0D); // Student theme orange
    final bgLight = const Color(0xFFF5F5F5);
    final bgDark = const Color(0xFF231B0F);
    final cardBg = isDark ? const Color(0xFF3E3E3E) : Colors.white;

    return Consumer<VideoController>(
      builder: (context, controller, child) {
        return Scaffold(
          backgroundColor: isDark ? bgDark : bgLight,
          body: SafeArea(
            child: Column(
              children: [
                // Top app bar with search
                Container(
                  decoration: const BoxDecoration(
                    color: primary,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.arrow_back_ios_new,
                                color: Colors.white,
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'Learning Videos',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      // Search bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(color: Colors.black87),
                            onSubmitted: (_) => _handleSearch(),
                            decoration: InputDecoration(
                              hintText: 'Search videos...',
                              hintStyle: const TextStyle(color: Colors.grey),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.grey,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        controller.clearSearch();
                                      },
                                    )
                                  : IconButton(
                                      icon: const Icon(
                                        Icons.search,
                                        color: primary,
                                      ),
                                      onPressed: _handleSearch,
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Video list or loading/error state
                Expanded(child: _buildContent(controller, cardBg, isDark)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(VideoController controller, Color cardBg, bool isDark) {
    // Loading state
    if (controller.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF27F0D)),
      );
    }

    // Error state
    if (controller.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                controller.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: controller.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF27F0D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Empty state
    if (controller.videoList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 64,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No videos found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try a different search term',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Video list
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: controller.videoList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final video = controller.videoList[index];
        return _VideoCard(video: video, cardBg: cardBg);
      },
    );
  }
}

class _VideoCard extends StatelessWidget {
  final VideoModel video;
  final Color cardBg;

  const _VideoCard({required this.video, required this.cardBg});

  Future<void> _openYouTubeVideo(BuildContext context) async {
    final videoId = video.videoId;
    final youtubeBrowserUrl = Uri.parse(
      'https://www.youtube.com/watch?v=$videoId',
    );

    try {
      // Directly launch the YouTube URL in external browser/app
      await launchUrl(youtubeBrowserUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('❌ Error opening video: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open video. Please check if YouTube is installed.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _openYouTubeVideo(context),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      video.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.video_library, size: 48),
                      ),
                    ),
                  ),
                ),
                // Play button overlay
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      color: Colors.black.withOpacity(0.3),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.play_arrow, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'YouTube',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF212121),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    video.channelName,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? Colors.grey[400]
                          : const Color(0xFF757575),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.formattedDate,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Colors.grey[400]
                          : const Color(0xFF757575),
                    ),
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
