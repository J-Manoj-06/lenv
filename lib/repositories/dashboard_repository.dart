import 'package:hive/hive.dart';
import '../models/student_dashboard_data.dart';
import '../services/api_service.dart';
import '../services/network_service.dart';

/// Repository for managing student dashboard data
/// Handles API calls, caching, and offline mode
class DashboardRepository {
  final ApiService _apiService;
  final NetworkService _networkService;
  static const String _boxName = 'student_dashboard_cache';

  DashboardRepository({
    required ApiService apiService,
    required NetworkService networkService,
  }) : _apiService = apiService,
       _networkService = networkService;

  /// Fetch dashboard data with offline support
  /// 1. Check connectivity
  /// 2. If connected, try API call (with timeout)
  /// 3. If API succeeds, cache data and return
  /// 4. If API fails or times out, load from cache
  /// 5. If no cache, return null (show animation screen)
  Future<StudentDashboardData?> fetchDashboardData(String studentId) async {
    // Check if connected to internet
    final isConnected = await _networkService.isConnected();

    if (isConnected) {
      // Try to fetch from API
      final apiData = await _apiService.fetchStudentDashboard(studentId);

      if (apiData != null) {
        // API call succeeded - parse and cache data
        final dashboardData = StudentDashboardData.fromJson(apiData);
        await _cacheDashboardData(studentId, dashboardData);
        return dashboardData;
      } else {
        // API call failed - try to load from cache
        return await _loadFromCache(studentId);
      }
    } else {
      // No internet - load from cache
      return await _loadFromCache(studentId);
    }
  }

  /// Cache dashboard data to Hive
  Future<void> _cacheDashboardData(
    String studentId,
    StudentDashboardData data,
  ) async {
    try {
      final box = await Hive.openBox<StudentDashboardData>(_boxName);
      await box.put(studentId, data);
    } catch (e) {}
  }

  /// Load dashboard data from cache
  Future<StudentDashboardData?> _loadFromCache(String studentId) async {
    try {
      final box = await Hive.openBox<StudentDashboardData>(_boxName);
      final cachedData = box.get(studentId);

      if (cachedData != null) {
        return cachedData;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Clear cache for a specific student
  Future<void> clearCache(String studentId) async {
    try {
      final box = await Hive.openBox<StudentDashboardData>(_boxName);
      await box.delete(studentId);
    } catch (e) {}
  }

  /// Clear all cached data
  Future<void> clearAllCache() async {
    try {
      final box = await Hive.openBox<StudentDashboardData>(_boxName);
      await box.clear();
    } catch (e) {}
  }

  /// Check if cached data exists for a student
  Future<bool> hasCachedData(String studentId) async {
    try {
      final box = await Hive.openBox<StudentDashboardData>(_boxName);
      return box.containsKey(studentId);
    } catch (e) {
      return false;
    }
  }

  /// Get age of cached data in hours
  Future<int?> getCacheAge(String studentId) async {
    try {
      final box = await Hive.openBox<StudentDashboardData>(_boxName);
      final cachedData = box.get(studentId);
      if (cachedData != null) {
        final age = DateTime.now().difference(cachedData.cachedAt);
        return age.inHours;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
