/// Video model representing a YouTube video
/// Used for displaying search results and video information
class VideoModel {
  final String videoId;
  final String title;
  final String thumbnail;
  final String channelName;
  final DateTime publishedAt;
  final String description;

  VideoModel({
    required this.videoId,
    required this.title,
    required this.thumbnail,
    required this.channelName,
    required this.publishedAt,
    required this.description,
  });

  /// Parse YouTube API response to VideoModel
  /// Expected JSON structure from YouTube Data API v3 search endpoint
  factory VideoModel.fromJson(Map<String, dynamic> json) {
    try {
      final snippet = json['snippet'] as Map<String, dynamic>? ?? {};
      final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};

      // Get highest quality thumbnail available (maxres > high > medium > default)
      final thumbnailUrl =
          (thumbnails['high'] as Map<String, dynamic>?)?['url'] as String? ??
          (thumbnails['medium'] as Map<String, dynamic>?)?['url'] as String? ??
          (thumbnails['default'] as Map<String, dynamic>?)?['url'] as String? ??
          '';

      return VideoModel(
        videoId:
            (json['id'] as Map<String, dynamic>?)?['videoId'] as String? ?? '',
        title: snippet['title'] as String? ?? 'Untitled',
        thumbnail: thumbnailUrl,
        channelName: snippet['channelTitle'] as String? ?? 'Unknown Channel',
        publishedAt:
            DateTime.tryParse(snippet['publishedAt'] as String? ?? '') ??
            DateTime.now(),
        description: snippet['description'] as String? ?? '',
      );
    } catch (e) {
      print('❌ Error parsing video from JSON: $e');
      // Return a placeholder video on error
      return VideoModel(
        videoId: '',
        title: 'Error loading video',
        thumbnail: '',
        channelName: 'Unknown',
        publishedAt: DateTime.now(),
        description: '',
      );
    }
  }

  /// Convert VideoModel to JSON (for caching or storage if needed)
  Map<String, dynamic> toJson() {
    return {
      'videoId': videoId,
      'title': title,
      'thumbnail': thumbnail,
      'channelName': channelName,
      'publishedAt': publishedAt.toIso8601String(),
      'description': description,
    };
  }

  /// Format published date for display
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(publishedAt);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return 'Published $years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return 'Published $months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return 'Published ${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return 'Published ${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else {
      return 'Published recently';
    }
  }

  @override
  String toString() => 'VideoModel(id: $videoId, title: $title)';
}
