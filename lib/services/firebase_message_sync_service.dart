import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/local_message.dart';
import '../repositories/local_message_repository.dart';

/// Firebase sync service - ONLY for syncing, NOT for search
/// WHY: Separation of concerns - Firebase handles sync, local DB handles everything else
class FirebaseMessageSyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalMessageRepository _localRepo;

  // Active listeners for cleanup
  final Map<String, StreamSubscription> _activeListeners = {};

  FirebaseMessageSyncService(this._localRepo);

  /// Start syncing messages for a chat
  /// WHY: Listen to Firebase and save new messages to local DB
  /// This runs in background and keeps local DB up-to-date
  Future<void> startSyncForChat({
    required String chatId,
    required String chatType, // 'staff_room', 'community', 'private'
    required String userId,
  }) async {
    // Don't start if already listening
    if (_activeListeners.containsKey(chatId)) {
      print('⚠️ Already syncing chat: $chatId');
      return;
    }

    print('🔄 Starting sync for chat: $chatId ($chatType)');

    // Get the appropriate collection path based on chat type
    final Query messagesQuery = _getMessagesQuery(chatId, chatType);

    // Listen to real-time updates
    late StreamSubscription subscription;
    subscription = messagesQuery.snapshots().listen(
      (snapshot) async {
        final List<LocalMessage> newMessages = [];

        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added ||
              change.type == DocumentChangeType.modified) {
            final doc = change.doc;
            final data = doc.data() as Map<String, dynamic>;

            // Check if message already exists locally
            final exists = await _localRepo.hasMessage(doc.id);
            if (!exists || change.type == DocumentChangeType.modified) {
              final localMessage = LocalMessage.fromFirestore(
                data,
                doc.id,
                chatId,
                chatType,
              );

              newMessages.add(localMessage);
            }
          } else if (change.type == DocumentChangeType.removed) {
            // Handle deleted messages
            await _localRepo.deleteMessage(change.doc.id);
          }
        }

        // Batch save new messages
        if (newMessages.isNotEmpty) {
          await _localRepo.saveMessages(newMessages);
          print('✅ Synced ${newMessages.length} messages for chat: $chatId');
        }
      },
      onError: (error) {
        print('❌ Sync error for chat $chatId: $error');
        if (error is FirebaseException && error.code == 'permission-denied') {
          print(
            '🚫 Stopping sync listener for $chatId due to permission-denied',
          );
          subscription.cancel();
          _activeListeners.remove(chatId);
        }
      },
    );

    _activeListeners[chatId] = subscription;
  }

  /// Initial sync - fetch recent messages and save to local DB
  /// WHY: On first launch or after logout, populate local DB with recent messages
  Future<void> initialSyncForChat({
    required String chatId,
    required String chatType,
    int limit = 100, // Fetch last 100 messages
    bool forceResync = false, // Force re-fetch even if messages exist
  }) async {
    print('📥 Initial sync for chat: $chatId ($chatType)');
    if (forceResync) {
      print('   ⚠️ FORCE RESYNC - will re-save all messages');
    }

    try {
      // First try with ordering
      Query messagesQuery = _getMessagesQuery(
        chatId,
        chatType,
      ).orderBy('createdAt', descending: true).limit(limit);

      print('   Fetching messages from Firebase...');
      var snapshot = await messagesQuery.get();
      print('   Fetched ${snapshot.docs.length} documents with orderBy');

      // If we got fewer messages than expected, try without ordering
      // (some messages might not have createdAt field)
      if (snapshot.docs.length < 10) {
        print('   ⚠️ Few messages found, trying without orderBy...');
        messagesQuery = _getMessagesQuery(chatId, chatType).limit(limit);
        snapshot = await messagesQuery.get();
        print('   Fetched ${snapshot.docs.length} documents without orderBy');
      }

      final List<LocalMessage> messages = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Debug: Log message data to see what fields we're getting
        print('   📄 Doc ${doc.id}:');
        print('      text: ${data['text'] ?? data['message'] ?? '[none]'}');
        print('      attachmentUrl: ${data['attachmentUrl'] ?? '[none]'}');
        print('      mediaUrl: ${data['mediaUrl'] ?? '[none]'}');
        print('      imageUrl: ${data['imageUrl'] ?? '[none]'}');
        print('      fileUrl: ${data['fileUrl'] ?? '[none]'}');
        print('      attachmentType: ${data['attachmentType'] ?? '[none]'}');
        print('      mediaType: ${data['mediaType'] ?? '[none]'}');
        print('      type: ${data['type'] ?? '[none]'}');

        // 🔍 NEW: Check for mediaMetadata field (PDFs and files)
        if (data['mediaMetadata'] != null) {
          final media = data['mediaMetadata'] as Map<String, dynamic>?;
          print('      📎 mediaMetadata found!');
          print('         publicUrl: ${media?['publicUrl'] ?? '[none]'}');
          print('         mimeType: ${media?['mimeType'] ?? '[none]'}');
          print(
            '         originalFileName: ${media?['originalFileName'] ?? '[none]'}',
          );
        }

        print('      Available keys: ${data.keys.toList()}');

        // Only save if not already in local DB (or force resync)
        final exists = await _localRepo.hasMessage(doc.id);
        if (!exists || forceResync) {
          final localMessage = LocalMessage.fromFirestore(
            data,
            doc.id,
            chatId,
            chatType,
          );
          messages.add(localMessage);

          // Show what was saved
          print(
            '      ✅ Saved with attachmentUrl: ${localMessage.attachmentUrl}',
          );
          print(
            '      ✅ Saved with attachmentType: ${localMessage.attachmentType}',
          );

          final preview =
              localMessage.messageText?.substring(
                0,
                localMessage.messageText!.length > 30
                    ? 30
                    : localMessage.messageText!.length,
              ) ??
              '[no text]';
          print('      📝 Message ${doc.id}: "$preview..."');
        }
      }

      if (messages.isNotEmpty) {
        print('   💾 Saving ${messages.length} new messages to local DB...');
        await _localRepo.saveMessages(messages);
        print('✅ Initial sync complete: ${messages.length} messages saved');
      } else {
        print('✅ Initial sync complete: All messages already cached');
      }
    } catch (e) {
      print('❌ Initial sync failed: $e');
      if (e is FirebaseException && e.code == 'permission-denied') {
        print(
          '🚫 Permission denied for $chatType/$chatId. Using local cache only.',
        );
        return;
      }
      rethrow;
    }
  }

  /// Stop syncing a specific chat
  /// WHY: Clean up resources when user leaves chat
  Future<void> stopSyncForChat(String chatId) async {
    final subscription = _activeListeners.remove(chatId);
    await subscription?.cancel();
    print('⏹️ Stopped sync for chat: $chatId');
  }

  /// Sync only new messages since last cached timestamp
  /// WHY: Efficient background sync - only fetch messages we don't have
  Future<void> syncNewMessages({
    required String chatId,
    required String chatType,
    required int lastTimestamp,
  }) async {
    try {
      print(
        '🔄 Syncing new messages since ${DateTime.fromMillisecondsSinceEpoch(lastTimestamp)}',
      );

      final Query messagesQuery = _getMessagesQuery(chatId, chatType)
          .where('createdAt', isGreaterThan: lastTimestamp)
          .orderBy('createdAt', descending: false)
          .limit(100);

      final snapshot = await messagesQuery.get();

      if (snapshot.docs.isEmpty) {
        print('✅ Already up to date - no new messages');
        return;
      }

      final List<LocalMessage> newMessages = [];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final exists = await _localRepo.hasMessage(doc.id);

        if (!exists) {
          final localMessage = LocalMessage.fromFirestore(
            data,
            doc.id,
            chatId,
            chatType,
          );
          newMessages.add(localMessage);
        }
      }

      if (newMessages.isNotEmpty) {
        await _localRepo.saveMessages(newMessages);
        print('✅ Synced ${newMessages.length} new messages');
      }
    } catch (e) {
      print('⚠️ Background sync failed (offline?): $e');
    }
  }

  /// Load older messages (pagination)
  /// WHY: Don't load all messages at once - load on demand when user scrolls up
  Future<List<LocalMessage>> loadOlderMessages({
    required String chatId,
    required String chatType,
    required int beforeTimestamp,
    int limit = 50,
  }) async {
    try {
      print(
        '📜 Loading older messages before ${DateTime.fromMillisecondsSinceEpoch(beforeTimestamp)}',
      );

      final Query messagesQuery = _getMessagesQuery(chatId, chatType)
          .where('createdAt', isLessThan: beforeTimestamp)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final snapshot = await messagesQuery.get();
      final List<LocalMessage> olderMessages = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Save to cache
        final localMessage = LocalMessage.fromFirestore(
          data,
          doc.id,
          chatId,
          chatType,
        );
        olderMessages.add(localMessage);
      }

      if (olderMessages.isNotEmpty) {
        await _localRepo.saveMessages(olderMessages);
        print('✅ Loaded ${olderMessages.length} older messages');
      }

      return olderMessages;
    } catch (e) {
      print('❌ Failed to load older messages: $e');
      return [];
    }
  }

  /// Stop all active syncs
  /// WHY: Called on logout to stop all background listeners
  Future<void> stopAllSyncs() async {
    for (final subscription in _activeListeners.values) {
      await subscription.cancel();
    }
    _activeListeners.clear();
    print('⏹️ Stopped all sync listeners');
  }

  /// Send a new message to Firebase (and auto-save locally)
  /// WHY: User sends message -> goes to Firebase -> sync listener saves to local DB
  Future<void> sendMessage({
    required String chatId,
    required String chatType,
    required String senderId,
    required String senderName,
    String? messageText,
    String? attachmentUrl,
    String? attachmentType,
    Map<String, dynamic>? pollData,
  }) async {
    try {
      final CollectionReference messagesRef = _getMessagesCollection(
        chatId,
        chatType,
      );

      final messageData = {
        'senderId': senderId,
        'senderName': senderName,
        'text': messageText,
        'message': messageText,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'attachmentUrl': attachmentUrl,
        'mediaUrl': attachmentUrl,
        'attachmentType': attachmentType,
        'mediaType': attachmentType,
        'poll': pollData,
        'isDeleted': false,
      };

      final docRef = await messagesRef.add(messageData);

      // Immediately save to local DB (don't wait for sync)
      final localMessage = LocalMessage(
        messageId: docRef.id,
        chatId: chatId,
        chatType: chatType,
        senderId: senderId,
        senderName: senderName,
        messageText: messageText,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
        pollData: pollData,
        isDeleted: false,
      );

      await _localRepo.saveMessage(localMessage);

      print('✅ Message sent and saved locally');
    } catch (e) {
      print('❌ Failed to send message: $e');
      rethrow;
    }
  }

  /// Get the messages query based on chat type
  Query _getMessagesQuery(String chatId, String chatType) {
    switch (chatType) {
      case 'staff_room':
        return _firestore
            .collection('staff_rooms')
            .doc(chatId)
            .collection('messages');

      case 'community':
        return _firestore
            .collection('communities')
            .doc(chatId)
            .collection('messages');

      case 'group':
        // Group chat: classId_subjectId format
        final parts = chatId.split('_');
        if (parts.length < 2) {
          throw Exception('Invalid group chat ID format: $chatId');
        }
        final classId = parts[0];
        final subjectId = parts
            .sublist(1)
            .join('_'); // Handle underscores in subject ID
        return _firestore
            .collection('classes')
            .doc(classId)
            .collection('subjects')
            .doc(subjectId)
            .collection('messages');

      case 'parent_group':
        // Parent-teacher group: uses parent_teacher_groups collection
        return _firestore
            .collection('parent_teacher_groups')
            .doc(chatId)
            .collection('messages');

      case 'private':
        // Private chat: uses conversations collection (teacher-parent individual chat)
        return _firestore
            .collection('conversations')
            .doc(chatId)
            .collection('messages');

      default:
        throw Exception('Unknown chat type: $chatType');
    }
  }

  /// Get the messages collection reference
  CollectionReference _getMessagesCollection(String chatId, String chatType) {
    switch (chatType) {
      case 'staff_room':
        return _firestore
            .collection('staff_rooms')
            .doc(chatId)
            .collection('messages');

      case 'community':
        return _firestore
            .collection('communities')
            .doc(chatId)
            .collection('messages');

      case 'group':
        // Group chat: classId_subjectId format
        final parts = chatId.split('_');
        if (parts.length < 2) {
          throw Exception('Invalid group chat ID format: $chatId');
        }
        final classId = parts[0];
        final subjectId = parts.sublist(1).join('_');
        return _firestore
            .collection('classes')
            .doc(classId)
            .collection('subjects')
            .doc(subjectId)
            .collection('messages');

      case 'parent_group':
        // Parent-teacher group: uses parent_teacher_groups collection
        return _firestore
            .collection('parent_teacher_groups')
            .doc(chatId)
            .collection('messages');

      case 'private':
        // Private chat: uses conversations collection (teacher-parent individual chat)
        return _firestore
            .collection('conversations')
            .doc(chatId)
            .collection('messages');

      default:
        throw Exception('Unknown chat type: $chatType');
    }
  }
}
