import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../utils/chat_type_config.dart';

/// Unified unread message count service for all chat types
/// Supports: Group chats, Community chats, Parent-Teacher individual, Parent-Teacher groups
class UnreadCountService {
  static final UnreadCountService _instance = UnreadCountService._internal();

  factory UnreadCountService() {
    return _instance;
  }

  UnreadCountService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache: chatId -> unreadCount
  final Map<String, int> _unreadCache = {};

  /// Get unread count for a specific chat
  ///
  /// [userId] - Current user ID
  /// [chatId] - Chat identifier (same across all chat types)
  /// [chatType] - Type: 'group', 'community', 'individual', 'ptGroup'
  /// [messageCollection] - Path to messages collection
  ///
  /// Returns: Number of unread messages (cached if available)
  Future<int> getUnreadCount({
    required String userId,
    required String chatId,
    required String chatType,
    required String messageCollection,
    bool forceRefresh = false,
    Timestamp? overrideLastReadAt,
  }) async {
    // Check cache first (unless force refresh)
    final cacheKey = '$chatId:$userId';
    if (!forceRefresh && _unreadCache.containsKey(cacheKey)) {
      final cached = _unreadCache[cacheKey] ?? 0;
      debugPrint(
        '[UnreadService] 🔎 Cache hit: chat=$chatId user=$userId count=$cached',
      );
      return cached;
    }

    try {
      // Get last read timestamp
      final lastReadAt = await _getLastReadAt(userId, chatId);
      final effectiveLastRead = overrideLastReadAt != null
          ? (overrideLastReadAt.millisecondsSinceEpoch >
                    lastReadAt.millisecondsSinceEpoch
                ? overrideLastReadAt
                : lastReadAt)
          : lastReadAt;

      // Determine field and comparison value by chat type
      // Groups use integer 'timestamp' (ms since epoch)
      // Communities/others primarily use Firestore Timestamp 'createdAt' but fall back to
      // 'timestamp' for legacy community documents.
      final isGroup = chatType == ChatTypeConfig.groupChat;
      final fieldCandidates = isGroup
          ? ['timestamp']
          : ['createdAt', 'timestamp'];

      int totalCount = 0;
      String usedField = fieldCandidates.first;
      for (final fieldName in fieldCandidates) {
        try {
          final compareValue = fieldName == 'timestamp'
              ? effectiveLastRead.toDate().millisecondsSinceEpoch
              : effectiveLastRead;

          final snapshot = await _firestore
              .collection(messageCollection)
              .where(fieldName, isGreaterThan: compareValue)
              .count()
              .get();
          totalCount = snapshot.count ?? 0;
          usedField = fieldName;
          break;
        } catch (e) {
          debugPrint(
            '[UnreadService] ⚠️ Count failed on field=$fieldName, trying next.',
          );
          continue;
        }
      }
      debugPrint(
        '[UnreadService] 📊 Total unread raw: chat=$chatId type=$chatType field=$usedField count=$totalCount',
      );

      // Count messages sent by current user in the unread window, then subtract
      int selfCount = 0;
      // Try common sender field names
      for (final senderField in [
        'senderId',
        'senderUid',
        'senderID',
        'sender',
      ]) {
        try {
          final compareValueSelf = usedField == 'timestamp'
              ? effectiveLastRead.toDate().millisecondsSinceEpoch
              : effectiveLastRead;

          final selfSnapshot = await _firestore
              .collection(messageCollection)
              .where(usedField, isGreaterThan: compareValueSelf)
              .where(senderField, isEqualTo: userId)
              .count()
              .get();
          selfCount = selfSnapshot.count ?? 0;
          debugPrint(
            '[UnreadService] 👤 Self messages field=$senderField count=$selfCount',
          );
          break; // stop after first successful field
        } catch (e) {
          debugPrint('[UnreadService] ⚠️ Sender field miss: $senderField');
          continue;
        }
      }

      final count = totalCount - selfCount;
      final safeCount = count < 0 ? 0 : count;

      // Cache the result (fresh)
      _unreadCache[cacheKey] = safeCount;
      debugPrint(
        '[UnreadService] ✅ Final unread: chat=$chatId user=$userId count=$safeCount',
      );

      return safeCount;
    } catch (e) {
      debugPrint('[UnreadService] ❌ getUnreadCount error: $e');
      return 0; // Fail gracefully
    }
  }

