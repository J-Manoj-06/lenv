import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'
    show kReleaseMode; // For debug-only fallback

/// Service for interacting with YouTube Data API v3
/// Handles video search and data fetching
class YouTubeApiService {
  // Prefer passing API key via --dart-define for security
  // flutter run --dart-define=YOUTUBE_API_KEY=YOUR_KEY
  static const String _envApiKey = String.fromEnvironment('YOUTUBE_API_KEY');
  // Debug-only fallback for local testing so you don't need --dart-define
  // NOTE: This value is used ONLY in debug/profile builds. In release builds,
  // it remains disabled (empty) to avoid accidentally shipping a hardcoded key.
  static const String _debugFallbackApiKey =
      'AIzaSyA3JPTTomKJv7nDvEfPtHf8ZC7iuu0kvgw'; // Android-restricted key

  static String get _apiKey {
    if (_envApiKey.isNotEmpty) return _envApiKey;
    // Use fallback only when NOT in release mode
    return kReleaseMode ? '' : _debugFallbackApiKey;
  }

  static const String _baseUrl = 'https://www.googleapis.com/youtube/v3';

  /// Search for videos based on a keyword query
  ///
  /// Returns raw JSON response from YouTube API
  /// Throws exception if API call fails
  Future<Map<String, dynamic>> searchVideos({
    required String query,
    int maxResults = 20,
  }) async {
    try {
      if (_apiKey.isEmpty) {
        throw Exception(
          'Missing YouTube API key. Provide --dart-define=YOUTUBE_API_KEY or set a debug fallback.',
        );
      }
      // Build search URL with parameters
      final url = Uri.parse(
        '$_baseUrl/search?part=snippet&type=video&maxResults=$maxResults&q=${Uri.encodeComponent(query)}&key=$_apiKey',
      );

      print('🔍 Searching YouTube for: "$query"');
      print('   URL: ${url.toString().replaceAll(_apiKey, 'API_KEY')}');

      // Make HTTP GET request
      final response = await http.get(url);

      print('   Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Parse and return JSON response
        final data = json.decode(response.body) as Map<String, dynamic>;
        final itemCount = (data['items'] as List?)?.length ?? 0;
        print('✅ Found $itemCount videos');
        return data;
      } else {
        // Try to parse YouTube error payload to show specific reason
        String message =
            'Failed to search videos. Status: ${response.statusCode}';
        try {
          final body = json.decode(response.body) as Map<String, dynamic>;
          final error = body['error'] as Map<String, dynamic>?;
          final code = error?['code'];
          final status = error?['status'];
          final errors =
              (error?['errors'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
          final reason = errors.isNotEmpty
              ? (errors.first['reason'] ?? '')
              : '';
          final messageText = error?['message'] ?? '';
          message = 'YouTube API error $code/$status: $messageText (${reason})';
          print('❌ $message');
        } catch (_) {
          print('❌ YouTube API error: ${response.statusCode}');
        }
        throw Exception(message);
      }
    } catch (e) {
      print('❌ Exception in searchVideos: $e');
      rethrow;
    }
  }

  /// Load default/recommended educational videos
  ///
  /// Fetches popular educational content when no search query is provided
  Future<Map<String, dynamic>> loadDefaultVideos() async {
    // Default search query for educational content
    const defaultQuery = 'educational tutorials';
    return searchVideos(query: defaultQuery, maxResults: 20);
  }

  /// Get video details by video ID (optional, for future use)
  ///
  /// Useful for getting detailed info like view count, like count, etc.
  Future<Map<String, dynamic>> getVideoDetails(String videoId) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/videos?part=snippet,statistics&id=$videoId&key=$_apiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to get video details. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Exception in getVideoDetails: $e');
      rethrow;
    }
  }
}
