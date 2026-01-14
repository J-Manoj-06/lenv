import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student_model.dart';
import '../models/test_result_model.dart';
import '../models/reward_request_model.dart';
import '../models/parent_teacher_group.dart';
import '../services/parent_service.dart';
import '../services/parent_teacher_group_service.dart';

class ParentProvider with ChangeNotifier {
  final ParentService _parentService = ParentService();
  final ParentTeacherGroupService _ptGroupService = ParentTeacherGroupService();

  // SharedPreferences key for persisting selected child
  static const String _selectedChildKey = 'parent_selected_child_uid';

  // Parent information
  String? _parentEmail;
  String? _parentId;

  // Children data
  List<StudentModel> _children = [];
  int _selectedChildIndex = 0;
  bool _isLoadingChildren = false;
  String? _childrenError;

  // Selected child data
  List<TestResultModel> _testResults = [];
  List<RewardRequestModel> _rewardRequests = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _upcomingTests = [];
  List<Map<String, dynamic>> _rewardHistory = [];
  Map<String, dynamic> _performanceStats = {};
  double _attendance = 0.0;
  Map<String, int> _attendanceBreakdown = {
    'present': 0,
    'absent': 0,
    'late': 0,
    'total': 0,
  };

  // Preferences
  bool _notificationsEnabled = true;

  // Loading states
  bool _isLoadingTests = false;
  bool _isLoadingRewards = false;
  bool _isLoadingAnnouncements = false;
  bool _isLoadingConversations = false;
  bool _isLoadingPerformance = false;

  // Error states
  String? _testsError;
  String? _rewardsError;
  String? _announcementsError;
  String? _conversationsError;
  String? _performanceError;
  ParentTeacherGroup? _sectionGroup;
  bool _isLoadingSectionGroup = false;
  String? _sectionGroupError;

  // Getters
  String? get parentEmail => _parentEmail;
  String? get parentId => _parentId;
  List<StudentModel> get children => _children;
  int get selectedChildIndex => _selectedChildIndex;
  bool get isLoadingChildren => _isLoadingChildren;
  String? get childrenError => _childrenError;
  bool get hasChildren => _children.isNotEmpty;

  StudentModel? get selectedChild =>
      _children.isNotEmpty ? _children[_selectedChildIndex] : null;

  List<TestResultModel> get testResults => _testResults;
  List<RewardRequestModel> get rewardRequests => _rewardRequests;
  List<Map<String, dynamic>> get announcements => _announcements;
  List<Map<String, dynamic>> get conversations => _conversations;
  List<Map<String, dynamic>> get upcomingTests => _upcomingTests;
  List<Map<String, dynamic>> get rewardHistory => _rewardHistory;
  Map<String, dynamic> get performanceStats => _performanceStats;
  double get attendance => _attendance;
  Map<String, int> get attendanceBreakdown => _attendanceBreakdown;
  bool get notificationsEnabled => _notificationsEnabled;

  bool get isLoadingTests => _isLoadingTests;
  bool get isLoadingRewards => _isLoadingRewards;
  bool get isLoadingAnnouncements => _isLoadingAnnouncements;
  bool get isLoadingConversations => _isLoadingConversations;
  bool get isLoadingPerformance => _isLoadingPerformance;

  String? get testsError => _testsError;
  String? get rewardsError => _rewardsError;
  String? get announcementsError => _announcementsError;

  // Real-time announcements subscription (aggregated across linked students)
  StreamSubscription<List<Map<String, dynamic>>>? _announcementsSub;
  // Real-time reward requests subscription (aggregated across all children)
  StreamSubscription<List<RewardRequestModel>>? _rewardRequestsSub;
  String? get conversationsError => _conversationsError;
  String? get performanceError => _performanceError;
  ParentTeacherGroup? get sectionGroup => _sectionGroup;
  bool get isLoadingSectionGroup => _isLoadingSectionGroup;
  String? get sectionGroupError => _sectionGroupError;

