/// Unified chat configuration for unread count system
/// 
/// Maps chat types to their Firestore collections and IDs
class ChatTypeConfig {
  // Group chats
  static const String groupChat = 'group';
  // Student group chats live under classes/{classId}/subjects/{subjectId}/messages
  // We encode chatId as "{classId}|{subjectId}" for unread count APIs
  static const String groupMessagesCollection = 'classes/{classId}/subjects/{subjectId}/messages';
  
  // Community chats
  static const String communityChat = 'community';
  static const String communityMessagesCollection = 'communities/{communityId}/messages';
  
  // Parent-Teacher individual chats
  static const String individualChat = 'individual';
  static const String individualMessagesCollection = 'chats/{chatId}/messages';
  
  // Parent-Teacher group chats
  static const String ptGroupChat = 'ptGroup';
  static const String ptGroupMessagesCollection = 'ptGroups/{groupId}/messages';
  
  /// Get messages collection path for a chat type
  static String getMessagesCollectionPath({
    required String chatType,
    required String chatId,
  }) {
    switch (chatType) {
      case groupChat:
        // Expect chatId formatted as "classId|subjectId"
        final parts = chatId.split('|');
        if (parts.length == 2) {
          final classId = parts[0];
          final subjectId = parts[1];
          return groupMessagesCollection
              .replaceFirst('{classId}', classId)
              .replaceFirst('{subjectId}', subjectId);
        }
        // Fallback: treat chatId as a groupId (legacy)
        return 'groups/$chatId/messages';
      case communityChat:
        return communityMessagesCollection.replaceFirst('{communityId}', chatId);
      case individualChat:
        return individualMessagesCollection.replaceFirst('{chatId}', chatId);
      case ptGroupChat:
        return ptGroupMessagesCollection.replaceFirst('{groupId}', chatId);
      default:
        return '';
    }
  }
  
  /// All supported chat types
  static const List<String> allChatTypes = [
    groupChat,
    communityChat,
    individualChat,
    ptGroupChat,
  ];
}
