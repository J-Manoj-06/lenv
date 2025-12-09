import 'package:hive_flutter/hive_flutter.dart';

/// Local cache storage using Hive
/// Manages:
/// - Messages (with pagination)
/// - Media metadata
/// - User session data
/// - Unread counts
///
/// Auto-clears when user logs out
class LocalCacheService {
  static const String _messagesBoxName = 'messages_cache';
  static const String _mediaBoxName = 'media_cache';
  static const String _userSessionBoxName = 'user_session';
  static const String _unreadCountsBoxName = 'unread_counts';
  static const String _mediaMetadataBoxName = 'media_metadata';

  static final LocalCacheService _instance = LocalCacheService._internal();

  late Box<Map> _messagesBox;
  late Box<Map> _mediaBox;
  late Box<String> _sessionBox;
  late Box<int> _unreadCountsBox;
  late Box<Map> _mediaMetadataBox;

  bool _initialized = false;

  LocalCacheService._internal();

  factory LocalCacheService() {
    return _instance;
  }

  /// Initialize Hive and open all boxes
  /// Call this once in main() after Firebase initialization
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Hive.initFlutter();

      _messagesBox = await Hive.openBox<Map>(_messagesBoxName);
      _mediaBox = await Hive.openBox<Map>(_mediaBoxName);
      _sessionBox = await Hive.openBox<String>(_userSessionBoxName);
      _unreadCountsBox = await Hive.openBox<int>(_unreadCountsBoxName);
      _mediaMetadataBox = await Hive.openBox<Map>(_mediaMetadataBoxName);

      _initialized = true;
      print('✅ LocalCacheService initialized');
    } catch (e) {
      print('❌ Failed to initialize LocalCacheService: $e');
      rethrow;
    }
  }

  /// Store user session info (called on login)
  Future<void> saveUserSession({
    required String userId,
    required String userRole,
    required String schoolCode,
  }) async {
    await _sessionBox.clear();
    await _sessionBox.putAll({
      'userId': userId,
      'userRole': userRole,
      'schoolCode': schoolCode,
      'loginTime': DateTime.now().toIso8601String(),
    });
  }

  /// Get current user session
  Map<String, String>? getUserSession() {
    try {
      if (_sessionBox.isEmpty) return null;
      return {
        'userId': _sessionBox.get('userId') ?? '',
        'userRole': _sessionBox.get('userRole') ?? '',
        'schoolCode': _sessionBox.get('schoolCode') ?? '',
      };
    } catch (e) {
      print('Error getting user session: $e');
      return null;
    }
  }

  /// Clear all user data on logout
  Future<void> clearUserData() async {
    try {
      await Future.wait([
        _messagesBox.clear(),
        _mediaBox.clear(),
        _sessionBox.clear(),
        _unreadCountsBox.clear(),
        _mediaMetadataBox.clear(),
      ]);
      print('✅ User data cleared from cache');
    } catch (e) {
      print('❌ Failed to clear user data: $e');
      rethrow;
    }
  }

  /// Cache messages for a conversation
  /// Key: conversationId
  /// Value: {messages: [...], lastUpdated: ISO8601}
  Future<void> cacheMessages({
    required String conversationId,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      await _messagesBox.put(conversationId, {
        'messages': messages,
        'lastUpdated': DateTime.now().toIso8601String(),
        'count': messages.length,
      });
    } catch (e) {
      print('Error caching messages: $e');
    }
  }

  /// Get cached messages for a conversation
  List<Map<String, dynamic>>? getCachedMessages(String conversationId) {
    try {
      final cached = _messagesBox.get(conversationId);
      if (cached == null) return null;

      final messages = cached['messages'] as List?;
      if (messages == null) return null;

      return List<Map<String, dynamic>>.from(messages);
    } catch (e) {
      print('Error getting cached messages: $e');
      return null;
    }
  }

  /// Check if conversation cache is stale
  /// Returns true if cache is older than maxAge
  bool isCacheStale({
    required String conversationId,
    Duration maxAge = const Duration(hours: 1),
  }) {
    try {
      final cached = _messagesBox.get(conversationId);
      if (cached == null) return true;

      final lastUpdated = DateTime.parse(cached['lastUpdated'] as String);
      return DateTime.now().difference(lastUpdated) > maxAge;
    } catch (e) {
      return true;
    }
  }

  /// Cache media metadata
  /// Key: mediaId
  /// Value: media metadata map
  Future<void> cacheMediaMetadata({
    required String mediaId,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      metadata['cachedAt'] = DateTime.now().toIso8601String();
      await _mediaMetadataBox.put(mediaId, metadata);
    } catch (e) {
      print('Error caching media metadata: $e');
    }
  }

  /// Get cached media metadata
  Map<String, dynamic>? getCachedMediaMetadata(String mediaId) {
    try {
      final cached = _mediaMetadataBox.get(mediaId);
      if (cached == null) return null;
      return Map<String, dynamic>.from(cached);
    } catch (e) {
      print('Error getting cached media metadata: $e');
      return null;
    }
  }

  /// Cache unread count for a conversation
  Future<void> updateUnreadCount({
    required String conversationId,
    required int count,
  }) async {
    try {
      await _unreadCountsBox.put(conversationId, count);
    } catch (e) {
      print('Error updating unread count: $e');
    }
  }

  /// Get cached unread count
  int? getUnreadCount(String conversationId) {
    try {
      return _unreadCountsBox.get(conversationId);
    } catch (e) {
      return null;
    }
  }

  /// Cache media file locally (for offline access)
  /// Key: mediaId
  /// Value: file data map
  Future<void> cacheMediaFile({
    required String mediaId,
    required List<int> fileBytes,
    required String fileName,
    required String fileType,
  }) async {
    try {
      // Note: For large files, consider using CacheManager instead
      // This is for small files only (< 5MB)
      if (fileBytes.length > 5 * 1024 * 1024) {
        print('⚠️ File too large for local cache: ${fileBytes.length} bytes');
        return;
      }

      await _mediaBox.put(mediaId, {
        'fileName': fileName,
        'fileType': fileType,
        'fileSize': fileBytes.length,
        'cachedAt': DateTime.now().toIso8601String(),
        // Don't store actual bytes in Hive - use CacheManager instead
      });
    } catch (e) {
      print('Error caching media file: $e');
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    return {
      'messages': _messagesBox.length,
      'media': _mediaBox.length,
      'mediaMetadata': _mediaMetadataBox.length,
      'unreadCounts': _unreadCountsBox.length,
      'hasUserSession': _sessionBox.isNotEmpty,
      'cacheSize': _messagesBox.isEmpty
          ? 0
          : _messagesBox.values.fold(
              0,
              (sum, val) => sum + (val.toString().length ?? 0),
            ),
    };
  }

  /// Delete specific conversation cache
  Future<void> deleteConversationCache(String conversationId) async {
    try {
      await _messagesBox.delete(conversationId);
      await _unreadCountsBox.delete(conversationId);
    } catch (e) {
      print('Error deleting conversation cache: $e');
    }
  }

  /// Delete specific media cache
  Future<void> deleteMediaCache(String mediaId) async {
    try {
      await _mediaBox.delete(mediaId);
      await _mediaMetadataBox.delete(mediaId);
    } catch (e) {
      print('Error deleting media cache: $e');
    }
  }
}
