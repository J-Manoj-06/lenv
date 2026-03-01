import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Universal Media Cache Service
/// Manages local caching for all media types: images, audio, video, PDF, documents
/// Follows the smart caching strategy: check local first, download only when needed
class MediaCacheService {
  static const String _mediaCacheDir = 'lenv_media';

  // Sub-directories for different media types
  static const String _imagesDir = 'images';
  static const String _audioDir = 'audio';
  static const String _documentsDir = 'documents';

  /// Get the base media cache directory
  /// Structure: AppDirectory/lenv_media/
  Future<Directory> _getBaseCacheDirectory() async {
    try {
      // Try external storage first (more reliable for persistent cache)
      if (Platform.isAndroid || Platform.isIOS) {
        final appDir = await getApplicationDocumentsDirectory();
        final cacheDir = Directory(path.join(appDir.path, _mediaCacheDir));

        if (!await cacheDir.exists()) {
          await cacheDir.create(recursive: true);
        }

        return cacheDir;
      }

      // Fallback for other platforms
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(path.join(appDir.path, _mediaCacheDir));

      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      return cacheDir;
    } catch (e) {
      debugPrint('Error getting base cache directory: $e');
      rethrow;
    }
  }

  /// Get directory for specific media type
  Future<Directory> _getMediaTypeDirectory(MediaType mediaType) async {
    final baseDir = await _getBaseCacheDirectory();
    String subDir;

    switch (mediaType) {
      case MediaType.image:
        subDir = _imagesDir;
        break;
      case MediaType.audio:
        subDir = _audioDir;
        break;
      case MediaType.document:
      case MediaType.pdf:
        subDir = _documentsDir;
        break;
    }

    final dir = Directory(path.join(baseDir.path, subDir));

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  /// STEP 1: Check if media exists locally
  /// This is the core function - always call this first before downloading
  Future<bool> checkIfMediaExists(String localPath) async {
    try {
      if (localPath.isEmpty) return false;

      final file = File(localPath);
      return await file.exists();
    } catch (e) {
      debugPrint('Error checking media existence: $e');
      return false;
    }
  }

  /// Generate local file path for a media file
  /// messageId is used as the filename to ensure uniqueness
  Future<String> getLocalFilePath({
    required String messageId,
    required MediaType mediaType,
    String? extension,
  }) async {
    try {
      final dir = await _getMediaTypeDirectory(mediaType);

      // Use messageId as filename with appropriate extension
      final ext = extension ?? _getDefaultExtension(mediaType);
      final fileName = '$messageId$ext';

      return path.join(dir.path, fileName);
    } catch (e) {
      debugPrint('Error generating local file path: $e');
      rethrow;
    }
  }

  /// Get default file extension for media type
  String _getDefaultExtension(MediaType mediaType) {
    switch (mediaType) {
      case MediaType.image:
        return '.jpg';
      case MediaType.audio:
        return '.mp3';
      case MediaType.pdf:
        return '.pdf';
      case MediaType.document:
        return '.doc';
    }
  }

  /// Save media file locally
  /// Used when downloading from cloud or when user sends media
  Future<String> saveMediaFile({
    required String messageId,
    required MediaType mediaType,
    required Uint8List fileBytes,
    String? extension,
  }) async {
    try {
      final localPath = await getLocalFilePath(
        messageId: messageId,
        mediaType: mediaType,
        extension: extension,
      );

      final file = File(localPath);
      await file.writeAsBytes(fileBytes, flush: true);

      debugPrint('Media saved locally: $localPath');
      return localPath;
    } catch (e) {
      debugPrint('Error saving media file: $e');
      rethrow;
    }
  }

  /// Load media file from local storage
  /// Returns null if file doesn't exist
  Future<File?> loadMediaFile(String localPath) async {
    try {
      if (localPath.isEmpty) return null;

      final file = File(localPath);

      if (await file.exists()) {
        return file;
      }

      return null;
    } catch (e) {
      debugPrint('Error loading media file: $e');
      return null;
    }
  }

  /// Delete media file from local storage
  Future<bool> deleteMediaFile(String localPath) async {
    try {
      if (localPath.isEmpty) return false;

      final file = File(localPath);

      if (await file.exists()) {
        await file.delete();
        debugPrint('Media deleted: $localPath');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error deleting media file: $e');
      return false;
    }
  }

  /// Get file size of locally cached media
  Future<int?> getFileSize(String localPath) async {
    try {
      if (localPath.isEmpty) return null;

      final file = File(localPath);

      if (await file.exists()) {
        return await file.length();
      }

      return null;
    } catch (e) {
      debugPrint('Error getting file size: $e');
      return null;
    }
  }

  /// Clear all cached media for a specific type
  Future<int> clearMediaCache(MediaType mediaType) async {
    try {
      final dir = await _getMediaTypeDirectory(mediaType);
      int deletedCount = 0;

      if (await dir.exists()) {
        final files = dir.listSync();
        for (final file in files) {
          if (file is File) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      debugPrint('Cleared $deletedCount ${mediaType.name} files');
      return deletedCount;
    } catch (e) {
      debugPrint('Error clearing media cache: $e');
      return 0;
    }
  }

  /// Clear all cached media across all types
  Future<Map<MediaType, int>> clearAllMediaCache() async {
    final results = <MediaType, int>{};

    for (final mediaType in MediaType.values) {
      results[mediaType] = await clearMediaCache(mediaType);
    }

    return results;
  }

  /// Get total cache size for a media type
  Future<int> getCacheSize(MediaType mediaType) async {
    try {
      final dir = await _getMediaTypeDirectory(mediaType);
      int totalSize = 0;

      if (await dir.exists()) {
        final files = dir.listSync();
        for (final file in files) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('Error calculating cache size: $e');
      return 0;
    }
  }

  /// Get total cache size across all media types
  Future<int> getTotalCacheSize() async {
    int totalSize = 0;

    for (final mediaType in MediaType.values) {
      totalSize += await getCacheSize(mediaType);
    }

    return totalSize;
  }

  /// Format bytes to readable size
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Check if device has enough storage space
  Future<bool> hasEnoughStorage({int requiredBytes = 10 * 1024 * 1024}) async {
    try {
      // This is a simplified check
      // In production, you might want to use platform-specific methods
      return true; // Placeholder - implement actual storage check
    } catch (e) {
      debugPrint('Error checking storage: $e');
      return false;
    }
  }

  /// Get cache statistics
  Future<CacheStatistics> getCacheStatistics() async {
    final stats = <MediaType, MediaCacheStats>{};

    for (final mediaType in MediaType.values) {
      final dir = await _getMediaTypeDirectory(mediaType);
      int fileCount = 0;
      int totalSize = 0;

      if (await dir.exists()) {
        final files = dir.listSync().whereType<File>().toList();
        fileCount = files.length;

        for (final file in files) {
          totalSize += await file.length();
        }
      }

      stats[mediaType] = MediaCacheStats(
        fileCount: fileCount,
        totalSize: totalSize,
      );
    }

    return CacheStatistics(stats: stats);
  }
}

/// Media type enum
enum MediaType { image, audio, pdf, document }

/// Helper extension to convert from MIME type string
extension MediaTypeExtension on MediaType {
  static MediaType fromMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) return MediaType.image;
    if (mimeType.startsWith('audio/')) return MediaType.audio;
    if (mimeType == 'application/pdf') return MediaType.pdf;
    return MediaType.document;
  }

  static MediaType fromFileExtension(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');

    // Images
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return MediaType.image;
    }

    // Audio
    if (['mp3', 'wav', 'aac', 'm4a', 'ogg'].contains(ext)) {
      return MediaType.audio;
    }

    // PDF
    if (ext == 'pdf') {
      return MediaType.pdf;
    }

    // Documents
    return MediaType.document;
  }
}

/// Cache statistics data class
class CacheStatistics {
  final Map<MediaType, MediaCacheStats> stats;

  CacheStatistics({required this.stats});

  int get totalFiles =>
      stats.values.fold(0, (sum, stat) => sum + stat.fileCount);
  int get totalSize =>
      stats.values.fold(0, (sum, stat) => sum + stat.totalSize);

  String get formattedTotalSize {
    final service = MediaCacheService();
    return service.formatFileSize(totalSize);
  }
}

/// Individual media type cache statistics
class MediaCacheStats {
  final int fileCount;
  final int totalSize;

  MediaCacheStats({required this.fileCount, required this.totalSize});

  String get formattedSize {
    final service = MediaCacheService();
    return service.formatFileSize(totalSize);
  }
}
