import 'package:flutter/material.dart';
import '../models/local_message.dart';
import '../repositories/local_message_repository.dart';
import '../services/firebase_message_sync_service.dart';

/// Helper mixin to add offline-first capabilities to existing chat pages
/// WHY: Makes migration easier - add this mixin to any chat page
mixin OfflineFirstChatMixin<T extends StatefulWidget> on State<T> {
  late LocalMessageRepository localRepo;
  late FirebaseMessageSyncService syncService;

  bool _isOfflineInitialized = false;

  /// Initialize offline-first for this chat
  /// Call this in initState()
  Future<void> initializeOfflineChat({
    required String chatId,
    required String chatType,
    required String userId,
  }) async {
    if (_isOfflineInitialized) return;

    // Initialize local repository
    localRepo = LocalMessageRepository();
    await localRepo.initialize();

    // Initialize sync service
    syncService = FirebaseMessageSyncService(localRepo);

    // Do initial sync (fetch recent messages from Firebase)
    await syncService.initialSyncForChat(
      chatId: chatId,
      chatType: chatType,
      limit: 100,
    );

    // Start real-time sync
    await syncService.startSyncForChat(
      chatId: chatId,
      chatType: chatType,
      userId: userId,
    );

    _isOfflineInitialized = true;

    if (mounted) {
      setState(() {});
    }
  }

  /// Get messages stream from local DB
  /// Use this instead of Firebase StreamBuilder
  Stream<List<LocalMessage>> getMessagesStream(String chatId) {
    return localRepo.watchMessagesForChat(chatId);
  }

  /// Search messages offline
  Future<List<LocalMessage>> searchMessagesOffline(
    String query,
    String chatId,
  ) async {
    return await localRepo.searchMessages(query, chatId: chatId, limit: 500);
  }

  /// Send message (handles both Firebase and local save)
  Future<void> sendMessageOffline({
    required String chatId,
    required String chatType,
    required String senderId,
    required String senderName,
    String? messageText,
    String? attachmentUrl,
    String? attachmentType,
    Map<String, dynamic>? pollData,
  }) async {
    await syncService.sendMessage(
      chatId: chatId,
      chatType: chatType,
      senderId: senderId,
      senderName: senderName,
      messageText: messageText,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      pollData: pollData,
    );
  }

  /// Stop sync when leaving chat
  /// Call this in dispose()
  Future<void> disposeOfflineChat(String chatId) async {
    await syncService.stopSyncForChat(chatId);
  }
}
