import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/unread_count_provider.dart';

/// Mixin for chat list screens to integrate unread counts
/// ✅ Non-invasive: doesn't modify existing logic
/// ✅ Reusable: works for all chat types
/// ✅ Safe: fail-silent approach
mixin UnreadCountMixin<T extends StatefulWidget> on State<T> {
  UnreadCountProvider? _unreadProvider;

  void _ensureProvider() {
    _unreadProvider ??= Provider.of<UnreadCountProvider>(
      context,
      listen: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureProvider();
  }

  /// Load unread counts for multiple chats
  /// Call this when loading chat list
  ///
  /// Example:
  /// ```dart
  /// loadUnreadCountsForChats(
  ///   chatIds: ['group1', 'group2', 'group3'],
  ///   chatTypes: {'group1': 'group', 'group2': 'group', 'group3': 'community'},
  /// );
  /// ```
  Future<void> loadUnreadCountsForChats({
    required List<String> chatIds,
    required Map<String, String> chatTypes,
  }) async {
    if (chatIds.isEmpty) return;
    _ensureProvider();
    if (_unreadProvider == null) return;
    await _unreadProvider!.loadUnreadCountsBatch(
      chatIds: chatIds,
      chatTypes: chatTypes,
    );
  }

  /// Get unread count for a specific chat
  int getUnreadCount(String chatId) {
    _ensureProvider();
    return _unreadProvider?.getUnreadCount(chatId) ?? 0;
  }

  /// Mark chat as read when user opens it
  /// Call this in onTap handler of chat card
  ///
  /// Example:
  /// ```dart
  /// ListTile(
  ///   onTap: () {
  ///     markChatAsRead(chatId);
  ///     Navigator.push(...); // Navigate to chat
  ///   },
  /// )
  /// ```
  Future<void> markChatAsRead(String chatId) async {
    _ensureProvider();
    if (_unreadProvider == null) return;
    await _unreadProvider!.markChatAsRead(chatId);
  }

  /// Refresh unread counts when screen resumes
  /// Call this in didChangeAppLifecycleState or on screen focus
  void refreshUnreadCounts() {
    _ensureProvider();
    _unreadProvider?.refreshAll();
  }
}

/// Mixin for individual chat screens to mark as read
/// ✅ Call this once when opening chat
mixin ChatReadMixin<T extends StatefulWidget> on State<T> {
  UnreadCountProvider? _unreadProvider;
  late String _chatId;

  void _ensureProviderCR() {
    _unreadProvider ??= Provider.of<UnreadCountProvider>(
      context,
      listen: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureProviderCR();
    if (_unreadProvider != null && _chatId.isNotEmpty) {
      _unreadProvider!.markChatAsRead(_chatId);
    }
  }

  /// Initialize with chat ID (call in initState)
  void initializeChatRead(String chatId) {
    _chatId = chatId;
  }

  /// Refresh read status when returning from nested navigation
  void refreshReadStatus() {
    _ensureProviderCR();
    _unreadProvider?.refreshChat(_chatId);
  }
}
