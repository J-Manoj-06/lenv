import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../services/student_service.dart';
import '../utils/cache_manager.dart';

class StudentProvider with ChangeNotifier {
  final StudentService _studentService = StudentService();

  StudentModel? _currentStudent;
  DailyChallengeModel? _todayChallenge;
  List<NotificationModel> _notifications = [];

  bool _isLoading = false;
  String? _errorMessage;
  bool _hasAttemptedChallenge = false;
  bool _hasLoaded = false; // Prevent duplicate loads

  // Getters
  StudentModel? get currentStudent => _currentStudent;
  DailyChallengeModel? get todayChallenge => _todayChallenge;
  List<NotificationModel> get notifications => _notifications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasAttemptedChallenge => _hasAttemptedChallenge;

  int get unreadNotificationCount {
    return _notifications.where((n) => !n.isRead).length;
  }

  // Set current student from cache immediately (no async, just notify listeners)
  void setCurrentStudentFromCache(StudentModel student) {
    _currentStudent = student;
    notifyListeners();
    print('📱 StudentProvider: Cached student set: ${student.name}');
  }

  // Load student dashboard data
  Future<void> loadDashboardData(String studentId) async {
    // Skip if already loaded to prevent flickering (but check if same student)
    if (_hasLoaded &&
        _currentStudent != null &&
        _currentStudent!.uid == studentId) {
      print('🔄 Dashboard already loaded for student: $studentId - skipping');
      return;
    }

    // Force reload on user switch
    print('🚀 Starting loadDashboardData for student: $studentId');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Step 1: Try to load from cache first (instant UI update)
      print('📦 Attempting to load from cache...');
      final cachedStudent = await CacheManager.getStudentDataCache(
        studentId: studentId,
      );
      if (cachedStudent != null) {
        _currentStudent = cachedStudent;
        notifyListeners(); // Show cached data immediately
        print('✅ Loaded student data from cache: ${cachedStudent.name}');
      }

      // Step 2: Load from Firestore with timeout
      print('🔥 Loading from Firestore...');
      try {
        _currentStudent = await _studentService.getCurrentStudent().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏱️ Firestore fetch timed out after 10 seconds');
            return _currentStudent; // Use cached data if timeout
          },
        );
      } catch (e) {
        print('❌ Firestore fetch error: $e');
        if (_currentStudent == null) rethrow; // Only rethrow if no cached data
        print('✅ Using cached data due to fetch error');
      }
      print('✅ Firestore fetch complete: ${_currentStudent?.name ?? "null"}');

      if (_currentStudent != null) {
        // Cache the fresh data
        print('💾 Caching fresh student data...');
        await CacheManager.cacheStudentData(_currentStudent!);
        print('✅ Cache saved');

        // Load today's challenge
        print('📚 Loading today\'s challenge...');
        _todayChallenge = await _studentService.getTodayChallenge();
        print(
          '✅ Challenge loaded: ${_todayChallenge?.question ?? "no challenge"}',
        );

        // Check if student has attempted today's challenge
        print('✅ Checking if student attempted challenge...');
        _hasAttemptedChallenge = await _studentService
            .hasAttemptedTodayChallenge(studentId);
        print('✅ Attempt status: $_hasAttemptedChallenge');

        // Load notifications
        print('🔔 Loading notifications...');
        _notifications = await _studentService.getStudentNotifications(
          studentId,
          limit: 20,
        );
        print('✅ Notifications loaded: ${_notifications.length} items');

        // Update stats
        print('📊 Updating student stats...');
        await _updateStudentStats(studentId);
        print('✅ Stats updated');

        _hasLoaded = true; // Mark as loaded
        print('✅ Dashboard data loading COMPLETE');
      } else {
        print('⚠️ Firestore returned null for current student');
      }
    } catch (e) {
      _errorMessage = 'Failed to load dashboard: ${e.toString()}';
      print('❌ ERROR in loadDashboardData: $_errorMessage');

      // If Firestore fails, at least we have cache
      if (_currentStudent == null) {
        print('🔄 Attempting fallback to cached data...');
        final cachedStudent = await CacheManager.getStudentDataCache(
          studentId: studentId,
        );
        if (cachedStudent != null) {
          _currentStudent = cachedStudent;
          print('⚠️ Using cached data (offline mode)');
        }
      }
    } finally {
      _isLoading = false;
      notifyListeners();
      print('✅ notifyListeners() called - _isLoading set to false');
    }
  }

  // Force refresh student data (bypasses _hasLoaded check)
  Future<void> forceRefreshStudentData(String studentId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Load student data
      _currentStudent = await _studentService.getCurrentStudent();

      if (_currentStudent != null) {
        // Load today's challenge
        _todayChallenge = await _studentService.getTodayChallenge();

        // Check if student has attempted today's challenge
        _hasAttemptedChallenge = await _studentService
            .hasAttemptedTodayChallenge(studentId);

        // Load notifications
        _notifications = await _studentService.getStudentNotifications(
          studentId,
          limit: 20,
        );

        // Update stats
        await _updateStudentStats(studentId);
      }
    } catch (e) {
      _errorMessage = 'Failed to refresh data: ${e.toString()}';
      print(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Refresh only student data (lightweight - just updates streak in UI)
  Future<void> refreshStudentStreak(String studentId) async {
    try {
      // Only fetch current student - no full reload
      _currentStudent = await _studentService.getCurrentStudent();
      notifyListeners();
    } catch (e) {
      print('Error refreshing streak: $e');
    }
  }

  // Update student stats
  Future<void> _updateStudentStats(String studentId) async {
    try {
      final pendingTests = await _studentService.getPendingTestsCount(
        studentId,
      );
      final monthlyProgress = await _studentService.calculateMonthlyProgress(
        studentId,
      );
      final unreadCount = await _studentService.getUnreadNotificationCount(
        studentId,
      );

      await _studentService.updateStudentStats(
        uid: studentId,
        pendingTests: pendingTests,
        monthlyProgress: monthlyProgress,
        newNotifications: unreadCount,
      );

      // Reload student data
      _currentStudent = await _studentService.getCurrentStudent();
      notifyListeners();
    } catch (e) {
      print('Error updating stats: $e');
    }
  }

  // Submit daily challenge answer
  Future<bool> submitChallengeAnswer(String studentId, String answer) async {
    if (_todayChallenge == null) return false;

    try {
      final isCorrect = await _studentService.submitChallengeAnswer(
        studentId: studentId,
        challengeId: _todayChallenge!.id,
        answer: answer,
      );

      _hasAttemptedChallenge = true;

      // Reload student data to update points
      if (isCorrect) {
        _currentStudent = await _studentService.getCurrentStudent();
      }

      notifyListeners();
      return isCorrect;
    } catch (e) {
      print('Error submitting answer: $e');
      return false;
    }
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _studentService.markNotificationAsRead(notificationId);

      // Update local notifications
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        _notifications[index] = NotificationModel(
          id: _notifications[index].id,
          studentId: _notifications[index].studentId,
          title: _notifications[index].title,
          message: _notifications[index].message,
          type: _notifications[index].type,
          createdAt: _notifications[index].createdAt,
          isRead: true,
          data: _notifications[index].data,
        );
        notifyListeners();
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String studentId) async {
    try {
      await _studentService.markAllNotificationsAsRead(studentId);

      // Update local notifications
      _notifications = _notifications
          .map(
            (n) => NotificationModel(
              id: n.id,
              studentId: n.studentId,
              title: n.title,
              message: n.message,
              type: n.type,
              createdAt: n.createdAt,
              isRead: true,
              data: n.data,
            ),
          )
          .toList();

      notifyListeners();
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  // Refresh data
  Future<void> refresh(String studentId) async {
    await loadDashboardData(studentId);
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Clear all data (logout)
  Future<void> clear() async {
    _currentStudent = null;
    _todayChallenge = null;
    _notifications = [];
    _hasAttemptedChallenge = false;
    _errorMessage = null;
    _hasLoaded = false; // Reset load flag

    // Clear cached student data on logout
    await CacheManager.clearStudentDataCache();

    notifyListeners();
  }
}
