import '../models/local_message.dart';
import '../repositories/local_message_repository.dart';

/// Debug utility to inspect local message database
class DebugLocalMessages {
  static Future<void> printDatabaseStats() async {
    final repo = LocalMessageRepository();
    await repo.initialize();

    // Get all messages
    final allMessages = await repo.searchMessages('', limit: 10000);

    // Group by chat
    final chatGroups = <String, List<LocalMessage>>{};
    for (var msg in allMessages) {
      chatGroups.putIfAbsent(msg.chatId, () => []).add(msg);
    }

    for (var entry in chatGroups.entries) {
      final chatId = entry.key;
      final messages = entry.value;
      final withAttachments = messages.where((m) => m.hasAttachment()).length;
    }

    // Find all messages with attachments
    final messagesWithAttachments = allMessages
        .where((m) => m.hasAttachment())
        .toList();

    if (messagesWithAttachments.isNotEmpty) {
      final types = <String, int>{};
      for (var msg in messagesWithAttachments) {
        final type = msg.attachmentType ?? 'unknown';
        types[type] = (types[type] ?? 0) + 1;
      }
      for (var entry in types.entries) {}

      for (var i = 0; i < messagesWithAttachments.take(10).length; i++) {
        final msg = messagesWithAttachments[i];
      }
    }
  }

  static Future<void> testFileSearch(String query, String? chatId) async {
    final repo = LocalMessageRepository();
    await repo.initialize();

    final results = await repo.searchFilesAndMedia(query, chatId: chatId);

    if (results.isNotEmpty) {
      for (var i = 0; i < results.take(10).length; i++) {
        final msg = results[i];
      }
    } else {
      // Try to understand why
      final allInChat = chatId != null
          ? await repo.getMessagesForChat(chatId)
          : await repo.searchMessages('', limit: 10000);

      final withAttachments = allInChat
          .where((m) => m.hasAttachment())
          .toList();

      if (withAttachments.isNotEmpty) {
        final first = withAttachments.first;
      }
    }
  }
}
