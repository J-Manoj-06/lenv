import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/local_message.dart';
import '../repositories/local_message_repository.dart';
import 'cloudflare_notification_service.dart';

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
      return;
    }

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
        }
      },
      onError: (error) {
        if (error is FirebaseException && error.code == 'permission-denied') {
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
    if (forceResync) {}

    try {
      // First try with ordering
      Query messagesQuery = _getMessagesQuery(
        chatId,
        chatType,
      ).orderBy('createdAt', descending: true).limit(limit);

      var snapshot = await messagesQuery.get();

      // If we got fewer messages than expected, try without ordering
      // (some messages might not have createdAt field)
      if (snapshot.docs.length < 10) {
        messagesQuery = _getMessagesQuery(chatId, chatType).limit(limit);
        snapshot = await messagesQuery.get();
      }

      final List<LocalMessage> messages = [];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Debug: Log message data to see what fields we're getting

        // 🔍 NEW: Check for mediaMetadata field (PDFs and files)
        if (data['mediaMetadata'] != null) {
          final media = data['mediaMetadata'] as Map<String, dynamic>?;
        }

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

          final preview =
              localMessage.messageText?.substring(
                0,
                localMessage.messageText!.length > 30
                    ? 30
                    : localMessage.messageText!.length,
              ) ??
              '[no text]';
        }
      }

      if (messages.isNotEmpty) {
        await _localRepo.saveMessages(messages);
      } else {}
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
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
  }

  /// Sync only new messages since last cached timestamp
  /// WHY: Efficient background sync - only fetch messages we don't have
  Future<void> syncNewMessages({
    required String chatId,
    required String chatType,
    required int lastTimestamp,
  }) async {
    try {
      final Query messagesQuery = _getMessagesQuery(chatId, chatType)
          .where('createdAt', isGreaterThan: lastTimestamp)
          .orderBy('createdAt', descending: false)
          .limit(100);

      final snapshot = await messagesQuery.get();

      if (snapshot.docs.isEmpty) {
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
      }
    } catch (e) {}
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
      }

      return olderMessages;
    } catch (e) {
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

      switch (chatType) {
        case 'private':
          unawaited(
            _notifyPrivateMessage(
              chatId: chatId,
              messageId: docRef.id,
              senderId: senderId,
              text: messageText ?? '',
              messageType: attachmentType ?? 'text',
            ),
          );
          break;
        case 'parent_group':
          unawaited(
            _notifyParentGroupMessage(
              groupId: chatId,
              messageId: docRef.id,
              senderId: senderId,
              senderName: senderName,
              content: messageText ?? '',
              messageType: attachmentType ?? 'text',
            ),
          );
          break;
        case 'community':
          unawaited(
            _notifyCommunityMessage(
              communityId: chatId,
              messageId: docRef.id,
              senderId: senderId,
              senderName: senderName,
              content: messageText ?? '',
              messageType: attachmentType ?? 'text',
            ),
          );
          break;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _notifyPrivateMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String text,
    required String messageType,
  }) async {
    try {
      final conversation = await _firestore
          .collection('conversations')
          .doc(chatId)
          .get();
      final data = conversation.data() ?? const <String, dynamic>{};
      final teacherId = (data['teacherId'] ?? '').toString();
      final parentId = (data['parentId'] ?? '').toString();
      final recipientId = senderId == teacherId ? parentId : teacherId;
      if (recipientId.isEmpty) return;

      await CloudflareNotificationService.sendDirectChatNotification(
        messageId: messageId,
        senderId: senderId,
        recipientId: recipientId,
        text: text,
        messageType: messageType,
        deepLinkRoute: '/messages',
        metadata: {'conversationId': chatId, 'chatType': 'direct'},
      );
    } catch (e) {
      debugPrint('Cloudflare private sync notification failed: $e');
    }
  }

  Future<void> _notifyParentGroupMessage({
    required String groupId,
    required String messageId,
    required String senderId,
    required String senderName,
    required String content,
    required String messageType,
  }) async {
    try {
      final groupSnapshot = await _firestore
          .collection('parent_teacher_groups')
          .doc(groupId)
          .get();
      final groupData = groupSnapshot.data() ?? const <String, dynamic>{};
      final schoolCode =
          (groupData['schoolCode'] ??
                  groupData['schoolId'] ??
                  groupData['instituteId'] ??
                  '')
              .toString();
      final className = (groupData['className'] ?? '').toString();
      final section = (groupData['section'] ?? '').toString();
      final normalizedClass = _normalizeClassName(className).toLowerCase();

      final usersSnapshot = await _firestore.collection('users').get();
      final recipientIds = usersSnapshot.docs
          .where((doc) {
            if (doc.id == senderId) return false;
            final data = doc.data();
            final role = (data['role'] ?? '').toString().toLowerCase();
            if (role != 'parent' && role != 'teacher') return false;

            final userSchool =
                (data['schoolCode'] ??
                        data['schoolId'] ??
                        data['instituteId'] ??
                        '')
                    .toString();
            if (schoolCode.isNotEmpty && userSchool != schoolCode) return false;

            final userClass = _normalizeClassName(
              (data['className'] ?? data['class'] ?? data['standard'] ?? '')
                  .toString(),
            ).toLowerCase();
            if (normalizedClass.isNotEmpty && userClass != normalizedClass) {
              return false;
            }

            final userSection = (data['section'] ?? '').toString();
            if (section.isNotEmpty && userSection != section) return false;
            return true;
          })
          .map((doc) => doc.id)
          .toList();

      if (recipientIds.isEmpty) return;

      await CloudflareNotificationService.sendGroupMessageNotification(
        messageId: messageId,
        senderId: senderId,
        senderName: senderName,
        senderRole: '',
        groupType: 'parent_teacher_group',
        groupId: groupId,
        recipientIds: recipientIds,
        content: content,
        messageType: messageType,
        groupName: groupData['name']?.toString(),
        deepLinkRoute: '/notifications',
        metadata: {
          'className': className,
          'section': section,
          'schoolCode': schoolCode,
        },
      );
    } catch (e) {
      debugPrint('Cloudflare parent group sync notification failed: $e');
    }
  }

  Future<void> _notifyCommunityMessage({
    required String communityId,
    required String messageId,
    required String senderId,
    required String senderName,
    required String content,
    required String messageType,
  }) async {
    try {
      final membersSnapshot = await _firestore
          .collection('communities')
          .doc(communityId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .get();
      final recipientIds = membersSnapshot.docs
          .map((doc) => doc.data()['userId']?.toString() ?? doc.id)
          .where((userId) => userId.isNotEmpty && userId != senderId)
          .toSet()
          .toList();
      if (recipientIds.isEmpty) return;

      await CloudflareNotificationService.sendGroupMessageNotification(
        messageId: messageId,
        senderId: senderId,
        senderName: senderName,
        senderRole: '',
        groupType: 'community',
        groupId: communityId,
        recipientIds: recipientIds,
        content: content,
        messageType: messageType,
        deepLinkRoute: '/notifications',
        metadata: {'communityId': communityId},
      );
    } catch (e) {
      debugPrint('Cloudflare community sync notification failed: $e');
    }
  }

  String _normalizeClassName(String className) {
    final trimmed = className.trim();
    if (trimmed.isEmpty) return '';

    final digitMatch = RegExp(r'\d+').firstMatch(trimmed);
    if (digitMatch != null) {
      return digitMatch.group(0)!;
    }

    return trimmed
        .replaceAll(RegExp(r'(?i)grade\s+'), '')
        .replaceAll(RegExp(r'(?i)class\s+'), '')
        .trim();
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
