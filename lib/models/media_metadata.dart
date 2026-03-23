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
  // Original filename to display in UI (preserves user-provided name)
  final String? originalFileName;

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
    this.originalFileName,
  });

  /// Parse a timestamp field that may be a Firestore [Timestamp], an [int]
  /// (milliseconds since epoch), or null.
  static DateTime _parseTimestamp(dynamic value, DateTime fallback) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _parseString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  static String _deriveR2KeyFromUrl(String url) {
    if (url.isEmpty) return '';

    final parsed = Uri.tryParse(url);
    if (parsed == null) return '';

    var path = parsed.path;
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.isEmpty) return '';

    final mediaIndex = path.indexOf('media/');
    if (mediaIndex >= 0) {
      path = path.substring(mediaIndex);
    } else {
      path = 'media/$path';
    }

    return Uri.decodeFull(path);
  }

  /// Create from Firestore document
  factory MediaMetadata.fromFirestore(Map<String, dynamic> data) {
    final parsedPublicUrl = _parseString(data['publicUrl']).isNotEmpty
      ? _parseString(data['publicUrl'])
      : (_parseString(data['url']).isNotEmpty
          ? _parseString(data['url'])
          : (_parseString(data['downloadUrl']).isNotEmpty
            ? _parseString(data['downloadUrl'])
            : _parseString(data['fileUrl'])));

    final parsedR2Key = _parseString(data['r2Key']).isNotEmpty
      ? _parseString(data['r2Key'])
      : (_parseString(data['key']).isNotEmpty
          ? _parseString(data['key'])
          : (_parseString(data['mediaKey']).isNotEmpty
            ? _parseString(data['mediaKey'])
            : _deriveR2KeyFromUrl(parsedPublicUrl)));

    return MediaMetadata(
      messageId: _parseString(data['messageId']),
      r2Key: parsedR2Key,
      publicUrl: parsedPublicUrl,
      localPath: data['localPath'] is String
          ? data['localPath'] as String
          : null,
      thumbnail: _parseString(data['thumbnail']),
      deletedLocally: data['deletedLocally'] as bool? ?? false,
      serverStatus: ServerStatus.fromString(
        data['serverStatus'] as String? ?? 'available',
      ),
      expiresAt: _parseTimestamp(
        data['expiresAt'],
        DateTime.now().add(const Duration(days: 30)),
      ),
      uploadedAt: _parseTimestamp(data['uploadedAt'], DateTime.now()),
      fileSize: _parseInt(data['fileSize']),
      mimeType: _parseString(data['mimeType']).isNotEmpty
          ? _parseString(data['mimeType'])
          : (_parseString(data['type']).isNotEmpty
                ? _parseString(data['type'])
                : null),
      originalFileName: _parseString(data['originalFileName']).isNotEmpty
          ? _parseString(data['originalFileName'])
          : null,
    );
  }

  /// Convert to Firestore document
  /// NOTE: localPath is intentionally excluded - it's device-specific and should
  /// only be stored in local download cache, never in Firestore.
  /// This prevents auto-download issues when signing in on different devices.
  Map<String, dynamic> toFirestore() {
    return {
      'messageId': messageId,
      'r2Key': r2Key,
      'publicUrl': publicUrl,
      // 'localPath': localPath, // ❌ REMOVED: Never save device-specific paths to Firestore
      'thumbnail': thumbnail,
      'deletedLocally': deletedLocally,
      'serverStatus': serverStatus.toString(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'fileSize': fileSize,
      'mimeType': mimeType,
      'originalFileName': originalFileName,
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
    String? originalFileName,
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
      originalFileName: originalFileName ?? this.originalFileName,
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
