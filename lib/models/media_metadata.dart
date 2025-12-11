import 'package:cloud_firestore/cloud_firestore.dart';

/// WhatsApp-style media metadata model
/// Tracks image upload, download, caching, and expiry state
class MediaMetadata {
  final String messageId;
  final String r2Key;
  final String publicUrl;
  final String? localPath;
  final String thumbnail; // Base64 or URL to small compressed thumbnail
  final bool deletedLocally;
  final ServerStatus serverStatus;
  final DateTime expiresAt;
  final DateTime uploadedAt;
  final int? fileSize;
  final String? mimeType;

  MediaMetadata({
    required this.messageId,
    required this.r2Key,
    required this.publicUrl,
    this.localPath,
    required this.thumbnail,
    this.deletedLocally = false,
    this.serverStatus = ServerStatus.available,
    required this.expiresAt,
    required this.uploadedAt,
    this.fileSize,
    this.mimeType,
  });

  /// Create from Firestore document
  factory MediaMetadata.fromFirestore(Map<String, dynamic> data) {
    return MediaMetadata(
      messageId: data['messageId'] as String? ?? '',
      r2Key: data['r2Key'] as String? ?? '',
      publicUrl: data['publicUrl'] as String? ?? '',
      localPath: data['localPath'] as String?,
      thumbnail: data['thumbnail'] as String? ?? '',
      deletedLocally: data['deletedLocally'] as bool? ?? false,
      serverStatus: ServerStatus.fromString(
        data['serverStatus'] as String? ?? 'available',
      ),
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 30)),
      uploadedAt:
          (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fileSize: data['fileSize'] as int?,
      mimeType: data['mimeType'] as String?,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'messageId': messageId,
      'r2Key': r2Key,
      'publicUrl': publicUrl,
      'localPath': localPath,
      'thumbnail': thumbnail,
      'deletedLocally': deletedLocally,
      'serverStatus': serverStatus.toString(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'fileSize': fileSize,
      'mimeType': mimeType,
    };
  }

  /// Check if media is available for viewing
  bool get isAvailable {
    return !deletedLocally &&
        serverStatus == ServerStatus.available &&
        DateTime.now().isBefore(expiresAt);
  }

  /// Check if media exists locally
  bool get hasLocalFile {
    return localPath != null && localPath!.isNotEmpty && !deletedLocally;
  }

  /// Check if media has expired
  bool get isExpired {
    return DateTime.now().isAfter(expiresAt) ||
        serverStatus == ServerStatus.expired;
  }

  /// Check if media is missing on server
  bool get isMissing {
    return serverStatus == ServerStatus.missing ||
        serverStatus == ServerStatus.deleted;
  }

  /// Copy with updated fields
  MediaMetadata copyWith({
    String? messageId,
    String? r2Key,
    String? publicUrl,
    String? localPath,
    String? thumbnail,
    bool? deletedLocally,
    ServerStatus? serverStatus,
    DateTime? expiresAt,
    DateTime? uploadedAt,
    int? fileSize,
    String? mimeType,
  }) {
    return MediaMetadata(
      messageId: messageId ?? this.messageId,
      r2Key: r2Key ?? this.r2Key,
      publicUrl: publicUrl ?? this.publicUrl,
      localPath: localPath ?? this.localPath,
      thumbnail: thumbnail ?? this.thumbnail,
      deletedLocally: deletedLocally ?? this.deletedLocally,
      serverStatus: serverStatus ?? this.serverStatus,
      expiresAt: expiresAt ?? this.expiresAt,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}

/// Server status enum for tracking media availability
enum ServerStatus {
  available, // File exists on R2
  missing, // 404 - File not found
  expired, // 410 - File expired/deleted
  deleted, // Manually deleted
  error; // Server error (5xx)

  @override
  String toString() {
    switch (this) {
      case ServerStatus.available:
        return 'available';
      case ServerStatus.missing:
        return 'missing';
      case ServerStatus.expired:
        return 'expired';
      case ServerStatus.deleted:
        return 'deleted';
      case ServerStatus.error:
        return 'error';
    }
  }

  static ServerStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return ServerStatus.available;
      case 'missing':
        return ServerStatus.missing;
      case 'expired':
        return ServerStatus.expired;
      case 'deleted':
        return ServerStatus.deleted;
      case 'error':
        return ServerStatus.error;
      default:
        return ServerStatus.available;
    }
  }

  /// Get status from HTTP code
  static ServerStatus fromHttpCode(int code) {
    if (code == 200) return ServerStatus.available;
    if (code == 404) return ServerStatus.missing;
    if (code == 410) return ServerStatus.expired;
    if (code >= 500) return ServerStatus.error;
    return ServerStatus.error;
  }
}
