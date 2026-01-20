import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';

/// Unified offline cache manager for all app data
/// Handles:
/// - Groups (Student, Teacher, Parent, Institute)
/// - Communities
/// - Daily content
/// - Role-specific dashboards
/// - User profiles and metadata
class OfflineCacheManager {
  static final OfflineCacheManager _instance = OfflineCacheManager._internal();

  static const String _groupsBoxName = 'offline_groups';
  static const String _communitiesBoxName = 'offline_communities';
  static const String _dailyContentBoxName = 'offline_daily_content';
  static const String _dashboardBoxName = 'offline_dashboard';
  static const String _profileBoxName = 'offline_profile';
  static const String _leaderboardBoxName = 'offline_leaderboard';
  static const String _announcementsBoxName = 'offline_announcements';
  static const String _userDataBoxName = 'offline_user_data';

  late Box<Map> _groupsBox;
  late Box<Map> _communitiesBox;
  late Box<Map> _dailyContentBox;
  late Box<Map> _dashboardBox;
  late Box<Map> _profileBox;
  late Box<Map> _leaderboardBox;
  late Box<Map> _announcementsBox;
  late Box<Map> _userDataBox;

  bool _initialized = false;

  factory OfflineCacheManager() {
    return _instance;
  }

  OfflineCacheManager._internal();

