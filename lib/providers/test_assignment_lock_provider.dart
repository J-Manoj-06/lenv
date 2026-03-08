import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/test_assignment_lock.dart';
import '../services/test_assignment_lock_service.dart';

/// Manages real-time test-assignment lock state for teacher screens.
///
/// Usage:
/// ```dart
/// // Start watching when class+subject are picked:
/// context.read<TestAssignmentLockProvider>().watchLock(
///   instituteId: 'inst_123',
///   classId: 'Grade 10',
///   subjectId: 'Mathematics',
/// );
///
/// // Before saving a test:
/// final ok = await context.read<TestAssignmentLockProvider>().acquireLock(
///   instituteId: ..., classId: ..., subjectId: ...,
///   teacherId: ..., teacherName: ...,
///   nextAvailableTimestamp: testEndDate,
/// );
/// ```
class TestAssignmentLockProvider with ChangeNotifier {
  final TestAssignmentLockService _service = TestAssignmentLockService();

  // ── State ──────────────────────────────────────────────────────────────────
  TestAssignmentLock? _currentLock;
  bool _isChecking = false;
  String? _errorMessage;

  // ── Watch context ──────────────────────────────────────────────────────────
  String? _watchedInstituteId;
  String? _watchedClassId;
  String? _watchedSectionId;
  StreamSubscription<TestAssignmentLock?>? _sub;

  // ── Public getters ─────────────────────────────────────────────────────────

  /// The active lock, or `null` when no lock / lock expired.
  TestAssignmentLock? get currentLock => _currentLock;

  /// `true` while the initial lock check is in flight.
  bool get isChecking => _isChecking;

  /// `true` when ANY active lock exists (including the current teacher's own).
  bool get isLocked => _currentLock != null && _currentLock!.isActive;

  /// `true` only when a *different* teacher holds the active lock.
  bool isLockedForOther(String currentTeacherId) =>
      isLocked && _currentLock!.teacherId != currentTeacherId;

  /// Returns the active lock only when it belongs to a different teacher.
  /// Returns null if the current teacher owns the lock (or no lock exists).
  TestAssignmentLock? lockForOther(String currentTeacherId) =>
      isLockedForOther(currentTeacherId) ? _currentLock : null;

  String? get errorMessage => _errorMessage;

  // ── Watch ──────────────────────────────────────────────────────────────────

  /// Starts a real-time listener for the given class+subject combination.
  ///
  /// Calling again with the same arguments is a no-op.
  void watchLock({
    required String instituteId,
    required String classId,
    required String sectionId,
  }) {
    // Skip if already watching the same combination.
    if (_watchedInstituteId == instituteId &&
        _watchedClassId == classId &&
        _watchedSectionId == sectionId) {
      return;
    }

    _watchedInstituteId = instituteId;
    _watchedClassId = classId;
    _watchedSectionId = sectionId;
    _currentLock = null;
    _isChecking = true;
    _errorMessage = null;
    notifyListeners();

    _sub?.cancel();
    _sub = _service
        .streamLock(
          instituteId: instituteId,
          classId: classId,
          sectionId: sectionId,
        )
        .listen(
          (lock) {
            _currentLock = lock;
            _isChecking = false;
            notifyListeners();
          },
          onError: (Object e) {
            _errorMessage = e.toString();
            _isChecking = false;
            notifyListeners();
          },
        );
  }

  /// Stops the current listener and clears all lock state.
  void stopWatching() {
    _sub?.cancel();
    _sub = null;
    _currentLock = null;
    _watchedInstituteId = null;
    _watchedClassId = null;
    _watchedSectionId = null;
    _isChecking = false;
    notifyListeners();
  }

  // ── Acquire ────────────────────────────────────────────────────────────────

  /// Tries to acquire the lock for the current teacher before assigning a test.
  ///
  /// Returns `true` on success.
  /// Returns `false` and updates [currentLock] when another teacher already
  /// holds the lock.
  Future<bool> acquireLock({
    required String instituteId,
    required String classId,
    required String sectionId,
    required String subjectName,
    required String teacherId,
    required String teacherName,
    DateTime? nextAvailableTimestamp,
  }) async {
    try {
      final lock = await _service.acquireLock(
        instituteId: instituteId,
        classId: classId,
        sectionId: sectionId,
        subjectName: subjectName,
        teacherId: teacherId,
        teacherName: teacherName,
        nextAvailableTimestamp: nextAvailableTimestamp,
      );
      // Update local state immediately (stream will also fire shortly).
      _currentLock = lock;
      notifyListeners();
      return true;
    } on TestAssignmentLockException catch (lockEx) {
      _currentLock = lockEx.existingLock;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      // Refresh from server to get current state.
      if (_watchedClassId != null && _watchedSectionId != null) {
        final fresh = await _service.fetchLock(
          instituteId: instituteId,
          classId: classId,
          sectionId: sectionId,
        );
        _currentLock = fresh;
      }
      notifyListeners();
      return false;
    }
  }

  // ── Release ────────────────────────────────────────────────────────────────

  /// Releases the lock (called when test creation fails after lock acquired).
  Future<void> releaseLock({
    required String instituteId,
    required String classId,
    required String sectionId,
    required String teacherId,
  }) async {
    await _service.releaseLock(
      instituteId: instituteId,
      classId: classId,
      sectionId: sectionId,
      teacherId: teacherId,
    );
    // Stream will push null shortly; clear locally for instant feedback.
    if (_currentLock?.teacherId == teacherId) {
      _currentLock = null;
      notifyListeners();
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
