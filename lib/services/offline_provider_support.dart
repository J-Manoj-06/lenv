import 'package:flutter/material.dart';
import 'connectivity_service.dart';
import 'offline_cache_manager.dart';

/// Offline support mixin for providers
/// Add this to any provider to automatically support offline mode
mixin OfflineSupportMixin {
  /// Try to load data from cache if network is unavailable
  /// Returns cached data or null if not available
  Future<T?> loadFromCacheIfOffline<T>({
    required Future<T?> Function() onlineLoader,
    required T? Function() cacheLoader,
    required String cacheKey,
  }) async {
    final connectivityService = ConnectivityService();

    if (connectivityService.isOnline) {
      try {
        return await onlineLoader();
      } catch (e) {
        // Online fetch failed, try cache as fallback
        debugPrint('Online load failed for $cacheKey: $e');
      }
    }

    // Offline or failed: use cache
    return cacheLoader();
  }

  /// Attempt online operation with offline fallback
  /// Useful for one-time operations that should cache their result
  Future<T?> performWithOfflineFallback<T>({
    required Future<T?> Function() operation,
    required void Function(T data)? onSuccess,
    required Future<void> Function(T data)? onCacheSuccessfully,
  }) async {
    final connectivityService = ConnectivityService();

    try {
      if (connectivityService.isOnline) {
        final result = await operation();
        if (result != null && onSuccess != null) {
          onSuccess(result);
        }
        return result;
      }
    } catch (e) {
      debugPrint('Operation failed: $e');
      // Fall through to use existing cached data
    }

    return null;
  }

  /// Get cache manager instance
  OfflineCacheManager getCacheManager() => OfflineCacheManager();

  /// Get connectivity service instance
  ConnectivityService getConnectivityService() => ConnectivityService();
}

/// Provider-specific offline helpers
class ProviderOfflineHelpers {
  /// Cache student data
  static Future<void> cacheStudentData({
    required String studentId,
    required Map<String, dynamic> studentData,
  }) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.cacheProfile(
        userId: studentId,
        profileData: studentData,
      );
    } catch (e) {
      // Silent fail
    }
  }

  /// Get cached student data
  static Map<String, dynamic>? getCachedStudentData(String studentId) {
    try {
      final cacheManager = OfflineCacheManager();
      return cacheManager.getCachedProfile(studentId);
    } catch (e) {
      return null;
    }
  }

  /// Cache teacher data
  static Future<void> cacheTeacherData({
    required String teacherId,
    required Map<String, dynamic> teacherData,
  }) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.cacheProfile(
        userId: teacherId,
        profileData: teacherData,
      );
    } catch (e) {
      // Silent fail
    }
  }

  /// Get cached teacher data
  static Map<String, dynamic>? getCachedTeacherData(String teacherId) {
    try {
      final cacheManager = OfflineCacheManager();
      return cacheManager.getCachedProfile(teacherId);
    } catch (e) {
      return null;
    }
  }

  /// Cache dashboard data for any role
  static Future<void> cacheDashboardData({
    required String userId,
    required String role,
    required Map<String, dynamic> dashboardData,
  }) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.cacheDashboard(
        userId: userId,
        role: role,
        dashboardData: dashboardData,
      );
    } catch (e) {
      // Silent fail
    }
  }

  /// Get cached dashboard data
  static Map<String, dynamic>? getCachedDashboard({
    required String userId,
    required String role,
  }) {
    try {
      final cacheManager = OfflineCacheManager();
      return cacheManager.getCachedDashboard(userId: userId, role: role);
    } catch (e) {
      return null;
    }
  }

  /// Cache rewards/badges data
  static Future<void> cacheRewards({
    required String userId,
    required List<Map<String, dynamic>> rewards,
  }) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.cacheUserData(
        userId: userId,
        dataType: 'rewards',
        data: rewards,
      );
    } catch (e) {
      // Silent fail
    }
  }

  /// Get cached rewards
  static List<Map<String, dynamic>>? getCachedRewards(String userId) {
    try {
      final cacheManager = OfflineCacheManager();
      final cached = cacheManager.getCachedUserData(
        userId: userId,
        dataType: 'rewards',
      );
      return cached != null ? List<Map<String, dynamic>>.from(cached) : null;
    } catch (e) {
      return null;
    }
  }

  /// Cache leaderboard data
  static Future<void> cacheLeaderboard({
    required String classId,
    required List<Map<String, dynamic>> leaderboardData,
  }) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.cacheLeaderboard(
        classId: classId,
        leaderboardData: leaderboardData,
      );
    } catch (e) {
      // Silent fail
    }
  }

  /// Get cached leaderboard
  static List<Map<String, dynamic>>? getCachedLeaderboard(String classId) {
    try {
      final cacheManager = OfflineCacheManager();
      return cacheManager.getCachedLeaderboard(classId);
    } catch (e) {
      return null;
    }
  }

  /// Check if device is online
  static bool isOnline() {
    return ConnectivityService().isOnline;
  }

  /// Listen to connectivity changes
  static Stream<bool> onConnectivityChanged() {
    return ConnectivityService().onConnectivityChanged;
  }
}
