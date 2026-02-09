import '../models/local_message.dart';
import '../repositories/local_message_repository.dart';

/// Debug utility to inspect local message database
class DebugLocalMessages {
  static Future<void> printDatabaseStats() async {
    final repo = LocalMessageRepository();
    await repo.initialize();

    print('\n========== LOCAL MESSAGE DATABASE STATS ==========');
    print('Total messages: ${await repo.getTotalMessageCount()}');

    // Get all messages
    final allMessages = await repo.searchMessages('', limit: 10000);
    print('Total accessible messages: ${allMessages.length}');

    // Group by chat
    final chatGroups = <String, List<LocalMessage>>{};
    for (var msg in allMessages) {
      chatGroups.putIfAbsent(msg.chatId, () => []).add(msg);
    }

    print('\nMessages per chat:');
    for (var entry in chatGroups.entries) {
      final chatId = entry.key;
      final messages = entry.value;
      final withAttachments = messages.where((m) => m.hasAttachment()).length;
      print(
        '  $chatId: ${messages.length} messages, $withAttachments with attachments',
      );
    }

    // Find all messages with attachments
    final messagesWithAttachments = allMessages
        .where((m) => m.hasAttachment())
        .toList();
    print(
      '\nTotal messages with attachments: ${messagesWithAttachments.length}',
    );

    if (messagesWithAttachments.isNotEmpty) {
      print('\nAttachment types:');
      final types = <String, int>{};
      for (var msg in messagesWithAttachments) {
        final type = msg.attachmentType ?? 'unknown';
        types[type] = (types[type] ?? 0) + 1;
      }
      for (var entry in types.entries) {
        print('  ${entry.key}: ${entry.value} files');
      }

      print('\nSample attachments:');
      for (var i = 0; i < messagesWithAttachments.take(10).length; i++) {
        final msg = messagesWithAttachments[i];
        print('  [$i] Chat: ${msg.chatId}');
        print('      Type: ${msg.attachmentType}');
        print('      File: ${msg.getFileName()}');
        print('      URL: ${msg.attachmentUrl?.substring(0, 80)}...');
      }
    }

    print('==================================================\n');
  }

  static Future<void> testFileSearch(String query, String? chatId) async {
    final repo = LocalMessageRepository();
    await repo.initialize();

    print('\n========== FILE SEARCH TEST ==========');
    print('Query: "$query"');
    print('ChatId: ${chatId ?? "all chats"}');

    final results = await repo.searchFilesAndMedia(query, chatId: chatId);

    print('Results: ${results.length} files found');

    if (results.isNotEmpty) {
      print('\nMatching files:');
      for (var i = 0; i < results.take(10).length; i++) {
        final msg = results[i];
        print('  [$i] ${msg.getFileName()}');
        print('      Type: ${msg.attachmentType}');
        print('      Chat: ${msg.chatId}');
      }
    } else {
      print('No files found!');

      // Try to understand why
      final allInChat = chatId != null
          ? await repo.getMessagesForChat(chatId)
          : await repo.searchMessages('', limit: 10000);

      final withAttachments = allInChat
          .where((m) => m.hasAttachment())
          .toList();
      print('\nDebug info:');
      print('  Total messages in chat: ${allInChat.length}');
      print('  Messages with attachments: ${withAttachments.length}');

      if (withAttachments.isNotEmpty) {
        print('\n  Testing first attachment against query:');
        final first = withAttachments.first;
        print('    File: ${first.getFileName()}');
        print('    Type: ${first.attachmentType}');
        print('    Matches search: ${first.matchesFileSearch(query)}');
      }
    }

    print('======================================\n');
  }
}
