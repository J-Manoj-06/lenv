import 'package:flutter/material.dart';
import '../models/community_message_model.dart';
import '../models/media_metadata.dart';
import 'connectivity_service.dart';
import 'offline_cache_manager.dart';
import 'community_service.dart';

/// Offline support helpers for community service
class CommunityServiceOfflineSupport {
  /// Get community messages with offline fallback
  static Future<List<CommunityMessageModel>> getMessagesWithOfflineSupport({
    required String communityId,
    required CommunityService communityService,
  }) async {
    final connectivityService = ConnectivityService();

    if (connectivityService.isOnline) {
      try {
        // Online: try to get fresh data
        final stream = communityService.getMessagesStream(communityId);
        final messages = <CommunityMessageModel>[];

        await for (final list in stream.take(1)) {
          messages.addAll(list);
        }

        // Cache the data
        await _cacheMessages(communityId, messages);
        return messages;
      } catch (e) {
        // Fall through to cache
        debugPrint('Error fetching community messages online: $e');
      }
    }

    // Offline or online fetch failed: try cache
    return _getCachedMessages(communityId);
  }

  /// Cache community messages
  static Future<void> _cacheMessages(
    String communityId,
    List<CommunityMessageModel> messages,
  ) async {
    try {
      final cacheManager = OfflineCacheManager();
      final messagesList = messages.map((m) => _messageToMap(m)).toList();
      await cacheManager.cacheCommunityMessages(
        communityId: communityId,
        messages: messagesList,
      );
    } catch (e) {
      // Silent fail
    }
  }

  /// Get cached messages
  static Future<List<CommunityMessageModel>> _getCachedMessages(
    String communityId,
  ) async {
    try {
      final cacheManager = OfflineCacheManager();
      final cached = cacheManager.getCachedCommunityMessages(communityId);

      if (cached == null) return [];

      return cached
          .cast<Map<String, dynamic>>()
          .map((data) => _mapToMessage(data, communityId))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Convert message model to map for caching
  static Map<String, dynamic> _messageToMap(CommunityMessageModel message) {
    return {
      'messageId': message.messageId,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'senderAvatar': message.senderAvatar,
      'senderRole': message.senderRole,
      'content': message.content,
      'type': message.type,
      'createdAt': message.createdAt.toIso8601String(),
      'updatedAt': message.updatedAt?.toIso8601String(),
      'mediaMetadata': message.mediaMetadata != null
          ? {
              'r2Key': message.mediaMetadata!.r2Key,
              'publicUrl': message.mediaMetadata!.publicUrl,
              'mimeType': message.mediaMetadata!.mimeType,
              'fileSize': message.mediaMetadata!.fileSize,
              'messageId': message.mediaMetadata!.messageId,
            }
          : null,
      'deletedFor': message.deletedFor,
    };
  }

  /// Convert cached map back to message model
  static CommunityMessageModel _mapToMessage(
    Map<String, dynamic> data,
    String communityId,
  ) {
    return CommunityMessageModel(
      messageId: data['messageId'] ?? '',
      communityId: communityId,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderAvatar: data['senderAvatar'] ?? '',
      senderRole: data['senderRole'] ?? 'member',
      content: data['content'] ?? '',
      type: data['type'] ?? 'message',
      imageUrl: '',
      fileUrl: '',
      fileName: '',
      createdAt: DateTime.parse(
        data['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: data['updatedAt'] != null
          ? DateTime.parse(data['updatedAt'])
          : null,
      isEdited: false,
      isDeleted: false,
      isPinned: false,
      reactions: {},
      replyTo: '',
      replyCount: 0,
      isReported: false,
      reportCount: 0,
      mediaMetadata: data['mediaMetadata'] != null
          ? MediaMetadata.fromFirestore(
              data['mediaMetadata'] as Map<String, dynamic>,
            )
          : null,
      deletedFor: data['deletedFor'] != null
          ? List<String>.from(data['deletedFor'])
          : null,
    );
  }
}

/// Offline support for communities list
class CommunitiesOfflineSupport {
  /// Get communities with offline fallback
  static Future<List<Map<String, dynamic>>> getCommunitiesWithOfflineSupport({
    required String userId,
    required CommunityService communityService,
  }) async {
    final connectivityService = ConnectivityService();

    if (connectivityService.isOnline) {
      try {
        // Online: fetch fresh data
        final communities = await communityService.getMyComm(userId);
        final communitiesMap = communities
            .map((c) => c.toMap())
            .toList();
        await _cacheCommunities(userId, communitiesMap);
        return communitiesMap;
      } catch (e) {
        debugPrint('Error fetching communities online: $e');
      }
    }

    // Offline or failed: use cache
    return _getCachedCommunities(userId);
  }

  static Future<void> _cacheCommunities(
    String userId,
    List<Map<String, dynamic>> communities,
  ) async {
    try {
      final cacheManager = OfflineCacheManager();
      await cacheManager.cacheCommunities(
        userId: userId,
        communities: communities,
      );
    } catch (e) {
      // Silent fail
    }
  }

  static Future<List<Map<String, dynamic>>> _getCachedCommunities(
    String userId,
  ) async {
    try {
      final cacheManager = OfflineCacheManager();
      final cached = cacheManager.getCachedCommunities(userId);
      return cached ?? [];
    } catch (e) {
      return [];
    }
  }
}
