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
    print('\n========================================');
    print('🔄 FORCE RESYNC DEBUG');
    print('========================================\n');

    final localRepo = LocalMessageRepository();
    await localRepo.initialize();

    // Clear existing messages for this chat
    print('🗑️ Clearing existing messages for chat: $chatId');
    await localRepo.clearChatMessages(chatId);

    // Force re-sync from Firebase with MUCH higher limit and no orderBy
    final syncService = FirebaseMessageSyncService(localRepo);
    print('📥 Force fetching from Firebase with debug logging...\n');

    await syncService.initialSyncForChat(
      chatId: chatId,
      chatType: chatType,
      limit: 200, // Increased limit
      forceResync: true,
    );

    // Check what we got
    final messages = await localRepo.getMessagesForChat(chatId);
    final withAttachments = messages.where((m) => m.hasAttachment()).toList();

    print('\n========================================');
    print('📊 RESYNC RESULTS');
    print('========================================');
    print('Total messages synced: ${messages.length}');
    print('Messages with attachments: ${withAttachments.length}');

    if (withAttachments.isNotEmpty) {
      print('\n📎 Attachments found:');
      for (var i = 0; i < withAttachments.length; i++) {
        final msg = withAttachments[i];
        print('  [$i] ${msg.getFileName()}');
        print('      Type: ${msg.attachmentType}');
        print('      URL: ${msg.attachmentUrl}');
      }
    } else {
      print('\n❌ NO ATTACHMENTS FOUND!');
      print('This means Firebase messages don\'t have attachment fields.');
      print('\n💡 POSSIBLE REASONS:');
      print(
        '1. PDF messages might not have createdAt field (excluded from query)',
      );
      print('2. PDF messages are stored in a different collection');
      print('3. PDF messages use different field names');
      print('\n👉 Check Firebase console at:');
      print('   classes/$chatId/messages');
      print('   Look for documents with PDF/file data');
    }

    print('========================================\n');

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
