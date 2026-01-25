import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/unread_count_service.dart';
import '../utils/chat_type_config.dart';

/// Provider for managing unread counts across app
/// Handles caching and state updates
class UnreadCountProvider with ChangeNotifier {
  final UnreadCountService _service = UnreadCountService();

  // Storage: chatId -> unreadCount
  final Map<String, int> _unreadCounts = {};

  // Optimistic last-read timestamps to avoid badge flicker while waiting for server write
  final Map<String, Timestamp> _optimisticLastRead = {};

  // Loading states
  final Set<String> _loadingChats = {};

  String? _currentUserId;

  /// Initialize with current user ID
  void initialize(String userId) {
    _currentUserId = userId;
    debugPrint('[UnreadProvider] ✅ Initialized for user: $userId');
  }

  /// Get unread count for a specific chat
  int getUnreadCount(String chatId) {
    return _unreadCounts[chatId] ?? 0;
  }

  /// Check if count is loading
  bool isLoading(String chatId) {
    return _loadingChats.contains(chatId);
  }

  /// Load unread count for a single chat
  /// Non-blocking: shows cached value while loading
  Future<void> loadUnreadCount({
    required String chatId,
    required String chatType,
  }) async {
    if (_currentUserId == null) {
      debugPrint('[UnreadProvider] ⚠️ Skipping load (no user): chat=$chatId');
      return;
    }

    _loadingChats.add(chatId);
    notifyListeners();

    try {
      final collection = ChatTypeConfig.getMessagesCollectionPath(
        chatType: chatType,
        chatId: chatId,
      );

      // Force refresh so new messages are counted immediately
      _service.refreshCache(chatId, _currentUserId!);
      final count = await _service.getUnreadCount(
        userId: _currentUserId!,
        chatId: chatId,
        chatType: chatType,
        messageCollection: collection,
        forceRefresh: true,
        overrideLastReadAt: _optimisticLastRead[chatId],
      );

      _unreadCounts[chatId] = count;
      debugPrint(
        '[UnreadProvider] 📥 Loaded unread: chat=$chatId count=$count',
      );
      notifyListeners();
    } finally {
      _loadingChats.remove(chatId);
      notifyListeners();
    }
  }

  /// Load unread counts for multiple chats (batch)
  Future<void> loadUnreadCountsBatch({
    required List<String> chatIds,
    required Map<String, String> chatTypes, // chatId -> chatType
  }) async {
    if (_currentUserId == null || chatIds.isEmpty) {
      return;
    }

    // Mark all as loading
    _loadingChats.addAll(chatIds);
    notifyListeners();

    try {
      // Build collection map
      final collections = <String, String>{};
      for (final chatId in chatIds) {
        final chatType = chatTypes[chatId] ?? '';
        if (chatType.isNotEmpty) {
          collections[chatId] = ChatTypeConfig.getMessagesCollectionPath(
            chatType: chatType,
            chatId: chatId,
          );
        }
      }

      // Clear caches for these chats to avoid stale zeros
      for (final id in chatIds) {
        _service.refreshCache(id, _currentUserId!);
      }

      // Fetch batch (force refresh inside service)
      final counts = await _service.getUnreadCountsBatch(
        userId: _currentUserId!,
        chatIds: chatIds,
        chatTypesMap: chatTypes,
        messageCollectionsMap: collections,
        forceRefresh: true,
        overrideLastReadAtMap: _optimisticLastRead,
      );

      // Update cache
      _unreadCounts.addAll(counts);
      notifyListeners();
    } finally {
      _loadingChats.clear();
      notifyListeners();
    }
  }

  /// Mark chat as read (safe operation)
  Future<void> markChatAsRead(String chatId) async {
    if (_currentUserId == null) return;

    // Immediately clear badge (optimistic)
    _unreadCounts[chatId] = 0;
    _optimisticLastRead[chatId] = Timestamp.fromDate(DateTime.now());
    debugPrint('[UnreadProvider] ✅ Optimistic clear: chat=$chatId');
    notifyListeners();

    // Update Firestore (non-blocking)
    _service.markChatAsRead(userId: _currentUserId!, chatId: chatId).catchError(
      (e) {
        // If fails, next load will fix it
        debugPrint('[UnreadProvider] ❌ markChatAsRead failed: $e');
      },
    );
  }

  /// Refresh specific chat's count
  void refreshChat(String chatId) {
    _service.refreshCache(chatId, _currentUserId ?? '');
    debugPrint('[UnreadProvider] 🔄 Refresh cache: chat=$chatId');
    // Do not remove local count to avoid badge disappearing/flicker
    // Next load will overwrite with fresh value
    notifyListeners();
  }

  /// Refresh all unread counts
  void refreshAll() {
    _service.clearCache();
    _unreadCounts.clear();
    _optimisticLastRead.clear();
    notifyListeners();
  }

  /// Get total unread count across all chats
  int getTotalUnreadCount() {
    return _unreadCounts.values.fold(0, (a, b) => a + b);
  }

  /// Get all unread chat IDs
  List<String> getUnreadChatIds() {
    return _unreadCounts.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toList();
  }

  /// Clear all on logout
  void logout() {
    _unreadCounts.clear();
    _loadingChats.clear();
    _currentUserId = null;
    _service.clearCache();
    _optimisticLastRead.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _service.clearCache();
    super.dispose();
  }
}
