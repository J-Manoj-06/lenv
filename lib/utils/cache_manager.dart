import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/student_model.dart';

/// Manages persistent caching of student data across app restarts
/// Stores data in SharedPreferences with timestamps for validation
class CacheManager {
  static const String _studentDataKey = 'student_cache_data';
  static const String _studentDataTimestampKey = 'student_cache_timestamp';
  static const String _leaderboardDataKey = 'leaderboard_cache_data';
  static const String _leaderboardTimestampKey = 'leaderboard_cache_timestamp';

  /// Cache duration before refresh is recommended (in hours)
  static const int defaultCacheDurationHours = 1;
  static const int leaderboardCacheDurationMinutes =
      5; // 5 minutes for leaderboard

  // ==================== STUDENT DATA CACHE ====================

  /// Cache student profile data
  static Future<void> cacheStudentData(StudentModel student) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentJson = jsonEncode(
        student.toCacheableMap(),
      ); // ✅ Use cacheable map
      await prefs.setString(_studentDataKey, studentJson);
      await prefs.setInt(
        _studentDataTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
    }
  }

  /// Restore cached student data
  static Future<StudentModel?> getStudentDataCache({
    required String studentId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_studentDataKey);
      if (jsonString == null) {
        return null;
      }

      final studentMap = jsonDecode(jsonString) as Map<String, dynamic>;

      // Reconstruct StudentModel from cached Firestore data
      final student = StudentModel(
        uid: studentId,
        email: studentMap['email'] ?? '',
        name: studentMap['name'] ?? '',
        studentId: studentMap['studentId'],
        photoUrl: studentMap['photoUrl'],
        schoolId: studentMap['schoolId'],
        schoolCode: studentMap['schoolCode'],
        schoolName: studentMap['schoolName'],
        className: studentMap['className'],
        section: studentMap['section'],
        phone: studentMap['phone'],
        parentPhone: studentMap['parentPhone'],
        rewardPoints: studentMap['rewardPoints'] ?? 0,
        classRank: studentMap['classRank'] ?? 0,
        monthlyProgress: (studentMap['monthlyProgress'] ?? 0.0).toDouble(),
        monthlyTarget: (studentMap['monthlyTarget'] ?? 90.0).toDouble(),
        pendingTests: studentMap['pendingTests'] ?? 0,
        completedTests: studentMap['completedTests'] ?? 0,
        newNotifications: studentMap['newNotifications'] ?? 0,
        streak: studentMap['streak'] ?? 0,
        lastStreakDate: studentMap['lastStreakDate'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          studentMap['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        ),
        isActive: studentMap['isActive'] ?? true,
      );

      return student;
    } catch (e) {
      return null;
    }
  }

  /// Check if student data cache is still valid (not expired)
  static Future<bool> isStudentDataCacheValid({
    int cacheDurationHours = defaultCacheDurationHours,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_studentDataTimestampKey);
      if (timestamp == null) return false;

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(cacheTime).inHours;

      final isValid = difference < cacheDurationHours;
      return isValid;
    } catch (e) {
      return false;
    }
  }

  /// Clear student data cache
  static Future<void> clearStudentDataCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_studentDataKey);
      await prefs.remove(_studentDataTimestampKey);
    } catch (e) {
    }
  }

  // ==================== TOPPER POINTS CACHE ====================

  /// Cache topper points for a specific class with 5-minute expiration
  /// This dramatically reduces Firestore reads on dashboard loads
  static Future<void> cacheTopperPoints({
    required String schoolId,
    required String className,
    required int points,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'topper_points_${schoolId}_$className';
      final timestampKey = '${cacheKey}_timestamp';

      await prefs.setInt(cacheKey, points);
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
    }
  }

  /// Get cached topper points if still valid (within 5 minutes)
  /// Returns null if cache is expired or doesn't exist
  static Future<int?> getTopperPointsCache({
    required String schoolId,
    required String className,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'topper_points_${schoolId}_$className';
      final timestampKey = '${cacheKey}_timestamp';

      final cachedPoints = prefs.getInt(cacheKey);
      final timestamp = prefs.getInt(timestampKey);

      if (cachedPoints != null && timestamp != null) {
        final age = DateTime.now().millisecondsSinceEpoch - timestamp;
        final ageInMinutes = age / 60000;

        // Cache valid for 5 minutes (300000 milliseconds)
        if (age < 300000) {
          return cachedPoints;
        } else {
        }
      }
    } catch (e) {
    }
    return null;
  }

  /// Clear topper points cache for a specific class
  static Future<void> clearTopperPointsCache({
    required String schoolId,
    required String className,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'topper_points_${schoolId}_$className';
      final timestampKey = '${cacheKey}_timestamp';

      await prefs.remove(cacheKey);
      await prefs.remove(timestampKey);
    } catch (e) {
    }
  }

  // ==================== GENERIC DATA CACHE ====================

  /// Generic cache method for any JSON-serializable data
  static Future<void> cacheData(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(data);
      await prefs.setString(key, jsonString);
      await prefs.setInt(
        '${key}_timestamp',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
    }
  }

  /// Generic restore method for any JSON-serializable data
  static Future<dynamic> getCacheData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(key);
      if (jsonString == null) {
        return null;
      }

      final data = jsonDecode(jsonString);
      return data;
    } catch (e) {
      return null;
    }
  }

  /// Check if cache is valid for a specific key
  static Future<bool> isCacheValid(
    String key, {
    int cacheDurationHours = defaultCacheDurationHours,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('${key}_timestamp');
      if (timestamp == null) return false;

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(cacheTime).inHours;

      return difference < cacheDurationHours;
    } catch (e) {
      return false;
    }
  }

  /// Clear specific cache
  static Future<void> clearCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('${key}_timestamp');
    } catch (e) {
    }
  }

  // ==================== BULK OPERATIONS ====================

  /// Clear ALL application caches (called on logout)
  static Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get all keys
      final keys = prefs.getKeys();

      // Remove cache-related keys
      for (final key in keys) {
        if (key.contains('_cache') || key.contains('_timestamp')) {
          await prefs.remove(key);
        }
      }

    } catch (e) {
    }
  }

  /// Get cache statistics (for debugging)
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final stats = {
        'hasStudentCache': prefs.containsKey(_studentDataKey),
        'studentCacheAge': _getCacheAgeHours(
          prefs.getInt(_studentDataTimestampKey),
        ),
      };

      return stats;
    } catch (e) {
      return {};
    }
  }

  /// Helper to calculate cache age in hours
  static int? _getCacheAgeHours(int? timestamp) {
    if (timestamp == null) return null;
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now().difference(cacheTime).inHours;
  }

  // ==================== LEADERBOARD DATA CACHE ====================

  /// Cache leaderboard data for instant display
  static Future<void> cacheLeaderboardData({
    required String schoolCode,
    required String className,
    required List<Map<String, dynamic>> entries,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${_leaderboardDataKey}_${schoolCode}_$className';
      final timestampKey =
          '${_leaderboardTimestampKey}_${schoolCode}_$className';

      final leaderboardJson = jsonEncode(entries);
      await prefs.setString(cacheKey, leaderboardJson);
      await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
    }
  }

  /// Get cached leaderboard data for instant display
  static Future<List<Map<String, dynamic>>?> getLeaderboardCache({
    required String schoolCode,
    required String className,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '${_leaderboardDataKey}_${schoolCode}_$className';
      final jsonString = prefs.getString(cacheKey);

      if (jsonString == null) {
        return null;
      }

      final List<dynamic> decoded = jsonDecode(jsonString);
      final entries = decoded.map((e) => e as Map<String, dynamic>).toList();
      return entries;
    } catch (e) {
      return null;
    }
  }

  /// Check if leaderboard cache is still valid
  static Future<bool> isLeaderboardCacheValid({
    required String schoolCode,
    required String className,
    int cacheMinutes = leaderboardCacheDurationMinutes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampKey =
          '${_leaderboardTimestampKey}_${schoolCode}_$className';
      final timestamp = prefs.getInt(timestampKey);

      if (timestamp == null) return false;

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      final difference = now.difference(cacheTime).inMinutes;

      return difference < cacheMinutes;
    } catch (e) {
      return false;
    }
  }
}
