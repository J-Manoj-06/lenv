import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/unread_count_provider.dart';
import '../utils/chat_type_config.dart';

/// Mixin for chat list screens to integrate unread counts
/// ✅ Non-invasive: doesn't modify existing logic
/// ✅ Reusable: works for all chat types
/// ✅ Safe: fail-silent approach
mixin UnreadCountMixin<T extends StatefulWidget> on State<T> {
  late UnreadCountProvider _unreadProvider;
  
  @override
  void initState() {
    super.initState();
    // Access provider after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadProvider = Provider.of<UnreadCountProvider>(
        context,
        listen: false,
      );
    });
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
    
    await _unreadProvider.loadUnreadCountsBatch(
      chatIds: chatIds,
      chatTypes: chatTypes,
    );
  }
  
  /// Get unread count for a specific chat
  int getUnreadCount(String chatId) {
    return _unreadProvider.getUnreadCount(chatId);
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
    await _unreadProvider.markChatAsRead(chatId);
  }
  
  /// Refresh unread counts when screen resumes
  /// Call this in didChangeAppLifecycleState or on screen focus
  void refreshUnreadCounts() {
    _unreadProvider.refreshAll();
  }
}

/// Mixin for individual chat screens to mark as read
/// ✅ Call this once when opening chat
mixin ChatReadMixin<T extends StatefulWidget> on State<T> {
  late UnreadCountProvider _unreadProvider;
  late String _chatId;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadProvider = Provider.of<UnreadCountProvider>(
        context,
        listen: false,
      );
      // Mark chat as read when screen opens
      _unreadProvider.markChatAsRead(_chatId);
    });
  }
  
  /// Initialize with chat ID (call in initState)
  void initializeChatRead(String chatId) {
    _chatId = chatId;
  }
  
  /// Refresh read status when returning from nested navigation
  void refreshReadStatus() {
    _unreadProvider.refreshChat(_chatId);
  }
}