  /// Initialize all cache boxes
  /// Call once during app startup
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Open all boxes in parallel with timeout
      await Future.wait([
            Hive.openBox<Map>(_groupsBoxName),
            Hive.openBox<Map>(_communitiesBoxName),
            Hive.openBox<Map>(_dailyContentBoxName),
            Hive.openBox<Map>(_dashboardBoxName),
            Hive.openBox<Map>(_profileBoxName),
            Hive.openBox<Map>(_leaderboardBoxName),
            Hive.openBox<Map>(_announcementsBoxName),
            Hive.openBox<Map>(_userDataBoxName),
          ])
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () =>
                throw TimeoutException('OfflineCacheManager timeout'),
          )
          .then((boxes) {
            _groupsBox = boxes[0];
            _communitiesBox = boxes[1];
            _dailyContentBox = boxes[2];
            _dashboardBox = boxes[3];
            _profileBox = boxes[4];
            _leaderboardBox = boxes[5];
            _announcementsBox = boxes[6];
            _userDataBox = boxes[7];
          });

      _initialized = true;
    } catch (e) {
      // Mark as initialized even on error to prevent retry loops
      _initialized = true;
      debugPrint('⚠️ OfflineCacheManager initialization failed: $e');
      rethrow;
    }
  }

  /// ==================== GROUPS ====================

  /// Cache groups data (works for all roles)
  /// groupsKey: "student_groups", "teacher_groups", "parent_groups", etc.
  Future<void> cacheGroups({
    required String userId,
    required String role,
    required List<Map<String, dynamic>> groupsList,
  }) async {
    try {
      final key = '${role.toLowerCase()}_groups_$userId';
      await _groupsBox.put(key, {
        'groups': groupsList,
        'role': role,
        'userId': userId,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': groupsList.length,
      });
    } catch (e) {
      debugPrint('Error caching groups: $e');
    }
  }

  /// Get cached groups for a user
  List<Map<String, dynamic>>? getCachedGroups({
    required String userId,
    required String role,
  }) {
    try {
      final key = '${role.toLowerCase()}_groups_$userId';
      final cached = _groupsBox.get(key);
      if (cached == null) return null;

      final groups = cached['groups'] as List?;
      return groups != null ? List<Map<String, dynamic>>.from(groups) : null;
    } catch (e) {
      debugPrint('Error retrieving cached groups: $e');
      return null;
    }
  }

  /// ==================== COMMUNITIES ====================

  /// Cache community data
  Future<void> cacheCommunities({
    required String userId,
    required List<Map<String, dynamic>> communities,
  }) async {
    try {
      await _communitiesBox.put('communities_$userId', {
        'communities': communities,
        'userId': userId,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': communities.length,
      });
    } catch (e) {
      debugPrint('Error caching communities: $e');
    }
  }

  /// Get cached communities
  List<Map<String, dynamic>>? getCachedCommunities(String userId) {
    try {
      final cached = _communitiesBox.get('communities_$userId');
      if (cached == null) return null;

      final communities = cached['communities'] as List?;
      return communities != null
          ? List<Map<String, dynamic>>.from(communities)
          : null;
    } catch (e) {
      debugPrint('Error retrieving cached communities: $e');
      return null;
    }
  }

  /// Cache community messages
  Future<void> cacheCommunityMessages({
    required String communityId,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      await _communitiesBox.put('community_messages_$communityId', {
        'messages': messages,
        'communityId': communityId,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': messages.length,
      });
    } catch (e) {
      debugPrint('Error caching community messages: $e');
    }
  }

  /// Get cached community messages
  List<Map<String, dynamic>>? getCachedCommunityMessages(String communityId) {
    try {
      final cached = _communitiesBox.get('community_messages_$communityId');
      if (cached == null) return null;

      final messages = cached['messages'] as List?;
      return messages != null
          ? List<Map<String, dynamic>>.from(messages)
          : null;
    } catch (e) {
      debugPrint('Error retrieving cached community messages: $e');
      return null;
    }
  }

  /// ==================== DAILY CONTENT ====================

  /// Cache daily content/challenges
  Future<void> cacheDailyContent({
    required String userId,
    required Map<String, dynamic> content,
  }) async {
    try {
      await _dailyContentBox.put('daily_content_$userId', {
        'content': content,
        'userId': userId,
        'cachedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error caching daily content: $e');
    }
  }

  /// Get cached daily content
  Map<String, dynamic>? getCachedDailyContent(String userId) {
    try {
      final cached = _dailyContentBox.get('daily_content_$userId');
      if (cached == null) return null;

      final content = cached['content'] as Map?;
      return content != null ? Map<String, dynamic>.from(content) : null;
    } catch (e) {
      debugPrint('Error retrieving cached daily content: $e');
      return null;
    }
  }

  /// ==================== DASHBOARDS ====================

  /// Cache role-specific dashboard data
  Future<void> cacheDashboard({
    required String userId,
    required String role,
    required Map<String, dynamic> dashboardData,
  }) async {
    try {
      final key = '${role.toLowerCase()}_dashboard_$userId';
      await _dashboardBox.put(key, {
        'data': dashboardData,
        'userId': userId,
        'role': role,
        'cachedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error caching dashboard: $e');
    }
  }

  /// Get cached dashboard
  Map<String, dynamic>? getCachedDashboard({
    required String userId,
    required String role,
  }) {
    try {
      final key = '${role.toLowerCase()}_dashboard_$userId';
      final cached = _dashboardBox.get(key);
      if (cached == null) return null;

      final data = cached['data'] as Map?;
      return data != null ? Map<String, dynamic>.from(data) : null;
    } catch (e) {
      debugPrint('Error retrieving cached dashboard: $e');
      return null;
    }
  }

  /// ==================== PROFILES ====================

  /// Cache user profile data
  Future<void> cacheProfile({
    required String userId,
    required Map<String, dynamic> profileData,
  }) async {
    try {
      await _profileBox.put('profile_$userId', {
        'profile': profileData,
        'userId': userId,
        'cachedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error caching profile: $e');
    }
  }

  /// Get cached profile
  Map<String, dynamic>? getCachedProfile(String userId) {
    try {
      final cached = _profileBox.get('profile_$userId');
      if (cached == null) return null;

      final profile = cached['profile'] as Map?;
      return profile != null ? Map<String, dynamic>.from(profile) : null;
    } catch (e) {
      debugPrint('Error retrieving cached profile: $e');
      return null;
    }
  }

  /// ==================== LEADERBOARDS ====================

  /// Cache leaderboard data
  Future<void> cacheLeaderboard({
    required String classId,
    required List<Map<String, dynamic>> leaderboardData,
  }) async {
    try {
      await _leaderboardBox.put('leaderboard_$classId', {
        'data': leaderboardData,
        'classId': classId,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': leaderboardData.length,
      });
    } catch (e) {
      debugPrint('Error caching leaderboard: $e');
    }
  }

  /// Get cached leaderboard
  List<Map<String, dynamic>>? getCachedLeaderboard(String classId) {
    try {
      final cached = _leaderboardBox.get('leaderboard_$classId');
      if (cached == null) return null;

      final data = cached['data'] as List?;
      return data != null ? List<Map<String, dynamic>>.from(data) : null;
    } catch (e) {
      debugPrint('Error retrieving cached leaderboard: $e');
      return null;
    }
  }

  /// ==================== ANNOUNCEMENTS ====================

  /// Cache announcements
  Future<void> cacheAnnouncements({
    required String scope, // "school", "class", "institute", "community"
    required String scopeId,
    required List<Map<String, dynamic>> announcements,
  }) async {
    try {
      final key = '${scope}_announcements_$scopeId';
      await _announcementsBox.put(key, {
        'announcements': announcements,
        'scope': scope,
        'scopeId': scopeId,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': announcements.length,
      });
    } catch (e) {
      debugPrint('Error caching announcements: $e');
    }
  }

  /// Get cached announcements
  List<Map<String, dynamic>>? getCachedAnnouncements({
    required String scope,
    required String scopeId,
  }) {
    try {
      final key = '${scope}_announcements_$scopeId';
      final cached = _announcementsBox.get(key);
      if (cached == null) return null;

      final announcements = cached['announcements'] as List?;
      return announcements != null
          ? List<Map<String, dynamic>>.from(announcements)
          : null;
    } catch (e) {
      debugPrint('Error retrieving cached announcements: $e');
      return null;
    }
  }

  /// ==================== GENERIC USER DATA ====================

  /// Cache any additional user data
  /// dataType: "schools", "teachers", "parents", "tests", etc.
  Future<void> cacheUserData({
    required String userId,
    required String dataType,
    required dynamic data,
  }) async {
    try {
      await _userDataBox.put('${dataType}_$userId', {
        'type': dataType,
        'userId': userId,
        'data': data is List ? data : [data],
        'cachedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error caching user data ($dataType): $e');
    }
  }

  /// Get cached user data
  dynamic getCachedUserData({
    required String userId,
    required String dataType,
  }) {
    try {
      final cached = _userDataBox.get('${dataType}_$userId');
      if (cached == null) return null;

      return cached['data'];
    } catch (e) {
      debugPrint('Error retrieving cached user data ($dataType): $e');
      return null;
    }
  }

  /// ==================== UTILITY METHODS ====================

  /// Check if data is stale
  bool isDataStale({
    required String key,
    Box<Map>? box,
    Duration maxAge = const Duration(hours: 6),
  }) {
    try {
      final boxToCheck = box ?? _userDataBox;
      final cached = boxToCheck.get(key);
      if (cached == null) return true;

      final cachedAt = cached['cachedAt'];
      if (cachedAt == null) return true;

      final cacheTime = DateTime.parse(cachedAt as String);
      return DateTime.now().difference(cacheTime) > maxAge;
    } catch (e) {
      return true;
    }
  }

  /// Clear all offline cache (on logout)
  Future<void> clearAllCache() async {
    try {
      await Future.wait([
        _groupsBox.clear(),
        _communitiesBox.clear(),
        _dailyContentBox.clear(),
        _dashboardBox.clear(),
        _profileBox.clear(),
        _leaderboardBox.clear(),
        _announcementsBox.clear(),
        _userDataBox.clear(),
      ]);
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  /// Clear cache for specific user (on logout)
  Future<void> clearUserCache(String userId) async {
    try {
      // Remove user-specific entries
      await _groupsBox.deleteAll(
        _groupsBox.keys
            .where((key) => (key as String).contains(userId))
            .toList(),
      );
      await _communitiesBox.deleteAll(
        _communitiesBox.keys
            .where((key) => (key as String).contains(userId))
            .toList(),
      );
      // ... continue for other boxes
    } catch (e) {
      debugPrint('Error clearing user cache: $e');
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    return {
      'groups': _groupsBox.length,
      'communities': _communitiesBox.length,
      'dailyContent': _dailyContentBox.length,
      'dashboards': _dashboardBox.length,
      'profiles': _profileBox.length,
      'leaderboards': _leaderboardBox.length,
      'announcements': _announcementsBox.length,
      'userData': _userDataBox.length,
      'totalKeys':
          _groupsBox.length +
          _communitiesBox.length +
          _dailyContentBox.length +
          _dashboardBox.length +
          _profileBox.length +
          _leaderboardBox.length +
          _announcementsBox.length +
          _userDataBox.length,
    };
  }
}
