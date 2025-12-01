import '../models/video_model.dart';
import '../services/youtube_api_service.dart';

/// Repository for managing video data
/// Acts as a layer between services and controllers
class VideoRepository {
  final YouTubeApiService _apiService;

  VideoRepository({YouTubeApiService? apiService})
    : _apiService = apiService ?? YouTubeApiService();

  /// Search for videos and convert to VideoModel list
  ///
  /// Returns list of parsed VideoModel objects
  /// Returns empty list if search fails
  Future<List<VideoModel>> searchVideos(String query) async {
    try {
      // Validate query
      if (query.trim().isEmpty) {
        print('⚠️ Empty search query, returning empty list');
        return [];
      }

      // Fetch data from API
      final data = await _apiService.searchVideos(query: query, maxResults: 20);

      // Extract items array
      final items = data['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) {
        print('⚠️ No videos found for query: "$query"');
        return [];
      }

      // Parse each item to VideoModel
      final videos = items
          .map((item) => VideoModel.fromJson(item as Map<String, dynamic>))
          .toList();

      print('✅ Parsed ${videos.length} videos from API response');
      return videos;
    } catch (e) {
      print('❌ Error in searchVideos repository: $e');
      // Return empty list on error to prevent crashes
      return [];
    }
  }

  /// Load default educational videos
  ///
  /// Fetches recommended content when no search is active
  Future<List<VideoModel>> loadDefaultVideos() async {
    try {
      final data = await _apiService.loadDefaultVideos();

      final items = data['items'] as List<dynamic>?;
      if (items == null || items.isEmpty) {
        print('⚠️ No default videos found');
        return [];
      }

      final videos = items
          .map((item) => VideoModel.fromJson(item as Map<String, dynamic>))
          .toList();

      print('✅ Loaded ${videos.length} default videos');
      return videos;
    } catch (e) {
      print('❌ Error loading default videos: $e');
      return [];
    }
  }

  /// Get detailed info for a specific video (optional, for future use)
  Future<Map<String, dynamic>?> getVideoDetails(String videoId) async {
    try {
      return await _apiService.getVideoDetails(videoId);
    } catch (e) {
      print('❌ Error getting video details: $e');
      return null;
    }
  }
}
