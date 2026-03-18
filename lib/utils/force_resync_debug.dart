import 'package:flutter/material.dart';
import '../repositories/local_message_repository.dart';
import '../services/firebase_message_sync_service.dart';

/// Debug utility to force re-sync messages from Firebase
/// This will help identify what fields Firebase actually has
class ForceResyncDebug {
  static Future<void> forceResyncChat({
    required BuildContext context,
    required String chatId,
    required String chatType,
  }) async {
    final localRepo = LocalMessageRepository();
    await localRepo.initialize();

    // Clear existing messages for this chat
    await localRepo.clearChatMessages(chatId);

    // Force re-sync from Firebase with MUCH higher limit and no orderBy
    final syncService = FirebaseMessageSyncService(localRepo);

    await syncService.initialSyncForChat(
      chatId: chatId,
      chatType: chatType,
      limit: 200, // Increased limit
      forceResync: true,
    );

    // Check what we got
    final messages = await localRepo.getMessagesForChat(chatId);
    final withAttachments = messages.where((m) => m.hasAttachment()).toList();

    if (withAttachments.isNotEmpty) {
      for (var i = 0; i < withAttachments.length; i++) {
        final msg = withAttachments[i];
      }
    } else {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Resync complete: ${messages.length} messages, '
            '${withAttachments.length} with attachments',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
