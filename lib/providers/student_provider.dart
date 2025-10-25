import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../services/student_service.dart';

class StudentProvider with ChangeNotifier {
  final StudentService _studentService = StudentService();
  
  StudentModel? _currentStudent;
  DailyChallengeModel? _todayChallenge;
  List<NotificationModel> _notifications = [];
  
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasAttemptedChallenge = false;

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

  // Load student dashboard data
  Future<void> loadDashboardData(String studentId) async {
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
        _hasAttemptedChallenge = await _studentService.hasAttemptedTodayChallenge(studentId);

        // Load notifications
        _notifications = await _studentService.getStudentNotifications(studentId, limit: 20);

        // Update stats
        await _updateStudentStats(studentId);
      }
    } catch (e) {
      _errorMessage = 'Failed to load dashboard: ${e.toString()}';
      print(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update student stats
  Future<void> _updateStudentStats(String studentId) async {
    try {
      final pendingTests = await _studentService.getPendingTestsCount(studentId);
      final monthlyProgress = await _studentService.calculateMonthlyProgress(studentId);
      final unreadCount = await _studentService.getUnreadNotificationCount(studentId);

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
      _notifications = _notifications.map((n) => NotificationModel(
        id: n.id,
        studentId: n.studentId,
        title: n.title,
        message: n.message,
        type: n.type,
        createdAt: n.createdAt,
        isRead: true,
        data: n.data,
      )).toList();
      
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
  void clear() {
    _currentStudent = null;
    _todayChallenge = null;
    _notifications = [];
    _hasAttemptedChallenge = false;
    _errorMessage = null;
    notifyListeners();
  }
}