  /// Get unread counts for multiple chats (batched)
  ///
  /// Returns: Map of chatId -> unreadCount
  Future<Map<String, int>> getUnreadCountsBatch({
    required String userId,
    required List<String> chatIds,
    required Map<String, String> chatTypesMap, // chatId -> chatType
    required Map<String, String>
    messageCollectionsMap, // chatId -> collection path
    bool forceRefresh = false,
    Map<String, Timestamp>? overrideLastReadAtMap,
  }) async {
    final results = <String, int>{};

    try {
      for (final chatId in chatIds) {
        final chatType = chatTypesMap[chatId] ?? 'unknown';
        final collection = messageCollectionsMap[chatId] ?? '';

        if (collection.isEmpty) continue;

        final count = await getUnreadCount(
          userId: userId,
          chatId: chatId,
          chatType: chatType,
          messageCollection: collection,
          forceRefresh: forceRefresh,
          overrideLastReadAt: overrideLastReadAtMap?[chatId],
        );

        results[chatId] = count;
      }
    } catch (e) {}

    return results;
  }

  /// Mark chat as read by updating lastReadAt
  ///
  /// Safe operation: Uses server timestamp, idempotent, non-blocking
  Future<void> markChatAsRead({
    required String userId,
    required String chatId,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('chatReads')
          .doc(chatId)
          .set({
            'lastReadAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      debugPrint(
        '[UnreadService] 📝 Marked as read: chat=$chatId user=$userId',
      );

      // Clear cache
      final cacheKey = '$chatId:$userId';
      _unreadCache.remove(cacheKey);
    } catch (e) {
      debugPrint('[UnreadService] ❌ markChatAsRead error: $e');
      // Fail silently - don't break UI
    }
  }

  /// Get last read timestamp for a chat
  /// Defaults to 30 days ago if never read
  Future<Timestamp> _getLastReadAt(String userId, String chatId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('chatReads')
          .doc(chatId)
          .get();

      if (doc.exists && doc['lastReadAt'] != null) {
        final ts = doc['lastReadAt'] as Timestamp;
        debugPrint(
          '[UnreadService] ⏱️ lastReadAt: chat=$chatId user=$userId ts=${ts.millisecondsSinceEpoch}',
        );
        return ts;
      }
    } catch (e) {}

    // Default: 30 days ago (all messages considered new)
    return Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 30)),
    );
  }

  /// Refresh cache for specific chat
  void refreshCache(String chatId, String userId) {
    final cacheKey = '$chatId:$userId';
    _unreadCache.remove(cacheKey);
  }

  /// Clear all cache (useful on logout)
  void clearCache() {
    _unreadCache.clear();
  }

  /// Get cache stats (for debugging)
  Map<String, int> getCacheStats() {
    return {
      'cached_items': _unreadCache.length,
      'total_unread': _unreadCache.values.fold(0, (a, b) => a + b),
    };
  }

  /// Stream unread count for real-time updates (optional, use sparingly)
  ///
  /// ⚠️ Use only for currently open chat, not for lists
  Stream<int> streamUnreadCount({
    required String userId,
    required String chatId,
    required String messageCollection,
    String chatType = ChatTypeConfig.communityChat,
  }) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('chatReads')
        .doc(chatId)
        .snapshots()
        .asyncMap((readDoc) async {
          final lastReadAt =
              readDoc['lastReadAt'] as Timestamp? ??
              Timestamp.fromDate(
                DateTime.now().subtract(const Duration(days: 30)),
              );
          // Determine field and comparison value
          final isGroup = chatType == ChatTypeConfig.groupChat;
          final fieldName = isGroup ? 'timestamp' : 'createdAt';
          final compareValue = isGroup
              ? lastReadAt.toDate().millisecondsSinceEpoch
              : lastReadAt;

          final query = _firestore
              .collection(messageCollection)
              .where(fieldName, isGreaterThan: compareValue);

          final snapshot = await query.count().get();
          return snapshot.count ?? 0;
        });
  }
}
