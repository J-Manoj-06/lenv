import 'package:hive_flutter/hive_flutter.dart';
import '../models/local_message.dart';

/// Local repository for offline message storage and search
/// WHY: Single source of truth for all message operations
/// - All reads/writes go through local DB first
/// - Firebase is ONLY for sync, never for search
/// - Works completely offline
class LocalMessageRepository {
  static const String _boxName = 'messages';
  static const String _indexBoxName = 'message_index';

  Box<LocalMessage>? _messageBox;
  Box<Map>? _indexBox; // For fast lookup: messageId -> index

  /// Initialize Hive database
  /// WHY: Must be called on app startup before any message operations
  Future<void> initialize() async {
    // Don't re-initialize Hive - it's already done in main.dart
    // Just open the boxes

    // Open message box
    if (!Hive.isBoxOpen(_boxName)) {
      _messageBox = await Hive.openBox<LocalMessage>(_boxName);
    } else {
      _messageBox = Hive.box<LocalMessage>(_boxName);
    }

    // Open index box for fast lookups
    if (!Hive.isBoxOpen(_indexBoxName)) {
      _indexBox = await Hive.openBox<Map>(_indexBoxName);
    } else {
      _indexBox = Hive.box<Map>(_indexBoxName);
    }
  }

  /// Save a single message to local storage
  /// WHY: Called when new message arrives from Firebase or user sends message
  Future<void> saveMessage(LocalMessage message) async {
    await _ensureInitialized();

    // Use messageId as key for easy lookup
    await _messageBox!.put(message.messageId, message);
  }

  /// Save multiple messages in batch
  /// WHY: More efficient when syncing many messages from Firebase
  Future<void> saveMessages(List<LocalMessage> messages) async {
    await _ensureInitialized();

    final Map<String, LocalMessage> messageMap = {
      for (var msg in messages) msg.messageId: msg,
    };

    await _messageBox!.putAll(messageMap);
  }

  /// Get all messages for a specific chat
  /// WHY: Chat UI displays messages from local DB, NOT Firebase
  Future<List<LocalMessage>> getMessagesForChat(
    String chatId, {
    int? limit,
  }) async {
    await _ensureInitialized();

    // Filter messages by chatId
    final messages = _messageBox!.values
        .where((msg) => msg.chatId == chatId && !msg.isDeleted)
        .toList();

    // Sort by timestamp (newest first for chat UI)
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Apply limit if specified
    if (limit != null && messages.length > limit) {
      return messages.sublist(0, limit);
    }

    return messages;
  }

  /// Search messages across all chats
  /// WHY: Offline search - NO Firebase queries
  Future<List<LocalMessage>> searchMessages(
    String query, {
    String? chatId, // Optional: search within specific chat
    int limit = 500,
  }) async {
    await _ensureInitialized();

    if (query.trim().isEmpty) {
      return [];
    }

    final lowerQuery = query.toLowerCase();

    // Filter all messages
    var results = _messageBox!.values.where((msg) {
      // Skip deleted messages
      if (msg.isDeleted) return false;

      // Filter by chatId if specified
      if (chatId != null && msg.chatId != chatId) return false;

      // Search in message text only — sender name is NOT matched
      if (msg.messageText != null &&
          msg.messageText!.toLowerCase().contains(lowerQuery)) {
        return true;
      }

      // Search in poll question
      if (msg.pollData != null) {
        final pollQuestion = msg.pollData!['question'] as String?;
        if (pollQuestion != null &&
            pollQuestion.toLowerCase().contains(lowerQuery)) {
          return true;
        }
      }

      return false;
    }).toList();

    // Sort by timestamp (newest first)
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Limit results
    if (results.length > limit) {
      results = results.sublist(0, limit);
    }

    if (results.isNotEmpty) {}

    return results;
  }

  /// Search for files and media attachments
  /// WHY: Separate search for PDFs, images, audio files, videos, etc.
  Future<List<LocalMessage>> searchFilesAndMedia(
    String query, {
    String? chatId, // Optional: search within specific chat
    int limit = 100,
  }) async {
    await _ensureInitialized();

    if (query.trim().isEmpty) {
      return [];
    }

    // Filter messages with attachments
    var allMessagesWithAttachments = _messageBox!.values.where((msg) {
      if (msg.isDeleted) return false;
      if (chatId != null && msg.chatId != chatId) return false;
      return msg.hasAttachment();
    }).toList();

    if (allMessagesWithAttachments.isNotEmpty) {
      for (var i = 0; i < allMessagesWithAttachments.take(3).length; i++) {
        final msg = allMessagesWithAttachments[i];
      }
    }

    var results = allMessagesWithAttachments.where((msg) {
      return msg.matchesFileSearch(query);
    }).toList();

    // Sort by timestamp (newest first)
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Limit results
    if (results.length > limit) {
      results = results.sublist(0, limit);
    }

    if (results.isNotEmpty) {}

    return results;
  }

