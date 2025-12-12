/// Model to track downloaded media files locally
/// Stores metadata about downloaded files for quick lookup
class DownloadedMedia {
  final String key; // Cloudflare R2 key (e.g., "media/timestamp/filename.pdf")
  final String localPath; // Local file path on device
  final String fileName;
  final String mimeType;
  final int fileSize;
  final DateTime downloadedAt;
  final String? thumbnailBase64; // For images

  DownloadedMedia({
    required this.key,
    required this.localPath,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.downloadedAt,
    this.thumbnailBase64,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'localPath': localPath,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'downloadedAt': downloadedAt.toIso8601String(),
      'thumbnailBase64': thumbnailBase64,
    };
  }

  /// Create from JSON
  factory DownloadedMedia.fromJson(Map<String, dynamic> json) {
    return DownloadedMedia(
      key: json['key'] as String,
      localPath: json['localPath'] as String,
      fileName: json['fileName'] as String,
      mimeType: json['mimeType'] as String,
      fileSize: json['fileSize'] as int,
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
      thumbnailBase64: json['thumbnailBase64'] as String?,
    );
  }

  /// Check if file is an image
  bool get isImage => mimeType.startsWith('image/');

  /// Check if file is a PDF
  bool get isPdf => mimeType == 'application/pdf';

  /// Check if file is audio
  bool get isAudio => mimeType.startsWith('audio/');

  /// Check if file is video
  bool get isVideo => mimeType.startsWith('video/');

  /// Format file size for display
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
