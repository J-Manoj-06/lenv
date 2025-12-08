import 'package:cloud_firestore/cloud_firestore.dart';

/// Optimized service for teacher_groups collection
/// Replaces expensive classes collection scanning
class TeacherGroupsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ Cache with 5-minute TTL
  Map<String, dynamic>? _cachedTeacherGroups;
  DateTime? _cacheTimestamp;
  String? _cachedTeacherId;

  /// Check if cache is valid (5 minutes)
  bool _isCacheValid(String teacherId) {
    if (_cachedTeacherId != teacherId) return false;
    if (_cacheTimestamp == null || _cachedTeacherGroups == null) return false;
    return DateTime.now().difference(_cacheTimestamp!).inMinutes < 5;
  }

  /// Clear cache (call after sending message or on logout)
  void clearCache() {
    _cachedTeacherGroups = null;
    _cacheTimestamp = null;
    _cachedTeacherId = null;
  }

  /// Get teacher's groups from teacher_groups collection
  /// ✅ OPTIMIZATION: 1 read instead of scanning all classes (50+ reads)
  Future<Map<String, dynamic>?> getTeacherGroups(String teacherId) async {
    try {
      // Return cached data if valid
      if (_isCacheValid(teacherId)) {
        print('📦 Using cached teacher_groups data');
        return _cachedTeacherGroups;
      }

      print('🔍 Fetching teacher_groups for: $teacherId');

      final doc = await _firestore
          .collection('teacher_groups')
          .doc(teacherId)
          .get();

      if (!doc.exists || doc.data() == null) {
        print('⚠️ teacher_groups document not found for teacher: $teacherId');
        return null;
      }

      final data = doc.data()!;

      // Cache the result
      _cachedTeacherGroups = data;
      _cacheTimestamp = DateTime.now();
      _cachedTeacherId = teacherId;

      print('✅ Fetched ${(data['groupIds'] as List?)?.length ?? 0} groups');
      return data;
    } catch (e) {
      print('❌ Error fetching teacher_groups: $e');
      return null;
    }
  }

  /// Get teacher's groups with real-time updates
  /// ✅ OPTIMIZATION: 1 snapshot listener instead of polling
  Stream<Map<String, dynamic>?> getTeacherGroupsStream(String teacherId) {
    return _firestore
        .collection('teacher_groups')
        .doc(teacherId)
        .snapshots()
        .map((snapshot) {
          if (!snapshot.exists || snapshot.data() == null) {
            return null;
          }
          return snapshot.data();
        });
  }

  /// Mark group as read (update unread count to 0)
  /// Called when teacher opens a group chat
  Future<void> markGroupAsRead(String teacherId, String groupId) async {
    try {
      await _firestore.collection('teacher_groups').doc(teacherId).update({
        'unreadCounts.$groupId': 0,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update local cache
      if (_cachedTeacherGroups != null && _cachedTeacherId == teacherId) {
        final unreadCounts =
            _cachedTeacherGroups!['unreadCounts'] as Map<String, dynamic>? ??
            {};
        unreadCounts[groupId] = 0;
        _cachedTeacherGroups!['unreadCounts'] = unreadCounts;
      }

      print('✅ Marked group as read: $groupId');
    } catch (e) {
      print('❌ Error marking group as read: $e');
    }
  }

  /// Increment unread count for a group
  /// Called when a new message is received (from Cloud Function ideally)
  Future<void> incrementUnreadCount(String teacherId, String groupId) async {
    try {
      await _firestore.collection('teacher_groups').doc(teacherId).update({
        'unreadCounts.$groupId': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Invalidate cache to force refresh
      if (_cachedTeacherId == teacherId) {
        clearCache();
      }

      print('✅ Incremented unread count for group: $groupId');
    } catch (e) {
      print('❌ Error incrementing unread count: $e');
    }
  }

  /// Get unread count for a specific group
  /// ✅ OPTIMIZATION: Read from cached data, no extra query
  int getUnreadCountForGroup(String groupId) {
    if (_cachedTeacherGroups == null) return 0;

    final unreadCounts =
        _cachedTeacherGroups!['unreadCounts'] as Map<String, dynamic>?;
    if (unreadCounts == null) return 0;

    return (unreadCounts[groupId] as num?)?.toInt() ?? 0;
  }

  /// Get total unread count across all groups
  /// ✅ OPTIMIZATION: Calculate from cached data
  int getTotalUnreadCount() {
    if (_cachedTeacherGroups == null) return 0;

    final unreadCounts =
        _cachedTeacherGroups!['unreadCounts'] as Map<String, dynamic>?;
    if (unreadCounts == null) return 0;

    int total = 0;
    for (final count in unreadCounts.values) {
      if (count is num) {
        total += count.toInt();
      }
    }
    return total;
  }

  /// Parse groups from teacher_groups document
  List<Map<String, dynamic>> parseGroups(Map<String, dynamic>? data) {
    if (data == null) return [];

    final classes = data['classes'] as List<dynamic>?;
    if (classes == null) return [];

    return classes
        .whereType<Map<String, dynamic>>()
        .map(
          (classData) => {
            'classId': classData['classId'] ?? '',
            'className': classData['className'] ?? 'Unknown Class',
            'section': classData['section'] ?? '',
            'subject': classData['subject'] ?? '',
            'subjectId': classData['subjectId'] ?? '',
            'groupId': classData['groupId'] ?? '',
          },
        )
        .toList();
  }

  /// Rebuild teacher_groups index (fallback if data is missing)
  /// This should ideally be done server-side
  Future<bool> rebuildTeacherGroupsIndex(String teacherId) async {
    try {
      print('🔄 Rebuilding teacher_groups index for: $teacherId');

      // Scan classes to find teacher's subjects
      final classesSnapshot = await _firestore.collection('classes').get();

      List<Map<String, dynamic>> classes = [];
      List<String> groupIds = [];
      Map<String, int> unreadCounts = {};

      for (var classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final subjectTeachers =
            classData['subjectTeachers'] as Map<String, dynamic>?;

        if (subjectTeachers == null) continue;

        for (var entry in subjectTeachers.entries) {
          final subject = entry.key;
          final teacherData = entry.value as Map<String, dynamic>?;

          if (teacherData?['teacherId'] == teacherId) {
            final subjectId = subject.toLowerCase().replaceAll(' ', '_');
            final groupId = '${classDoc.id}_$subjectId';

            classes.add({
              'classId': classDoc.id,
              'className': classData['className'] ?? 'Unknown',
              'section': classData['section'] ?? '',
              'subject': subject,
              'subjectId': subjectId,
              'groupId': groupId,
            });

            groupIds.add(groupId);
            unreadCounts[groupId] = 0;
          }
        }
      }

      // Write to teacher_groups collection
      await _firestore.collection('teacher_groups').doc(teacherId).set({
        'teacherId': teacherId,
        'groupIds': groupIds,
        'classes': classes,
        'unreadCounts': unreadCounts,
        'lastUpdated': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Clear cache to force refresh
      clearCache();

      print('✅ Rebuilt teacher_groups index: ${classes.length} groups');
      return true;
    } catch (e) {
      print('❌ Error rebuilding teacher_groups index: $e');
      return false;
    }
  }
}