  /// Initialize parent provider with parent email
  Future<void> initialize(String parentEmail, {String? parentId}) async {
    _parentEmail = parentEmail;
    _parentId = parentId;
    await loadChildren();
    // Start real-time aggregated announcements for this parent
    startParentAnnouncementsStream();
    // Start real-time reward requests stream for all children
    startRewardRequestsStream();
  }

  /// Load all children linked to this parent
  Future<void> loadChildren() async {
    if (_parentEmail == null) {
      return;
    }

    _isLoadingChildren = true;
    _childrenError = null;
    notifyListeners();

    try {
      _children = await _parentService.getChildrenByParentEmail(_parentEmail!);

      // ✅ Load persisted child selection
      await _loadPersistedSelection();

      // Load data for the selected child if available
      if (_children.isNotEmpty) {
        await loadSelectedChildData();
      }
    } catch (e) {
      _childrenError = 'Failed to load children: $e';
    } finally {
      _isLoadingChildren = false;
      notifyListeners();
    }
  }

  /// ✅ Load persisted child selection from SharedPreferences
  Future<void> _loadPersistedSelection() async {
    if (_children.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedChildUid = prefs.getString(_selectedChildKey);

      if (savedChildUid != null) {
        final savedIndex = _children.indexWhere((c) => c.uid == savedChildUid);
        if (savedIndex >= 0) {
          _selectedChildIndex = savedIndex;
        }
      }
    } catch (e) {}
  }

