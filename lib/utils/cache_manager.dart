import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/student_model.dart';

/// Manages persistent caching of student data across app restarts
/// Stores data in SharedPreferences with timestamps for validation
class CacheManager {
  static const String _studentDataKey = 'student_cache_data';
  static const String _studentDataTimestampKey = 'student_cache_timestamp';

  /// Cache duration before refresh is recommended (in hours)
  static const int defaultCacheDurationHours = 1;

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
      print('✅ Student data cached successfully');
    } catch (e) {
      print('❌ Error caching student data: $e');
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
        print('📝 No cached student data found');
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

      print('✅ Restored student data from cache');
      return student;
    } catch (e) {
      print('❌ Error restoring student data: $e');
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
      print(
        '📊 Student cache age: ${difference}h, valid: $isValid (threshold: ${cacheDurationHours}h)',
      );
      return isValid;
    } catch (e) {
      print('❌ Error checking cache validity: $e');
      return false;
    }
  }

  /// Clear student data cache
  static Future<void> clearStudentDataCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_studentDataKey);
      await prefs.remove(_studentDataTimestampKey);
      print('✅ Student data cache cleared');
    } catch (e) {
      print('❌ Error clearing student data cache: $e');
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
      print('✅ Topper points cached: $points for class $className');
    } catch (e) {
      print('❌ Error caching topper points: $e');
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
          print(
            '✅ Using cached topper points: $cachedPoints (age: ${ageInMinutes.toStringAsFixed(1)}m)',
          );
          return cachedPoints;
        } else {
          print(
            '⏰ Topper points cache expired (age: ${ageInMinutes.toStringAsFixed(1)}m)',
          );
        }
      }
    } catch (e) {
      print('❌ Error getting topper cache: $e');
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
      print('✅ Topper points cache cleared for class $className');
    } catch (e) {
      print('❌ Error clearing topper cache: $e');
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
      print('✅ Data cached for key: $key');
    } catch (e) {
      print('❌ Error caching data for key $key: $e');
    }
  }

  /// Generic restore method for any JSON-serializable data
  static Future<dynamic> getCacheData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(key);
      if (jsonString == null) {
        print('📝 No cached data found for key: $key');
        return null;
      }

      final data = jsonDecode(jsonString);
      print('✅ Restored data from cache for key: $key');
      return data;
    } catch (e) {
      print('❌ Error restoring data for key $key: $e');
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
      print('❌ Error checking cache validity for key $key: $e');
      return false;
    }
  }

  /// Clear specific cache
  static Future<void> clearCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('${key}_timestamp');
      print('✅ Cache cleared for key: $key');
    } catch (e) {
      print('❌ Error clearing cache for key $key: $e');
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

      print('✅ All application caches cleared');
    } catch (e) {
      print('❌ Error clearing all caches: $e');
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
      print('❌ Error getting cache stats: $e');
      return {};
    }
  }

  /// Helper to calculate cache age in hours
  static int? _getCacheAgeHours(int? timestamp) {
    if (timestamp == null) return null;
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateTime.now().difference(cacheTime).inHours;
  }
}