  /// Get a single message by ID
  /// WHY: Used when navigating to message from search results
  Future<LocalMessage?> getMessageById(String messageId) async {
    await _ensureInitialized();
    return _messageBox!.get(messageId);
  }

  /// Check if message exists locally
  /// WHY: Avoid re-fetching from Firebase if already cached
  Future<bool> hasMessage(String messageId) async {
    await _ensureInitialized();
    return _messageBox!.containsKey(messageId);
  }

  /// Soft delete a message
  /// WHY: Mark as deleted without removing from DB (can be restored)
  Future<void> deleteMessage(String messageId) async {
    await _ensureInitialized();

    final message = _messageBox!.get(messageId);
    if (message != null) {
      final updated = LocalMessage(
        messageId: message.messageId,
        chatId: message.chatId,
        chatType: message.chatType,
        senderId: message.senderId,
        senderName: message.senderName,
        messageText: message.messageText,
        timestamp: message.timestamp,
        attachmentUrl: message.attachmentUrl,
        attachmentType: message.attachmentType,
        pollData: message.pollData,
        isDeleted: true, // Mark as deleted
        replyToMessageId: message.replyToMessageId,
      );

      await _messageBox!.put(messageId, updated);
    }
  }

  /// Get message count for a chat
  /// WHY: Display unread count or total messages
  Future<int> getMessageCount(String chatId) async {
    await _ensureInitialized();

    return _messageBox!.values
        .where((msg) => msg.chatId == chatId && !msg.isDeleted)
        .length;
  }

  /// Clear all messages (used on logout)
  /// WHY: CRITICAL - Remove all messages from device when user logs out
  Future<void> clearAllMessages() async {
    await _ensureInitialized();

    await _messageBox!.clear();
    await _indexBox!.clear();
  }

  /// Delete messages for a specific chat
  /// WHY: When user leaves a chat or chat is deleted
  Future<void> clearChatMessages(String chatId) async {
    await _ensureInitialized();

    final keysToDelete = _messageBox!.values
        .where((msg) => msg.chatId == chatId)
        .map((msg) => msg.messageId)
        .toList();

    await _messageBox!.deleteAll(keysToDelete);
  }

  /// Get total message count (all chats)
  /// WHY: Show storage usage or debug info
  Future<int> getTotalMessageCount() async {
    await _ensureInitialized();
    return _messageBox!.values.where((msg) => !msg.isDeleted).length;
  }

  /// Get pending messages (upload in progress)
  /// WHY: Load pending messages when screen opens to show upload progress
  Future<List<LocalMessage>> getPendingMessages({
    required String chatId,
    required String senderId,
  }) async {
    await _ensureInitialized();

    final pendingMessages = _messageBox!.values.where((msg) {
      final matches =
          msg.chatId == chatId &&
          msg.senderId == senderId &&
          msg.isPending == true;

      // ✅ FIXED: Include messages with EITHER multipleMedia OR single attachment
      final hasContent =
          (msg.multipleMedia != null && msg.multipleMedia!.isNotEmpty) ||
          (msg.attachmentUrl != null && msg.attachmentUrl!.isNotEmpty);

      if (matches && !hasContent) {}

      return matches && hasContent;
    }).toList();

    // Sort by timestamp (newest first)
    pendingMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    for (final msg in pendingMessages) {
      final isMulti =
          msg.multipleMedia != null && msg.multipleMedia!.isNotEmpty;
    }

    return pendingMessages;
  }

  /// Delete a pending message
  /// WHY: Remove from cache when upload completes
  Future<void> deletePendingMessage(String messageId) async {
    await _ensureInitialized();

    final msg = _messageBox!.get(messageId);
    if (msg != null && msg.isPending == true) {
      await _messageBox!.delete(messageId);
    }
  }

  /// Stream of messages for real-time updates
  /// WHY: UI can listen and auto-update when new messages arrive
  Stream<List<LocalMessage>> watchMessagesForChat(String chatId) async* {
    await _ensureInitialized();

    // Initial messages
    yield await getMessagesForChat(chatId);

    // Watch for changes
    await for (final _ in _messageBox!.watch()) {
      yield await getMessagesForChat(chatId);
    }
  }

  /// Ensure repository is initialized before operations
  Future<void> _ensureInitialized() async {
    if (_messageBox == null || !_messageBox!.isOpen) {
      await initialize();
    }
  }

  /// Close database (called on app shutdown)
  Future<void> close() async {
    await _messageBox?.close();
    await _indexBox?.close();
  }
}