  /// ✅ Persist child selection to SharedPreferences
  Future<void> _persistSelection() async {
    final child = selectedChild;
    if (child == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedChildKey, child.uid);
    } catch (e) {}
  }

  /// Switch to a different child
  /// ✅ ENHANCED: Now persists selection and updates globally
  Future<void> selectChild(int index) async {
    if (index < 0 || index >= _children.length) return;

    _selectedChildIndex = index;
    notifyListeners();

    // ✅ Persist the selection
    await _persistSelection();

    await loadSelectedChildData();
  }

  /// Load all data for the currently selected child
  Future<void> loadSelectedChildData() async {
    final child = selectedChild;
    if (child == null) return;

    // Load all data in parallel
    await Future.wait([
      loadTestResults(child.uid),
      loadRewardRequests(child.uid),
      // Use aggregated parent announcements instead of per-child announcements
      loadParentAnnouncements(),
      loadPerformanceStats(child.uid),
      loadUpcomingTests(child.uid),
      loadRewardHistory(child.uid),
      loadAttendance(child.uid),
      loadSectionGroup(child),
    ]);

    // Load conversations if parent ID is available
    if (_parentId != null) {
      await loadConversations(_parentId!);
    }
  }

  /// Load parent-teacher section group for the current child
  Future<void> loadSectionGroup(StudentModel child) async {
    _isLoadingSectionGroup = true;
    _sectionGroupError = null;
    notifyListeners();

    try {
      _sectionGroup = await _ptGroupService.ensureGroupForChild(child: child);
    } catch (e) {
      _sectionGroupError = 'Failed to load parent-teacher group: $e';
    } finally {
      _isLoadingSectionGroup = false;
      notifyListeners();
    }
  }

  /// Load test results for a student
  Future<void> loadTestResults(String studentId) async {
    _isLoadingTests = true;
    _testsError = null;
    notifyListeners();

    try {
      _testResults = await _parentService.getStudentTestResults(studentId);
    } catch (e) {
      _testsError = 'Failed to load test results: $e';
    } finally {
      _isLoadingTests = false;
      notifyListeners();
    }
  }

  /// Load reward requests for a student (now handled by stream)
  Future<void> loadRewardRequests(String studentId) async {
    // Stream handles this now, but keep for manual refresh
    _isLoadingRewards = true;
    _rewardsError = null;
    notifyListeners();

    try {
      _rewardRequests = await _parentService.getStudentRewardRequests(
        studentId,
      );
    } catch (e) {
      _rewardsError = 'Failed to load reward requests: $e';
    } finally {
      _isLoadingRewards = false;
      notifyListeners();
    }
  }

  /// Load announcements for a student
  Future<void> loadAnnouncements(String studentId) async {
    _isLoadingAnnouncements = true;
    _announcementsError = null;
    notifyListeners();

    try {
      _announcements = await _parentService.getAnnouncementsForStudent(
        studentId,
      );
    } catch (e) {
      _announcementsError = 'Failed to load announcements: $e';
    } finally {
      _isLoadingAnnouncements = false;
      notifyListeners();
    }
  }

  /// Load aggregated announcements for the parent across all linked students
  Future<void> loadParentAnnouncements() async {
    if (_parentEmail == null) return;

    _isLoadingAnnouncements = true;
    _announcementsError = null;
    notifyListeners();

    try {
      _announcements = await _parentService.getAnnouncementsForParentEmail(
        _parentEmail!,
      );

      // Fallback: if aggregated announcements are empty but children are present,
      // load per-child announcements (some parent docs may not contain schoolCode)
      if (_announcements.isEmpty && _children.isNotEmpty) {
        final Map<String, Map<String, dynamic>> merged = {};
        for (final child in _children) {
          try {
            final childAnnouncements = await _parentService
                .getAnnouncementsForStudent(child.uid);
            for (final a in childAnnouncements) {
              merged[a['id'] as String? ?? UniqueKey().toString()] = a;
            }
          } catch (e) {}
        }
        _announcements = merged.values.toList();
      }
    } catch (e) {
      _announcementsError = 'Failed to load parent announcements: $e';
    } finally {
      _isLoadingAnnouncements = false;
      notifyListeners();
    }
  }

  /// Start real-time aggregated announcements stream for the parent
  void startParentAnnouncementsStream() {
    if (_parentEmail == null) return;
    // If already subscribed, do nothing
    if (_announcementsSub != null) return;

    _announcementsSub = _parentService
        .getAnnouncementsStreamForParent(_parentEmail!)
        .listen(
          (list) {
            _announcements = list;
            notifyListeners();
          },
          onError: (e) {
            _announcementsError = 'Parent announcements stream error: $e';
            notifyListeners();
          },
        );
  }

  /// Stop the real-time announcements stream
  Future<void> stopParentAnnouncementsStream() async {
    await _announcementsSub?.cancel();
    _announcementsSub = null;
  }

  /// Load performance statistics for a student
  Future<void> loadPerformanceStats(String studentId) async {
    _isLoadingPerformance = true;
    _performanceError = null;
    notifyListeners();

    try {
      _performanceStats = await _parentService.getStudentPerformanceStats(
        studentId,
      );
    } catch (e) {
      _performanceError = 'Failed to load performance stats: $e';
    } finally {
      _isLoadingPerformance = false;
      notifyListeners();
    }
  }

  /// Load conversations for parent
  Future<void> loadConversations(String parentId) async {
    _isLoadingConversations = true;
    _conversationsError = null;
    notifyListeners();

    try {
      _conversations = await _parentService.getParentConversations(parentId);
    } catch (e) {
      _conversationsError = 'Failed to load conversations: $e';
    } finally {
      _isLoadingConversations = false;
      notifyListeners();
    }
  }

  /// Load upcoming tests for a student
  Future<void> loadUpcomingTests(String studentId) async {
    try {
      _upcomingTests = await _parentService.getUpcomingTests(studentId);
      notifyListeners();
    } catch (e) {}
  }

  /// Load reward history for a student
  Future<void> loadRewardHistory(String studentId) async {
    try {
      _rewardHistory = await _parentService.getStudentRewardHistory(studentId);

      // Derive current reward points from history (handles missing field on student doc)
      final computedPoints = _rewardHistory.fold<int>(0, (sum, entry) {
        final candidates = [
          entry['points'],
          entry['pointsEarned'],
          entry['rewardPoints'],
          entry['delta'],
          entry['amount'],
        ];
        int delta = 0;
        for (final value in candidates) {
          if (value is int) {
            delta = value;
            break;
          }
          if (value is num) {
            delta = value.toInt();
            break;
          }
          if (value is String) {
            final parsed = int.tryParse(value);
            if (parsed != null) {
              delta = parsed;
              break;
            }
          }
        }
        return sum + delta;
      });

      // Update selected child rewardPoints in memory so UI reflects actual total
      if (selectedChild != null && selectedChild!.uid == studentId) {
        final updated = selectedChild!.copyWith(rewardPoints: computedPoints);
        _children[_selectedChildIndex] = updated;
      }

      notifyListeners();
    } catch (e) {}
  }

  /// Load attendance for a student
  Future<void> loadAttendance(String studentId) async {
    try {
      _attendance = await _parentService.getStudentAttendance(studentId);
      _attendanceBreakdown = await _parentService.getStudentAttendanceBreakdown(
        studentId,
      );
      notifyListeners();
    } catch (e) {}
  }

  /// Approve a reward request
  Future<bool> approveRewardRequest(String requestId) async {
    try {
      final success = await _parentService.updateRewardRequestStatus(
        requestId: requestId,
        status: 'approved',
      );

      if (success && selectedChild != null) {
        // Reload reward requests to reflect the change
        await loadRewardRequests(selectedChild!.uid);
      }

      return success;
    } catch (e) {
      return false;
    }
  }

  /// Reject a reward request
  Future<bool> rejectRewardRequest(String requestId, String? reason) async {
    try {
      final success = await _parentService.updateRewardRequestStatus(
        requestId: requestId,
        status: 'rejected',
        parentNote: reason,
      );

      if (success && selectedChild != null) {
        // Reload reward requests to reflect the change
        await loadRewardRequests(selectedChild!.uid);
      }

      return success;
    } catch (e) {
      return false;
    }
  }

  /// Delete a reward request (pending or rejected only)
  Future<bool> deleteRewardRequest(String requestId) async {
    try {
      await _parentService.deleteRewardRequest(requestId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Refresh all data for current child
  Future<void> refresh() async {
    if (selectedChild != null) {
      await loadSelectedChildData();
    }
  }

  /// Clear all data (for logout)
  void clear() {
    _parentEmail = null;
    _parentId = null;
    _children = [];
    _selectedChildIndex = 0;
    _testResults = [];
    _rewardRequests = [];
    _announcements = [];
    _conversations = [];
    _upcomingTests = [];
    _rewardHistory = [];
    _performanceStats = {};
    _attendance = 0.0;
    _attendanceBreakdown = {'present': 0, 'absent': 0, 'late': 0, 'total': 0};
    _childrenError = null;
    _testsError = null;
    _rewardsError = null;
    _announcementsError = null;
    _conversationsError = null;
    _performanceError = null;
    _notificationsEnabled = true;
    // stop any active streams
    stopParentAnnouncementsStream();
    stopRewardRequestsStream();
    notifyListeners();
  }

  /// Start real-time reward requests stream for all children
  void startRewardRequestsStream() {
    if (_children.isEmpty) return;

    final studentIds = _children.map((c) => c.uid).toList();

    _rewardRequestsSub?.cancel();
    _rewardRequestsSub = _parentService
        .getParentRewardRequestsStream(studentIds)
        .listen(
          (requests) {
            _rewardRequests = requests;
            _isLoadingRewards = false;
            notifyListeners();
          },
          onError: (error) {
            _rewardsError = 'Failed to load reward requests: $error';
            _isLoadingRewards = false;
            notifyListeners();
          },
        );
  }

  /// Stop reward requests stream
  void stopRewardRequestsStream() {
    _rewardRequestsSub?.cancel();
    _rewardRequestsSub = null;
  }

  @override
  void dispose() {
    stopParentAnnouncementsStream();
    stopRewardRequestsStream();
    super.dispose();
  }

  /// Toggle notifications preference (local only for now)
  void setNotificationsEnabled(bool enabled) {
    _notificationsEnabled = enabled;
    notifyListeners();
  }

  /// Get pending reward requests count
  int get pendingRewardRequestsCount {
    return _rewardRequests
        .where((r) => r.status == 'pending' || r.status == 'requested')
        .length;
  }

  /// Get completed tests count
  int get completedTestsCount {
    return _testResults.length; // All testResults are completed
  }

  /// Get unread announcements count
  int get unreadAnnouncementsCount {
    return _announcements.where((a) => a['isUnread'] == true).length;
  }
}
