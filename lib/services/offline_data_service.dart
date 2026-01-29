import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';
import '../models/group_subject.dart';

/// Enhanced offline data service for WhatsApp-like offline experience
/// Stores messages, groups, communities, and media for offline access
class OfflineDataService {
  static final OfflineDataService _instance = OfflineDataService._internal();
  factory OfflineDataService() => _instance;
  OfflineDataService._internal();

  static const String _groupMessagesBox = 'group_messages_offline';
  static const String _groupSubjectsBox = 'group_subjects_offline';
  static const String _communitiesBox = 'communities_offline';
  static const String _communityPostsBox = 'community_posts_offline';
  static const String _userDataBox = 'user_data_offline';

  late Box<Map> _groupMessagesCache;
  late Box<Map> _groupSubjectsCache;
  late Box<Map> _communitiesCache;
  late Box<Map> _communityPostsCache;
  late Box<Map> _userDataCache;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Future.wait([
            Hive.openBox<Map>(_groupMessagesBox),
            Hive.openBox<Map>(_groupSubjectsBox),
            Hive.openBox<Map>(_communitiesBox),
            Hive.openBox<Map>(_communityPostsBox),
            Hive.openBox<Map>(_userDataBox),
          ])
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('OfflineDataService timeout'),
          )
          .then((boxes) {
            _groupMessagesCache = boxes[0];
            _groupSubjectsCache = boxes[1];
            _communitiesCache = boxes[2];
            _communityPostsCache = boxes[3];
            _userDataCache = boxes[4];
          });

      _initialized = true;
      debugPrint('✅ OfflineDataService initialized');
    } catch (e) {
      _initialized = true;
      debugPrint('⚠️ OfflineDataService initialization failed: $e');
      rethrow;
    }
  }

  // ==================== GROUP SUBJECTS ====================

  /// Cache student's classId
  Future<void> cacheStudentClassId({
    required String studentId,
    required String classId,
  }) async {
    try {
      await _userDataCache.put('classId_$studentId', {
        'classId': classId,
        'cachedAt': DateTime.now().toIso8601String(),
      });
      debugPrint('💾 Cached classId $classId for student $studentId');
    } catch (e) {
      debugPrint('Error caching classId: $e');
    }
  }

  /// Get cached classId for a student
  String? getCachedStudentClassId(String studentId) {
    try {
      final cached = _userDataCache.get('classId_$studentId');
      if (cached == null) return null;
      final classId = cached['classId'] as String?;
      if (classId != null) {
        debugPrint('📦 Using cached classId for student $studentId');
      }
      return classId;
    } catch (e) {
      debugPrint('Error reading cached classId: $e');
      return null;
    }
  }

  /// Cache group subjects for a student
  Future<void> cacheGroupSubjects({
    required String studentId,
    required List<GroupSubject> subjects,
  }) async {
    try {
      final data = subjects
          .map(
            (s) => {
              'id': s.id,
              'name': s.name,
              'teacherName': s.teacherName,
              'icon': s.icon,
            },
          )
          .toList();

      await _groupSubjectsCache.put('subjects_$studentId', {
        'subjects': data,
        'cachedAt': DateTime.now().toIso8601String(),
        'studentId': studentId,
      });
      debugPrint('✅ Cached ${subjects.length} group subjects for $studentId');
    } catch (e) {
      debugPrint('Error caching group subjects: $e');
    }
  }

  /// Get cached group subjects
  List<GroupSubject>? getCachedGroupSubjects(String studentId) {
    try {
      final cached = _groupSubjectsCache.get('subjects_$studentId');
      if (cached == null) return null;

      final subjectsList = cached['subjects'] as List?;
      if (subjectsList == null) return null;

      return subjectsList
          .map(
            (s) => GroupSubject(
              id: s['id'] ?? '',
              name: s['name'] ?? '',
              teacherName: s['teacherName'] ?? '',
              icon: s['icon'] ?? '📚',
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Error reading cached group subjects: $e');
      return null;
    }
  }

  // ==================== GROUP MESSAGES ====================

  /// Cache messages for a group chat
  Future<void> cacheGroupMessages({
    required String chatId,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      await _groupMessagesCache.put(chatId, {
        'messages': messages,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': messages.length,
      });
      debugPrint('✅ Cached ${messages.length} messages for $chatId');
    } catch (e) {
      debugPrint('Error caching group messages: $e');
    }
  }

  /// Get cached messages for a group chat
  List<Map<String, dynamic>>? getCachedGroupMessages(String chatId) {
    try {
      final cached = _groupMessagesCache.get(chatId);
      if (cached == null) return null;

      final messages = cached['messages'] as List?;
      if (messages == null) return null;

      return List<Map<String, dynamic>>.from(messages);
    } catch (e) {
      debugPrint('Error reading cached group messages: $e');
      return null;
    }
  }

  /// Store last message timestamp for a chat (for sorting)
  Future<void> cacheLastMessageTimestamp({
    required String chatId,
    required int timestamp,
  }) async {
    try {
      final key = 'last_msg_ts_$chatId';
      await _userDataCache.put(key, {
        'timestamp': timestamp,
        'cachedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error caching last message timestamp: $e');
    }
  }

  /// Get cached last message timestamp
  int? getCachedLastMessageTimestamp(String chatId) {
    try {
      final key = 'last_msg_ts_$chatId';
      final cached = _userDataCache.get(key);
      if (cached == null) return null;
      return cached['timestamp'] as int?;
    } catch (e) {
      debugPrint('Error reading cached timestamp: $e');
      return null;
    }
  }

  // ==================== COMMUNITIES ====================

  /// Cache communities list
  Future<void> cacheCommunities({
    required String studentId,
    required List<Map<String, dynamic>> communities,
  }) async {
    try {
      await _communitiesCache.put('communities_$studentId', {
        'communities': communities,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': communities.length,
      });
      debugPrint('✅ Cached ${communities.length} communities for $studentId');
    } catch (e) {
      debugPrint('Error caching communities: $e');
    }
  }

  /// Get cached communities
  List<Map<String, dynamic>>? getCachedCommunities(String studentId) {
    try {
      final cached = _communitiesCache.get('communities_$studentId');
      if (cached == null) return null;

      final communities = cached['communities'] as List?;
      if (communities == null) return null;

      return List<Map<String, dynamic>>.from(communities);
    } catch (e) {
      debugPrint('Error reading cached communities: $e');
      return null;
    }
  }

  /// Cache posts for a community
  Future<void> cacheCommunityPosts({
    required String communityId,
    required List<Map<String, dynamic>> posts,
  }) async {
    try {
      await _communityPostsCache.put('posts_$communityId', {
        'posts': posts,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': posts.length,
      });
      debugPrint('✅ Cached ${posts.length} posts for community $communityId');
    } catch (e) {
      debugPrint('Error caching community posts: $e');
    }
  }

  /// Get cached posts for a community
  List<Map<String, dynamic>>? getCachedCommunityPosts(String communityId) {
    try {
      final cached = _communityPostsCache.get('posts_$communityId');
      if (cached == null) return null;

      final posts = cached['posts'] as List?;
      if (posts == null) return null;

      return List<Map<String, dynamic>>.from(posts);
    } catch (e) {
      debugPrint('Error reading cached community posts: $e');
      return null;
    }
  }

  // ==================== UTILITY ====================

  /// Clear all cached data for a user
  Future<void> clearUserCache(String userId) async {
    try {
      await _groupSubjectsCache.delete('subjects_$userId');
      await _communitiesCache.delete('communities_$userId');
      debugPrint('✅ Cleared cache for user $userId');
    } catch (e) {
      debugPrint('Error clearing user cache: $e');
    }
  }

  /// Clear all caches (for logout)
  Future<void> clearAllCaches() async {
    try {
      await Future.wait([
        _groupMessagesCache.clear(),
        _groupSubjectsCache.clear(),
        _communitiesCache.clear(),
        _communityPostsCache.clear(),
        _userDataCache.clear(),
      ]);
      debugPrint('✅ Cleared all offline caches');
    } catch (e) {
      debugPrint('Error clearing all caches: $e');
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'groupMessages': _groupMessagesCache.length,
      'groupSubjects': _groupSubjectsCache.length,
      'communities': _communitiesCache.length,
      'communityPosts': _communityPostsCache.length,
      'userData': _userDataCache.length,
    };
  }
}
