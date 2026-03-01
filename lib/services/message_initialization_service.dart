import 'package:flutter/foundation.dart';
import '../models/cached_media_message.dart';
import '../models/media_metadata.dart';
import '../services/media_cache_service.dart';

/// Message Initialization Service
/// STEP 3 & 8: Handles checking local cache when messages load
/// Supports logout/login scenarios - always checks local storage first
class MessageInitializationService {
  final MediaCacheService _cacheService = MediaCacheService();

  /// Initialize a media message by checking local cache
  /// This should be called whenever a message is loaded from Firestore
  Future<CachedMediaMessage> initializeMediaMessage(
    CachedMediaMessage message,
  ) async {
    try {
      // Skip if already marked as downloaded
      if (message.isDownloaded && message.localPath != null) {
        return message;
      }

      // Generate expected local path
      final mediaType = _mapCategoryToType(message.mediaType);
      final extension = _getExtension(message.fileName);

      final expectedPath = await _cacheService.getLocalFilePath(
        messageId: message.messageId,
        mediaType: mediaType,
        extension: extension,
      );

      // Check if file exists locally
      final exists = await _cacheService.checkIfMediaExists(expectedPath);

      if (exists) {
        debugPrint('Media found locally: ${message.messageId}');
        // Update message with local path
        return message.copyWith(localPath: expectedPath, isDownloaded: true);
      } else {
        debugPrint('Media not found locally: ${message.messageId}');
        // Return original message (download button will be shown)
        return message;
      }
    } catch (e) {
      debugPrint('Error initializing media message: $e');
      return message;
    }
  }

  /// Batch initialize multiple media messages
  /// Efficient for loading chat history
  Future<List<CachedMediaMessage>> initializeMediaMessages(
    List<CachedMediaMessage> messages,
  ) async {
    final initializedMessages = <CachedMediaMessage>[];

    for (final message in messages) {
      final initialized = await initializeMediaMessage(message);
      initializedMessages.add(initialized);
    }

    return initializedMessages;
  }

  /// Initialize MediaMetadata by checking local cache
  /// Used for existing MediaMetadata objects in the app
  Future<MediaMetadata> initializeMediaMetadata(MediaMetadata metadata) async {
    try {
      // Skip if already has local path
      if (metadata.hasLocalFile) {
        return metadata;
      }

      // Determine media type from MIME type
      final mediaType = MediaTypeExtension.fromMimeType(
        metadata.mimeType ?? 'application/octet-stream',
      );

      // Get extension from original filename or MIME type
      final extension = _getExtensionFromMetadata(metadata);

      // Generate expected local path
      final expectedPath = await _cacheService.getLocalFilePath(
        messageId: metadata.messageId,
        mediaType: mediaType,
        extension: extension,
      );

      // Check if exists
      final exists = await _cacheService.checkIfMediaExists(expectedPath);

      if (exists) {
        return metadata.copyWith(localPath: expectedPath);
      }

      return metadata;
    } catch (e) {
      debugPrint('Error initializing media metadata: $e');
      return metadata;
    }
  }

  /// Batch initialize MediaMetadata objects
  Future<List<MediaMetadata>> initializeMediaMetadataList(
    List<MediaMetadata> metadataList,
  ) async {
    final initialized = <MediaMetadata>[];

    for (final metadata in metadataList) {
      final init = await initializeMediaMetadata(metadata);
      initialized.add(init);
    }

    return initialized;
  }

  /// Refresh media availability for a conversation
  /// Useful after logout/login or app restart
  Future<Map<String, bool>> checkMediaAvailability(
    List<String> messageIds,
    MediaTypeCategory mediaCategory,
  ) async {
    final availability = <String, bool>{};
    final mediaType = _mapCategoryToType(mediaCategory);

    for (final messageId in messageIds) {
      try {
        final expectedPath = await _cacheService.getLocalFilePath(
          messageId: messageId,
          mediaType: mediaType,
        );

        final exists = await _cacheService.checkIfMediaExists(expectedPath);
        availability[messageId] = exists;
      } catch (e) {
        availability[messageId] = false;
      }
    }

    return availability;
  }

  /// Get statistics on cached media for a conversation
  Future<ConversationCacheStats> getConversationCacheStats(
    List<CachedMediaMessage> messages,
  ) async {
    int totalMedia = messages.length;
    int cachedMedia = 0;
    int totalSize = 0;

    for (final message in messages) {
      // Check if exists locally
      final initialized = await initializeMediaMessage(message);

      if (initialized.isDownloaded && initialized.localPath != null) {
        cachedMedia++;

        // Get file size
        final size = await _cacheService.getFileSize(initialized.localPath!);
        if (size != null) {
          totalSize += size;
        }
      }
    }

    return ConversationCacheStats(
      totalMedia: totalMedia,
      cachedMedia: cachedMedia,
      uncachedMedia: totalMedia - cachedMedia,
      totalCacheSize: totalSize,
      cachePercentage: totalMedia > 0 ? (cachedMedia / totalMedia) * 100 : 0,
    );
  }

  MediaType _mapCategoryToType(MediaTypeCategory category) {
    switch (category) {
      case MediaTypeCategory.image:
        return MediaType.image;
      case MediaTypeCategory.audio:
        return MediaType.audio;
      case MediaTypeCategory.pdf:
        return MediaType.pdf;
      case MediaTypeCategory.document:
        return MediaType.document;
    }
  }

  String? _getExtension(String fileName) {
    if (fileName.contains('.')) {
      return '.${fileName.split('.').last}';
    }
    return null;
  }

  String? _getExtensionFromMetadata(MediaMetadata metadata) {
    // Try from original filename first
    if (metadata.originalFileName != null &&
        metadata.originalFileName!.contains('.')) {
      return '.${metadata.originalFileName!.split('.').last}';
    }

    // Try from MIME type
    if (metadata.mimeType != null) {
      return _extensionFromMimeType(metadata.mimeType!);
    }

    return null;
  }

  String? _extensionFromMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) {
      if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return '.jpg';
      if (mimeType.contains('png')) return '.png';
      if (mimeType.contains('gif')) return '.gif';
      if (mimeType.contains('webp')) return '.webp';
    }

    if (mimeType.startsWith('audio/')) {
      if (mimeType.contains('mpeg') || mimeType.contains('mp3')) return '.mp3';
      if (mimeType.contains('wav')) return '.wav';
      if (mimeType.contains('aac')) return '.aac';
    }

    if (mimeType == 'application/pdf') return '.pdf';

    return null;
  }
}

/// Conversation cache statistics
class ConversationCacheStats {
  final int totalMedia;
  final int cachedMedia;
  final int uncachedMedia;
  final int totalCacheSize;
  final double cachePercentage;

  ConversationCacheStats({
    required this.totalMedia,
    required this.cachedMedia,
    required this.uncachedMedia,
    required this.totalCacheSize,
    required this.cachePercentage,
  });

  String get formattedCacheSize {
    final service = MediaCacheService();
    return service.formatFileSize(totalCacheSize);
  }

  @override
  String toString() {
    return 'ConversationCacheStats('
        'total: $totalMedia, '
        'cached: $cachedMedia, '
        'uncached: $uncachedMedia, '
        'size: $formattedCacheSize, '
        'percentage: ${cachePercentage.toStringAsFixed(1)}%)';
  }
}
