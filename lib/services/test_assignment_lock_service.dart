import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/test_assignment_lock.dart';

/// Handles Firestore read/write operations for [TestAssignmentLock].
///
/// Document path: `test_assignment_locks/{docId}`
/// Document ID format: `{instituteId}__{normalizedClass}__{normalizedSection}`
/// One lock per class+section blocks ALL subjects simultaneously.
class TestAssignmentLockService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'test_assignment_locks';

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds a deterministic, URL-safe document ID scoped to a given institute.
  /// Keyed by class + section (NOT subject) so the lock covers all subjects.
  String docId({
    required String instituteId,
    required String classId,
    required String sectionId,
  }) {
    String normalize(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return '${normalize(instituteId)}__${normalize(classId)}__sec_${normalize(sectionId)}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Read
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a real-time stream of the active lock (null when no active lock).
  Stream<TestAssignmentLock?> streamLock({
    required String instituteId,
    required String classId,
    required String sectionId,
  }) {
    final id = docId(
      instituteId: instituteId,
      classId: classId,
      sectionId: sectionId,
    );
    return _db
        .collection(_collection)
        .doc(id)
        .snapshots()
        .map((snap) {
          if (!snap.exists || snap.data() == null) return null;
          final lock = TestAssignmentLock.fromJson(snap.data()!, snap.id);
          // Treat as expired if past nextAvailableTimestamp
          return lock.isActive ? lock : null;
        })
        .handleError((Object e) {
          debugPrint('⚠️ TestAssignmentLockService streamLock error: $e');
          return null;
        });
  }

  /// One-time fetch of the current active lock.
  Future<TestAssignmentLock?> fetchLock({
    required String instituteId,
    required String classId,
    required String sectionId,
  }) async {
    try {
      final snap = await _db
          .collection(_collection)
          .doc(
            docId(
              instituteId: instituteId,
              classId: classId,
              sectionId: sectionId,
            ),
          )
          .get();
      if (!snap.exists || snap.data() == null) return null;
      final lock = TestAssignmentLock.fromJson(snap.data()!, snap.id);
      return lock.isActive ? lock : null;
    } catch (e) {
      debugPrint('⚠️ TestAssignmentLockService fetchLock error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write
  // ─────────────────────────────────────────────────────────────────────────

  /// Tries to acquire the lock for [teacherId].
  ///
  /// Uses a Firestore transaction to prevent race conditions.
  ///
  /// - If no active lock exists, creates one and returns the new lock.
  /// - If the requesting teacher already holds the lock, refreshes it.
  /// - If another teacher holds an active lock, throws
  ///   `TestAssignmentLockException`.
  Future<TestAssignmentLock> acquireLock({
    required String instituteId,
    required String classId,
    required String sectionId,
    required String subjectName,
    required String teacherId,
    required String teacherName,

    /// If null, defaults to today 8:00 PM (or 3 h from now if already past 8 PM).
    DateTime? nextAvailableTimestamp,
  }) async {
    final id = docId(
      instituteId: instituteId,
      classId: classId,
      sectionId: sectionId,
    );
    final docRef = _db.collection(_collection).doc(id);
    final now = DateTime.now();

    // Default nextAvailable = today 8 PM, or +3h if already past 8 PM.
    final today8pm = DateTime(now.year, now.month, now.day, 20, 0, 0);
    final defaultNext = now.isBefore(today8pm)
        ? today8pm
        : now.add(const Duration(hours: 3));
    final nextAvail = nextAvailableTimestamp ?? defaultNext;

    late TestAssignmentLock createdLock;

    await _db.runTransaction((txn) async {
      final snap = await txn.get(docRef);

      if (snap.exists && snap.data() != null) {
        final existing = TestAssignmentLock.fromJson(snap.data()!, snap.id);
        if (existing.isActive && existing.teacherId != teacherId) {
          // Another teacher holds an active lock – abort.
          throw TestAssignmentLockException(existing);
        }
      }

      createdLock = TestAssignmentLock(
        id: id,
        classId: classId,
        sectionId: sectionId,
        subjectName: subjectName,
        assignedByTeacherName: teacherName,
        teacherId: teacherId,
        assignedAtTimestamp: now,
        nextAvailableTimestamp: nextAvail,
        isLocked: true,
      );
      txn.set(docRef, createdLock.toJson());
    });

    return createdLock;
  }

  /// Releases the lock if it is owned by [teacherId].
  Future<void> releaseLock({
    required String instituteId,
    required String classId,
    required String sectionId,
    required String teacherId,
  }) async {
    try {
      final docRef = _db
          .collection(_collection)
          .doc(
            docId(
              instituteId: instituteId,
              classId: classId,
              sectionId: sectionId,
            ),
          );
      final snap = await docRef.get();
      if (snap.exists && snap.data()?['teacherId'] == teacherId) {
        await docRef.delete();
        debugPrint('🔓 Lock released for $classId / Section $sectionId');
      }
    } catch (e) {
      debugPrint('⚠️ TestAssignmentLockService releaseLock error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exception
// ─────────────────────────────────────────────────────────────────────────────

/// Thrown when an active lock held by another teacher prevents acquisition.
class TestAssignmentLockException implements Exception {
  final TestAssignmentLock existingLock;
  const TestAssignmentLockException(this.existingLock);

  @override
  String toString() =>
      'TestAssignmentLockException: ${existingLock.assignedByTeacherName} '
      'already holds the lock until ${existingLock.nextAvailableTimestamp}';
}
