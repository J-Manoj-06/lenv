import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';
import '../models/group_subject.dart';

/// Enhanced offline data service for WhatsApp-like offline experience
/// Stores messages, groups, communities, and media for offline access
class OfflineDataService {
  static final OfflineDataService _instance = OfflineDataService._internal();
  factory OfflineDataService() => _instance;
  OfflineDataService._internal();

  static const String _groupMessagesBox = 'group_messages_offline';
  static const String _groupSubjectsBox = 'group_subjects_offline';
  static const String _communitiesBox = 'communities_offline';
  static const String _communityPostsBox = 'community_posts_offline';
  static const String _userDataBox = 'user_data_offline';
  static const String _teacherGroupsBox = 'teacher_groups_offline';
  static const String _parentTeachersBox = 'parent_teachers_offline';
  static const String _instituteCommunitiesBox =
      'institute_communities_offline';

  late Box<Map> _groupMessagesCache;
  late Box<Map> _groupSubjectsCache;
  late Box<Map> _communitiesCache;
  late Box<Map> _communityPostsCache;
  late Box<Map> _userDataCache;
  late Box<Map> _teacherGroupsCache;
  late Box<Map> _parentTeachersCache;
  late Box<Map> _instituteCommunitiesCache;

  bool _initialized = false;

  List<Map<String, dynamic>>? _asMapList(dynamic rawList) {
    if (rawList is! List) return null;

    final result = <Map<String, dynamic>>[];
    for (final item in rawList) {
      if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Future.wait([
            Hive.openBox<Map>(_groupMessagesBox),
            Hive.openBox<Map>(_groupSubjectsBox),
            Hive.openBox<Map>(_communitiesBox),
            Hive.openBox<Map>(_communityPostsBox),
            Hive.openBox<Map>(_userDataBox),
            Hive.openBox<Map>(_teacherGroupsBox),
            Hive.openBox<Map>(_parentTeachersBox),
            Hive.openBox<Map>(_instituteCommunitiesBox),
          ])
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw TimeoutException('OfflineDataService timeout'),
          )
          .then((boxes) {
            _groupMessagesCache = boxes[0];
            _groupSubjectsCache = boxes[1];
            _communitiesCache = boxes[2];
            _communityPostsCache = boxes[3];
            _userDataCache = boxes[4];
            _teacherGroupsCache = boxes[5];
            _parentTeachersCache = boxes[6];
            _instituteCommunitiesCache = boxes[7];
          });

      _initialized = true;
      debugPrint('✅ OfflineDataService initialized');
    } catch (e) {
      _initialized = true;
      debugPrint('⚠️ OfflineDataService initialization failed: $e');
      rethrow;
    }
  }

  // ==================== GROUP SUBJECTS ====================

  /// Cache student's classId
  Future<void> cacheStudentClassId({
    required String studentId,
    required String classId,
  }) async {
    try {
      await _userDataCache.put('classId_$studentId', {
        'classId': classId,
        'cachedAt': DateTime.now().toIso8601String(),
      });
      debugPrint('💾 Cached classId $classId for student $studentId');
    } catch (e) {
      debugPrint('Error caching classId: $e');
    }
  }

  /// Get cached classId for a student
  String? getCachedStudentClassId(String studentId) {
    try {
      final cached = _userDataCache.get('classId_$studentId');
      if (cached == null) return null;
      final classId = cached['classId'] as String?;
      if (classId != null) {
        debugPrint('📦 Using cached classId for student $studentId');
      }
      return classId;
    } catch (e) {
      debugPrint('Error reading cached classId: $e');
      return null;
    }
  }

  /// Cache group subjects for a student
  Future<void> cacheGroupSubjects({
    required String studentId,
    required List<GroupSubject> subjects,
  }) async {
    try {
      final data = subjects
          .map(
            (s) => {
              'id': s.id,
              'name': s.name,
              'teacherName': s.teacherName,
              'icon': s.icon,
            },
          )
          .toList();

      await _groupSubjectsCache.put('subjects_$studentId', {
        'subjects': data,
        'cachedAt': DateTime.now().toIso8601String(),
        'studentId': studentId,
      });
      debugPrint('✅ Cached ${subjects.length} group subjects for $studentId');
    } catch (e) {
      debugPrint('Error caching group subjects: $e');
    }
  }

  /// Get cached group subjects
  List<GroupSubject>? getCachedGroupSubjects(String studentId) {
    try {
      final cached = _groupSubjectsCache.get('subjects_$studentId');
      if (cached == null) return null;

      final subjectsList = cached['subjects'] as List?;
      if (subjectsList == null) return null;

      return subjectsList
          .map(
            (s) => GroupSubject(
              id: s['id'] ?? '',
              name: s['name'] ?? '',
              teacherName: s['teacherName'] ?? '',
              icon: s['icon'] ?? '📚',
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Error reading cached group subjects: $e');
      return null;
    }
  }

  // ==================== GROUP MESSAGES ====================

  /// Cache messages for a group chat
  Future<void> cacheGroupMessages({
    required String chatId,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      await _groupMessagesCache.put(chatId, {
        'messages': messages,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': messages.length,
      });
      debugPrint('✅ Cached ${messages.length} messages for $chatId');
    } catch (e) {
      debugPrint('Error caching group messages: $e');
    }
  }

  /// Get cached messages for a group chat
  List<Map<String, dynamic>>? getCachedGroupMessages(String chatId) {
    try {
      final cached = _groupMessagesCache.get(chatId);
      if (cached == null) return null;

      final messages = cached['messages'] as List?;
      if (messages == null) return null;

      // ✅ FIX: Safely convert each Map<dynamic, dynamic> to Map<String, dynamic>
      final result = <Map<String, dynamic>>[];
      for (final item in messages) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading cached group messages: $e');
      return null;
    }
  }

  /// Store last message timestamp for a chat (for sorting)
  Future<void> cacheLastMessageTimestamp({
    required String chatId,
    required int timestamp,
  }) async {
    try {
      final key = 'last_msg_ts_$chatId';
      await _userDataCache.put(key, {
        'timestamp': timestamp,
        'cachedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error caching last message timestamp: $e');
    }
  }

  /// Get cached last message timestamp
  int? getCachedLastMessageTimestamp(String chatId) {
    try {
      final key = 'last_msg_ts_$chatId';
      final cached = _userDataCache.get(key);
      if (cached == null) return null;
      return cached['timestamp'] as int?;
    } catch (e) {
      debugPrint('Error reading cached timestamp: $e');
      return null;
    }
  }

  // ==================== COMMUNITIES ====================

  /// Cache communities list
  Future<void> cacheCommunities({
    required String studentId,
    required List<Map<String, dynamic>> communities,
  }) async {
    try {
      await _communitiesCache.put('communities_$studentId', {
        'communities': communities,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': communities.length,
      });
      debugPrint('✅ Cached ${communities.length} communities for $studentId');
    } catch (e) {
      debugPrint('Error caching communities: $e');
    }
  }

  /// Get cached communities
  List<Map<String, dynamic>>? getCachedCommunities(String studentId) {
    try {
      final cached = _communitiesCache.get('communities_$studentId');
      if (cached == null) return null;

      final communities = cached['communities'] as List?;
      if (communities == null) return null;

      // ✅ FIX: Safely convert each Map<dynamic, dynamic> to Map<String, dynamic>
      final result = <Map<String, dynamic>>[];
      for (final item in communities) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading cached communities: $e');
      return null;
    }
  }

  /// Cache posts for a community
  Future<void> cacheCommunityPosts({
    required String communityId,
    required List<Map<String, dynamic>> posts,
  }) async {
    try {
      await _communityPostsCache.put('posts_$communityId', {
        'posts': posts,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': posts.length,
      });
      debugPrint('✅ Cached ${posts.length} posts for community $communityId');
    } catch (e) {
      debugPrint('Error caching community posts: $e');
    }
  }

  /// Get cached posts for a community
  List<Map<String, dynamic>>? getCachedCommunityPosts(String communityId) {
    try {
      final cached = _communityPostsCache.get('posts_$communityId');
      if (cached == null) return null;

      final posts = cached['posts'] as List?;
      if (posts == null) return null;

      // ✅ FIX: Safely convert each Map<dynamic, dynamic> to Map<String, dynamic>
      final result = <Map<String, dynamic>>[];
      for (final item in posts) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading cached community posts: $e');
      return null;
    }
  }

  // ==================== UTILITY ====================

  /// Clear all cached data for a user
  Future<void> clearUserCache(String userId) async {
    try {
      await _groupSubjectsCache.delete('subjects_$userId');
      await _communitiesCache.delete('communities_$userId');
      debugPrint('✅ Cleared cache for user $userId');
    } catch (e) {
      debugPrint('Error clearing user cache: $e');
    }
  }

  /// Clear all caches (for logout)
  Future<void> clearAllCaches() async {
    try {
      await Future.wait([
        _groupMessagesCache.clear(),
        _groupSubjectsCache.clear(),
        _communitiesCache.clear(),
        _communityPostsCache.clear(),
        _userDataCache.clear(),
        _teacherGroupsCache.clear(),
        _parentTeachersCache.clear(),
        _instituteCommunitiesCache.clear(),
      ]);
      debugPrint('✅ Cleared all offline caches');
    } catch (e) {
      debugPrint('Error clearing all caches: $e');
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'groupMessages': _groupMessagesCache.length,
      'groupSubjects': _groupSubjectsCache.length,
      'communities': _communitiesCache.length,
      'communityPosts': _communityPostsCache.length,
      'userData': _userDataCache.length,
      'teacherGroups': _teacherGroupsCache.length,
      'parentTeachers': _parentTeachersCache.length,
      'instituteCommunities': _instituteCommunitiesCache.length,
    };
  }

  // ==================== TEACHER GROUPS ====================

  /// Cache teacher's message groups
  Future<void> cacheTeacherGroups({
    required String teacherId,
    required List<Map<String, dynamic>> groups,
  }) async {
    try {
      await _teacherGroupsCache.put('groups_$teacherId', {
        'groups': groups,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': groups.length,
      });
      debugPrint('✅ Cached ${groups.length} teacher groups for $teacherId');
    } catch (e) {
      debugPrint('Error caching teacher groups: $e');
    }
  }

  /// Get cached teacher groups
  List<Map<String, dynamic>>? getCachedTeacherGroups(String teacherId) {
    try {
      debugPrint('🔍 [CACHE] Looking for cached groups: groups_$teacherId');
      final cached = _teacherGroupsCache.get('groups_$teacherId');
      debugPrint(
        '🔍 [CACHE] Raw cached data: ${cached != null ? "EXISTS" : "NULL"}',
      );

      if (cached == null) {
        debugPrint('⚠️ [CACHE] No cached entry found for groups_$teacherId');
        return null;
      }

      final groups = cached['groups'] as List?;
      debugPrint('🔍 [CACHE] Groups list: ${groups?.length ?? 0} items');

      if (groups == null) {
        debugPrint('⚠️ [CACHE] Groups list is null inside cached entry');
        return null;
      }

      // ✅ FIX: Safely convert each Map<dynamic, dynamic> to Map<String, dynamic>
      final result = <Map<String, dynamic>>[];
      for (final item in groups) {
        if (item is Map) {
          final converted = <String, dynamic>{};
          for (final entry in item.entries) {
            converted[entry.key.toString()] = entry.value;
          }
          result.add(converted);
        }
      }

      debugPrint('✅ [CACHE] Returning ${result.length} cached teacher groups');
      return result;
    } catch (e) {
      debugPrint('❌ [CACHE] Error reading cached teacher groups: $e');
      return null;
    }
  }

  /// Cache teacher's assigned groups list (teacher_groups_screen)
  Future<void> cacheTeacherAssignedGroups({
    required String teacherId,
    required List<Map<String, dynamic>> groups,
  }) async {
    try {
      await _teacherGroupsCache.put('assigned_groups_$teacherId', {
        'groups': groups,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': groups.length,
      });
      debugPrint(
        '✅ Cached ${groups.length} assigned teacher groups for $teacherId',
      );
    } catch (e) {
      debugPrint('Error caching assigned teacher groups: $e');
    }
  }

  /// Get cached teacher assigned groups list (teacher_groups_screen)
  List<Map<String, dynamic>>? getCachedTeacherAssignedGroups(String teacherId) {
    try {
      final cached = _teacherGroupsCache.get('assigned_groups_$teacherId');
      if (cached == null) return null;

      final groups = cached['groups'] as List?;
      if (groups == null) return null;

      // ✅ FIX: Safely convert each Map<dynamic, dynamic> to Map<String, dynamic>
      final result = <Map<String, dynamic>>[];
      for (final item in groups) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading cached assigned teacher groups: $e');
      return null;
    }
  }

  /// Cache teacher communities (for teacher role offline support)
  Future<void> cacheTeacherCommunities({
    required String teacherId,
    required List<Map<String, dynamic>> communities,
  }) async {
    try {
      await _communitiesCache.put('teacher_communities_$teacherId', {
        'communities': communities,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': communities.length,
      });
      debugPrint(
        '✅ Cached ${communities.length} teacher communities for $teacherId',
      );
    } catch (e) {
      debugPrint('Error caching teacher communities: $e');
    }
  }

  /// Get cached teacher communities
  List<Map<String, dynamic>>? getCachedTeacherCommunities(String teacherId) {
    try {
      final cached = _communitiesCache.get('teacher_communities_$teacherId');
      if (cached == null) return null;

      final communities = cached['communities'] as List?;
      if (communities == null) return null;

      // ✅ FIX: Safely convert each Map<dynamic, dynamic> to Map<String, dynamic>
      final result = <Map<String, dynamic>>[];
      for (final item in communities) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading cached teacher communities: $e');
      return null;
    }
  }

  /// Cache student class groups payload (student_groups_screen)
  Future<void> cacheStudentClassGroups({
    required String studentId,
    required Map<String, dynamic> classData,
  }) async {
    try {
      await _groupSubjectsCache.put('student_groups_$studentId', {
        'classData': classData,
        'cachedAt': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Cached student class groups for $studentId');
    } catch (e) {
      debugPrint('Error caching student class groups: $e');
    }
  }

  /// Get cached student class groups payload (student_groups_screen)
  Map<String, dynamic>? getCachedStudentClassGroups(String studentId) {
    try {
      final cached = _groupSubjectsCache.get('student_groups_$studentId');
      if (cached == null) return null;

      final classData = cached['classData'] as Map?;
      if (classData == null) return null;

      return Map<String, dynamic>.from(classData);
    } catch (e) {
      debugPrint('Error reading cached student class groups: $e');
      return null;
    }
  }

  // ==================== PARENT TEACHERS ====================

  /// Cache parent's teachers list
  Future<void> cacheParentTeachers({
    required String childId,
    required List<Map<String, dynamic>> teachers,
  }) async {
    try {
      await _parentTeachersCache.put('teachers_$childId', {
        'teachers': teachers,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': teachers.length,
      });
      debugPrint('✅ Cached ${teachers.length} teachers for child $childId');
    } catch (e) {
      debugPrint('Error caching parent teachers: $e');
    }
  }

  /// Get cached teachers list for parent
  List<Map<String, dynamic>>? getCachedParentTeachers(String childId) {
    try {
      final cached = _parentTeachersCache.get('teachers_$childId');
      if (cached == null) return null;

      final teachers = cached['teachers'] as List?;
      if (teachers == null) return null;

      // ✅ FIX: Safely convert each Map<dynamic, dynamic> to Map<String, dynamic>
      final result = <Map<String, dynamic>>[];
      for (final item in teachers) {
        if (item is Map) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error reading cached parent teachers: $e');
      return null;
    }
  }

  // ==================== INSTITUTE COMMUNITIES ====================

  /// Cache institute's communities
  Future<void> cacheInstituteCommunities({
    required String instituteId,
    required List<Map<String, dynamic>> communities,
  }) async {
    try {
      await _instituteCommunitiesCache.put('communities_$instituteId', {
        'communities': communities,
        'cachedAt': DateTime.now().toIso8601String(),
        'count': communities.length,
      });
      debugPrint(
        '✅ Cached ${communities.length} communities for institute $instituteId',
      );
    } catch (e) {
      debugPrint('Error caching institute communities: $e');
    }
  }

  /// Get cached communities for institute
  List<Map<String, dynamic>>? getCachedInstituteCommunities(
    String instituteId,
  ) {
    try {
      final cached = _instituteCommunitiesCache.get('communities_$instituteId');
      if (cached == null) return null;

      return _asMapList(cached['communities']);
    } catch (e) {
      debugPrint('Error reading cached institute communities: $e');
      return null;
    }
  }
}
