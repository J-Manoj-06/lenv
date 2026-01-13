import 'group_messaging_service.dart';
import '../models/group_chat_message.dart';
import 'connectivity_service.dart';
import 'offline_cache_manager.dart';

/// Extension to GroupMessagingService to add offline support
/// Automatically caches group messages and loads from cache when offline
extension GroupMessagingOfflineSupport on GroupMessagingService {
  /// Get group messages with offline fallback
  /// Online: fetches from Firestore and caches
  /// Offline: returns cached data if available
  Stream<List<GroupChatMessage>> getGroupMessagesWithOfflineSupport(
    String classId,
    String subjectId, {
    int limit = 50,
  }) {
    final connectivityService = ConnectivityService();
    final cacheManager = OfflineCacheManager();

    return connectivityService.onConnectivityChanged.asyncExpand((
      isOnline,
    ) async* {
      if (isOnline) {
        // Online: stream from Firestore and cache
        await for (final messages in getGroupMessages(
          classId,
          subjectId,
          limit: limit,
        )) {
          // Cache messages in background
          _cacheGroupMessages(classId, subjectId, messages);
          yield messages;
        }
      } else {
        // Offline: try to load from cache
        final cached = await _getGroupMessagesFromCache(classId, subjectId);
        if (cached.isNotEmpty) {
          yield cached;
        }
        // Keep listening for online status (don't complete the stream)
        yield* Stream.empty();
      }
    });
  }

  /// Cache group messages locally
  Future<void> _cacheGroupMessages(
    String classId,
    String subjectId,
    List<GroupChatMessage> messages,
  ) async {
    try {
      final cacheManager = OfflineCacheManager();
      final messagesList = messages.map((m) => m.toFirestore()).toList();
      final conversationId = '${classId}_$subjectId';

      await cacheManager.cacheGroups(
        userId: classId,
        role: 'group_messages',
        groupsList: [
          {
            'conversationId': conversationId,
            'messages': messagesList,
            'count': messages.length,
          },
        ],
      );
    } catch (e) {
      // Silent fail - caching should not crash the app
    }
  }

  /// Get group messages from cache
  Future<List<GroupChatMessage>> _getGroupMessagesFromCache(
    String classId,
    String subjectId,
  ) async {
    try {
      final cacheManager = OfflineCacheManager();
      final cached = cacheManager.getCachedGroups(
        userId: classId,
        role: 'group_messages',
      );

      if (cached == null || cached.isEmpty) return [];

      // Find the specific conversation
      final conversationId = '${classId}_$subjectId';
      final conversation = cached.firstWhere(
        (g) => g['conversationId'] == conversationId,
        orElse: () => {},
      );

      if (conversation.isEmpty) return [];

      final messagesList = conversation['messages'] as List?;
      if (messagesList == null) return [];

      return messagesList
          .cast<Map<String, dynamic>>()
          .map((msg) => GroupChatMessage.fromFirestore(msg, msg['id'] ?? ''))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// Wrapper to handle group data with offline support
/// For subject/group listings
class GroupMessagingOfflineHelper {
  static Future<void> cacheGroupSubjects({
    required String classId,
    required String userId,
    required List<Map<String, dynamic>> subjects,
  }) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.cacheCommunities(
        userId: '${classId}_$userId',
        communities: subjects,
      );
    } catch (e) {
      // Silent fail
    }
  }

  static Future<List<Map<String, dynamic>>?> getCachedGroupSubjects({
    required String classId,
    required String userId,
  }) async {
    try {
      final cacheManager = OfflineCacheManager();
      return cacheManager.getCachedCommunities('${classId}_$userId');
    } catch (e) {
      return null;
    }
  }
}
