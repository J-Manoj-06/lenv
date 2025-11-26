import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/student_model.dart';
import '../models/test_result_model.dart';
import '../models/reward_request_model.dart';
import '../services/parent_service.dart';

class ParentProvider with ChangeNotifier {
  final ParentService _parentService = ParentService();

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
  String? get conversationsError => _conversationsError;
  String? get performanceError => _performanceError;

  /// Initialize parent provider with parent email
  Future<void> initialize(String parentEmail, {String? parentId}) async {
    _parentEmail = parentEmail;
    _parentId = parentId;
    await loadChildren();
    // Start real-time aggregated announcements for this parent
    startParentAnnouncementsStream();
  }

  /// Load all children linked to this parent
  Future<void> loadChildren() async {
    if (_parentEmail == null) {
      print('⚠️ ParentProvider: No parent email set');
      return;
    }

    _isLoadingChildren = true;
    _childrenError = null;
    notifyListeners();

    try {
      print('📥 ParentProvider: Loading children for $_parentEmail');
      _children = await _parentService.getChildrenByParentEmail(_parentEmail!);
      print('✅ ParentProvider: Loaded ${_children.length} children');

      // Load data for the first child if available
      if (_children.isNotEmpty) {
        await loadSelectedChildData();
      }
    } catch (e) {
      _childrenError = 'Failed to load children: $e';
      print('❌ ParentProvider Error: $_childrenError');
    } finally {
      _isLoadingChildren = false;
      notifyListeners();
    }
  }

  /// Switch to a different child
  Future<void> selectChild(int index) async {
    if (index < 0 || index >= _children.length) return;

    _selectedChildIndex = index;
    notifyListeners();

    await loadSelectedChildData();
  }

  /// Load all data for the currently selected child
  Future<void> loadSelectedChildData() async {
    final child = selectedChild;
    if (child == null) return;

    print('📥 Loading data for child: ${child.name}');
    print('  - Child UID: ${child.uid}');
    print('  - Child rewardPoints: ${child.rewardPoints}');
    print('  - Child className: ${child.className}');
    print('  - Child schoolCode: ${child.schoolCode}');

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
    ]);

    // Load conversations if parent ID is available
    if (_parentId != null) {
      await loadConversations(_parentId!);
    }
  }

  /// Load test results for a student
  Future<void> loadTestResults(String studentId) async {
    _isLoadingTests = true;
    _testsError = null;
    notifyListeners();

    try {
      _testResults = await _parentService.getStudentTestResults(studentId);
      print('✅ Loaded ${_testResults.length} test results');
    } catch (e) {
      _testsError = 'Failed to load test results: $e';
      print('❌ Error loading test results: $e');
    } finally {
      _isLoadingTests = false;
      notifyListeners();
    }
  }

  /// Load reward requests for a student
  Future<void> loadRewardRequests(String studentId) async {
    _isLoadingRewards = true;
    _rewardsError = null;
    notifyListeners();

    try {
      _rewardRequests = await _parentService.getStudentRewardRequests(
        studentId,
      );
      print('✅ Loaded ${_rewardRequests.length} reward requests');
    } catch (e) {
      _rewardsError = 'Failed to load reward requests: $e';
      print('❌ Error loading reward requests: $e');
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
      print('✅ Loaded ${_announcements.length} announcements');
    } catch (e) {
      _announcementsError = 'Failed to load announcements: $e';
      print('❌ Error loading announcements: $e');
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
      print(
        '✅ Loaded aggregated parent announcements: ${_announcements.length}',
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
          } catch (e) {
            print('❌ Error loading announcements for child ${child.uid}: $e');
          }
        }
        _announcements = merged.values.toList();
        print(
          '✅ Loaded fallback per-child announcements: ${_announcements.length}',
        );
      }
    } catch (e) {
      _announcementsError = 'Failed to load parent announcements: $e';
      print('❌ Error loading parent announcements: $e');
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
      print('✅ Loaded performance stats: $_performanceStats');
      print('  - completedTests: ${_performanceStats['completedTests']}');
      print('  - totalTests: ${_performanceStats['totalTests']}');
      print('  - averageScore: ${_performanceStats['averageScore']}');
    } catch (e) {
      _performanceError = 'Failed to load performance stats: $e';
      print('❌ Error loading performance stats: $e');
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
      print('✅ Loaded ${_conversations.length} conversations');
    } catch (e) {
      _conversationsError = 'Failed to load conversations: $e';
      print('❌ Error loading conversations: $e');
    } finally {
      _isLoadingConversations = false;
      notifyListeners();
    }
  }

  /// Load upcoming tests for a student
  Future<void> loadUpcomingTests(String studentId) async {
    try {
      _upcomingTests = await _parentService.getUpcomingTests(studentId);
      print('✅ Loaded ${_upcomingTests.length} upcoming tests');
      notifyListeners();
    } catch (e) {
      print('❌ Error loading upcoming tests: $e');
    }
  }

  /// Load reward history for a student
  Future<void> loadRewardHistory(String studentId) async {
    try {
      _rewardHistory = await _parentService.getStudentRewardHistory(studentId);
      print('✅ Loaded ${_rewardHistory.length} reward history items');
      notifyListeners();
    } catch (e) {
      print('❌ Error loading reward history: $e');
    }
  }

  /// Load attendance for a student
  Future<void> loadAttendance(String studentId) async {
    try {
      print('🔄 Loading attendance for student: $studentId');
      _attendance = await _parentService.getStudentAttendance(studentId);
      _attendanceBreakdown = await _parentService.getStudentAttendanceBreakdown(
        studentId,
      );
      print('✅ Loaded attendance: $_attendance%');
      print(
        '✅ Breakdown: present=${_attendanceBreakdown['present']}, absent=${_attendanceBreakdown['absent']}, late=${_attendanceBreakdown['late']}, total=${_attendanceBreakdown['total']}',
      );
      notifyListeners();
    } catch (e) {
      print('❌ Error loading attendance: $e');
    }
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
      print('❌ Error approving reward request: $e');
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
      print('❌ Error rejecting reward request: $e');
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
    notifyListeners();
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
