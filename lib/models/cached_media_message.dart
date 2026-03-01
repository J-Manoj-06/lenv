import 'package:cloud_firestore/cloud_firestore.dart';

/// Enhanced media message model with smart caching support
/// This model extends the concept to support all media types with local caching
class CachedMediaMessage {
  final String messageId;
  final String senderId;
  final String senderRole;
  final String conversationId;

  // Media information
  final String fileName;
  final String fileType; // MIME type
  final int fileSize; // in bytes
  final String cloudUrl; // Cloudflare R2 or other cloud storage URL
  final String? thumbnailUrl; // Base64 thumbnail or URL

  // Caching metadata
  final String? localPath; // Local device path (null if not downloaded)
  final bool isDownloaded; // True if file exists locally
  final MediaTypeCategory mediaType; // image, audio, video, pdf, document

  // Timestamps
  final DateTime createdAt;
  final DateTime? downloadedAt;

  // Status
  final bool isPending; // Upload in progress
  final bool uploadFailed;
  final bool downloadFailed;
  final String? errorMessage;

  // Read status (varies by chat type)
  final Map<String, bool> readBy; // userId -> hasRead

  CachedMediaMessage({
    required this.messageId,
    required this.senderId,
    required this.senderRole,
    required this.conversationId,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.cloudUrl,
    this.thumbnailUrl,
    this.localPath,
    this.isDownloaded = false,
    required this.mediaType,
    required this.createdAt,
    this.downloadedAt,
    this.isPending = false,
    this.uploadFailed = false,
    this.downloadFailed = false,
    this.errorMessage,
    this.readBy = const {},
  });

  /// Check if this is an image
  bool get isImage => mediaType == MediaTypeCategory.image;

  /// Check if this is audio
  bool get isAudio => mediaType == MediaTypeCategory.audio;

  /// Check if this is a PDF
  bool get isPdf => mediaType == MediaTypeCategory.pdf;

  /// Check if this is a document
  bool get isDocument => mediaType == MediaTypeCategory.document;

  /// Format file size to readable format
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Get file extension from fileName
  String get fileExtension {
    if (fileName.contains('.')) {
      return fileName.split('.').last.toLowerCase();
    }
    return '';
  }

  /// Check if media is ready to view
  bool get isReadyToView =>
      isDownloaded && localPath != null && !downloadFailed;

  /// Check if media is available in cloud
  bool get isAvailableInCloud => !uploadFailed && cloudUrl.isNotEmpty;

  /// Create from Firestore document
  factory CachedMediaMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return CachedMediaMessage(
      messageId: doc.id,
      senderId: data['senderId'] ?? '',
      senderRole: data['senderRole'] ?? 'student',
      conversationId: data['conversationId'] ?? '',
      fileName: data['fileName'] ?? 'unknown',
      fileType: data['fileType'] ?? 'application/octet-stream',
      fileSize: data['fileSize'] ?? 0,
      cloudUrl: data['cloudUrl'] ?? data['r2Url'] ?? '',
      thumbnailUrl: data['thumbnailUrl'],
      // Never load localPath from Firestore - it's device-specific
      localPath: null,
      isDownloaded: false, // Always false when loading from Firestore
      mediaType: MediaTypeCategoryExtension.fromMimeType(
        data['fileType'] ?? 'application/octet-stream',
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      downloadedAt: (data['downloadedAt'] as Timestamp?)?.toDate(),
      isPending: doc.metadata.hasPendingWrites,
      uploadFailed: data['uploadFailed'] ?? false,
      downloadFailed: false,
      errorMessage: data['errorMessage'],
      readBy: data['readBy'] != null
          ? Map<String, bool>.from(data['readBy'])
          : {},
    );
  }

  /// Convert to Firestore document
  /// Note: localPath is intentionally excluded from Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderRole': senderRole,
      'conversationId': conversationId,
      'fileName': fileName,
      'fileType': fileType,
      'fileSize': fileSize,
      'cloudUrl': cloudUrl,
      'thumbnailUrl': thumbnailUrl,
      // 'localPath': localPath, // ❌ Never save to Firestore
      // 'isDownloaded': isDownloaded, // ❌ Never save to Firestore
      'mediaType': mediaType.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'downloadedAt': downloadedAt != null
          ? Timestamp.fromDate(downloadedAt!)
          : null,
      'uploadFailed': uploadFailed,
      'errorMessage': errorMessage,
      'readBy': readBy,
    };
  }

  /// Create a copy with updated fields
  CachedMediaMessage copyWith({
    String? messageId,
    String? senderId,
    String? senderRole,
    String? conversationId,
    String? fileName,
    String? fileType,
    int? fileSize,
    String? cloudUrl,
    String? thumbnailUrl,
    String? localPath,
    bool? isDownloaded,
    MediaTypeCategory? mediaType,
    DateTime? createdAt,
    DateTime? downloadedAt,
    bool? isPending,
    bool? uploadFailed,
    bool? downloadFailed,
    String? errorMessage,
    Map<String, bool>? readBy,
  }) {
    return CachedMediaMessage(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      conversationId: conversationId ?? this.conversationId,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      cloudUrl: cloudUrl ?? this.cloudUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localPath: localPath ?? this.localPath,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      mediaType: mediaType ?? this.mediaType,
      createdAt: createdAt ?? this.createdAt,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      isPending: isPending ?? this.isPending,
      uploadFailed: uploadFailed ?? this.uploadFailed,
      downloadFailed: downloadFailed ?? this.downloadFailed,
      errorMessage: errorMessage ?? this.errorMessage,
      readBy: readBy ?? this.readBy,
    );
  }
}

/// Media type category enum
enum MediaTypeCategory { image, audio, pdf, document }

/// Extension to convert from MIME type
extension MediaTypeCategoryExtension on MediaTypeCategory {
  /// Convert from MIME type to MediaTypeCategory
  static MediaTypeCategory fromMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) return MediaTypeCategory.image;
    if (mimeType.startsWith('audio/')) return MediaTypeCategory.audio;
    if (mimeType == 'application/pdf') return MediaTypeCategory.pdf;
    return MediaTypeCategory.document;
  }

  static MediaTypeCategory fromFileExtension(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');

    // Images
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
      return MediaTypeCategory.image;
    }

    // Audio
    if (['mp3', 'wav', 'aac', 'm4a', 'ogg', 'opus'].contains(ext)) {
      return MediaTypeCategory.audio;
    }

    // PDF
    if (ext == 'pdf') {
      return MediaTypeCategory.pdf;
    }

    // Documents
    return MediaTypeCategory.document;
  }

  /// Convert to string representation
  String toStringValue() {
    switch (this) {
      case MediaTypeCategory.image:
        return 'image';
      case MediaTypeCategory.audio:
        return 'audio';
      case MediaTypeCategory.pdf:
        return 'pdf';
      case MediaTypeCategory.document:
        return 'document';
    }
  }

  /// Get icon for media type
  String get icon {
    switch (this) {
      case MediaTypeCategory.image:
        return '🖼️';
      case MediaTypeCategory.audio:
        return '🎵';
      case MediaTypeCategory.pdf:
        return '📄';
      case MediaTypeCategory.document:
        return '📎';
    }
  }
}
