/// Data model for a message being forwarded.
/// Captures everything needed to re-send it to new destinations
/// without re-uploading any media.
class ForwardMessageData {
  final String originalMessageId;
  final String originalSenderId;
  final String originalSenderName;

  /// 'text' | 'image' | 'multi_image' | 'audio' | 'file' | 'link'
  final String messageType;

  /// Plain text content (for text / link messages)
  final String? text;

  /// Single image/audio/file URL (for image, audio, file messages)
  final String? mediaUrl;

  /// Original file name for audio/file messages
  final String? fileName;

  /// MIME type of media
  final String? mimeType;

  /// File size in bytes
  final int? fileSize;

  /// List of image URLs for multi-image grid messages
  final List<String>? multipleImageUrls;

  /// If `true` this message was already a forward (chained forward)
  final bool wasAlreadyForwarded;

  const ForwardMessageData({
    required this.originalMessageId,
    required this.originalSenderId,
    required this.originalSenderName,
    required this.messageType,
    this.text,
    this.mediaUrl,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.multipleImageUrls,
    this.wasAlreadyForwarded = false,
  });

  /// Build from a GroupChatMessage rawData map + metadata objects.
  factory ForwardMessageData.fromRaw({
    required String messageId,
    required String senderId,
    required String senderName,
    required Map<String, dynamic>? rawData,
    required String? imageUrl,
    required String? message,
    required dynamic mediaMetadata, // MediaMetadata?
    required dynamic multipleMedia, // List<MediaMetadata>?
  }) {
    // Determine type
    String type = 'text';
    String? mediaUrlParsed;
    String? fileNameParsed;
    String? mimeTypeParsed;
    int? fileSizeParsed;
    List<String>? multiImageUrls;
    String? textContent = message ?? '';
    bool wasForwarded = false;

    if (rawData != null) {
      wasForwarded = rawData['forwarded'] == true;
    }

    if (multipleMedia != null && (multipleMedia as List).isNotEmpty) {
      type = 'multi_image';
      multiImageUrls = multipleMedia
          .map((m) => (m.publicUrl as String?) ?? '')
          .where((url) => url.isNotEmpty)
          .toList();
    } else if (mediaMetadata != null) {
      final mime = (mediaMetadata.mimeType as String?) ?? '';
      final pubUrl = (mediaMetadata.publicUrl as String?) ?? '';
      final origName = (mediaMetadata.originalFileName as String?) ?? '';
      final size = mediaMetadata.fileSize as int?;

      mediaUrlParsed = pubUrl;
      fileNameParsed = origName;
      mimeTypeParsed = mime;
      fileSizeParsed = size;

      if (mime.startsWith('audio/')) {
        type = 'audio';
      } else if (mime.startsWith('image/') || imageUrl != null) {
        type = 'image';
        mediaUrlParsed = pubUrl.isNotEmpty ? pubUrl : imageUrl;
      } else {
        type = 'file';
      }
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      type = 'image';
      mediaUrlParsed = imageUrl;
    } else if (textContent.isNotEmpty) {
      // Check if it looks like a link
      if (textContent.startsWith('http://') ||
          textContent.startsWith('https://')) {
        type = 'link';
      } else {
        type = 'text';
      }
    }

    return ForwardMessageData(
      originalMessageId: messageId,
      originalSenderId: senderId,
      originalSenderName: senderName,
      messageType: type,
      text: textContent,
      mediaUrl: mediaUrlParsed,
      fileName: fileNameParsed,
      mimeType: mimeTypeParsed,
      fileSize: fileSizeParsed,
      multipleImageUrls: multiImageUrls,
      wasAlreadyForwarded: wasForwarded,
    );
  }

  /// Convert to Firestore map for writing as a forwarded message.
  /// Compatible with GroupChatMessage.fromFirestore() consumer fields:
  ///   text/message, imageUrl, mediaMetadata, multipleMedia, type, timestamp.
  Map<String, dynamic> toForwardedFirestoreMap({
    required String newSenderId,
    required String newSenderName,
    required String newSenderRole,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = <String, dynamic>{
      'senderId': newSenderId,
      'senderName': newSenderName,
      'senderRole': newSenderRole,
      'timestamp': now,
      'isDeleted': false,
      'deletedFor': null,
      'forwarded': true,
      'originalSenderId': originalSenderId,
      'originalSenderName': originalSenderName,
      'type': messageType,
    };

    // Text / link
    if (text != null && text!.isNotEmpty) {
      map['message'] = text;
    }

    // Single image
    if (messageType == 'image' && mediaUrl != null && mediaUrl!.isNotEmpty) {
      map['imageUrl'] = mediaUrl;
      map['mediaMetadata'] = _buildMetadataMap(now);
    }

    // Audio / file – store in mediaMetadata
    if ((messageType == 'audio' || messageType == 'file') &&
        mediaUrl != null &&
        mediaUrl!.isNotEmpty) {
      map['mediaMetadata'] = _buildMetadataMap(now);
    }

    // Multi-image grid
    if (messageType == 'multi_image' &&
        multipleImageUrls != null &&
        multipleImageUrls!.isNotEmpty) {
      map['multipleMedia'] = multipleImageUrls!
          .asMap()
          .entries
          .map(
            (e) => {
              'messageId': '${originalMessageId}_${e.key}',
              'publicUrl': e.value,
              'r2Key': '',
              'thumbnail': '',
              'originalFileName': 'image_${e.key}.jpg',
              'fileSize': 0,
              'mimeType': 'image/jpeg',
              'serverStatus': 'available',
              'uploadedAt': now,
              'expiresAt': now + const Duration(days: 30).inMilliseconds,
            },
          )
          .toList();
    }

    return map;
  }

  Map<String, dynamic> _buildMetadataMap(int now) {
    return {
      'messageId': originalMessageId,
      'publicUrl': mediaUrl ?? '',
      'r2Key': '',
      'thumbnail': '',
      'originalFileName': fileName ?? '',
      'fileSize': fileSize ?? 0,
      'mimeType': mimeType ?? 'application/octet-stream',
      'serverStatus': 'available',
      'uploadedAt': now,
      'expiresAt': now + const Duration(days: 30).inMilliseconds,
    };
  }
}

/// Represents a forward destination (community, group, private chat, etc.)
class ForwardDestination {
  final String id; // chat/community/group ID
  final String name; // display name
  final String
  type; // 'community' | 'group' | 'staffroom' | 'parent_teacher' | 'private'
  final String? subtitle; // e.g. class name, teacher name
  final String? iconEmoji; // optional emoji icon
  final Map<String, dynamic>?
  metadata; // extra fields needed to send (e.g. classId, subjectId)

  const ForwardDestination({
    required this.id,
    required this.name,
    required this.type,
    this.subtitle,
    this.iconEmoji,
    this.metadata,
  });
}
