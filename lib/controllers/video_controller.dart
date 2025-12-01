import 'package:flutter/foundation.dart';
import '../models/video_model.dart';
import '../repositories/video_repository.dart';

/// Controller for managing video search and display
/// Uses ChangeNotifier for state management with Provider
class VideoController extends ChangeNotifier {
  final VideoRepository _repository;

  VideoController({VideoRepository? repository})
    : _repository = repository ?? VideoRepository();

  // State variables
  bool _isLoading = false;
  List<VideoModel> _videoList = [];
  String _searchQuery = '';
  String? _error;

  // Getters
  bool get isLoading => _isLoading;
  List<VideoModel> get videoList => _videoList;
  String get searchQuery => _searchQuery;
  String? get error => _error;
  bool get hasError => _error != null;

  /// Search for videos based on query
  ///
  /// Updates videoList and notifies listeners
  Future<void> searchVideos(String query) async {
    // Prevent duplicate searches
    if (query.trim() == _searchQuery.trim() && !hasError) {
      print('⏭️ Skipping duplicate search for: "$query"');
      return;
    }

    _searchQuery = query.trim();
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('🔍 Controller searching for: "$_searchQuery"');
      final videos = await _repository.searchVideos(_searchQuery);

      _videoList = videos;
      _isLoading = false;

      if (videos.isEmpty) {
        _error = 'No videos found for "$_searchQuery"';
        print('⚠️ $_error');
      } else {
        print('✅ Controller loaded ${videos.length} videos');
      }

      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to search videos. Please check your connection.';
      print('❌ Controller error: $e');
      notifyListeners();
    }
  }

  /// Load default educational videos
  ///
  /// Called on initial load or when search is cleared
  Future<void> loadDefaultVideos() async {
    _searchQuery = '';
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('📚 Loading default videos...');
      final videos = await _repository.loadDefaultVideos();

      _videoList = videos;
      _isLoading = false;

      if (videos.isEmpty) {
        _error = 'No videos available';
      } else {
        print('✅ Loaded ${videos.length} default videos');
      }

      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load videos. Please check your connection.';
      print('❌ Controller error loading defaults: $e');
      notifyListeners();
    }
  }

  /// Clear search and reset to default videos
  void clearSearch() {
    _searchQuery = '';
    _error = null;
    loadDefaultVideos();
  }

  /// Clear error message
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Retry last operation
  void retry() {
    if (_searchQuery.isEmpty) {
      loadDefaultVideos();
    } else {
      searchVideos(_searchQuery);
    }
  }
}
