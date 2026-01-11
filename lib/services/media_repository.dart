import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/downloaded_media.dart';
import 'media_storage_helper.dart';

/// Repository for managing media downloads and local storage
/// This is the SINGLE SOURCE OF TRUTH for all media operations
///
/// Key Features:
/// - On-demand downloads (no auto-download)
/// - Local file caching
/// - Bandwidth optimization
/// - Progress tracking
/// - Cloudflare Worker integration
class MediaRepository {
  final MediaStorageHelper _storageHelper = MediaStorageHelper();
  static const String cloudflareBaseUrl = 'https://files.lenv1.tech';

  /// Check if media is downloaded locally
  /// Returns true if file exists on device
  Future<bool> isDownloaded(String r2Key) async {
    try {
      final metadata = await _storageHelper.getMediaMetadata(r2Key);
      if (metadata == null) return false;

      // Verify file actually exists
      final exists = await _storageHelper.fileExists(metadata.localPath);
      if (!exists) {
        // Metadata exists but file doesn't - clean up
        await _storageHelper.removeMediaMetadata(r2Key);
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get local file path if downloaded, null otherwise
  Future<String?> getLocalFilePath(String r2Key) async {
    try {
      final metadata = await _storageHelper.getMediaMetadata(r2Key);
      if (metadata == null) return null;

      // Verify file exists
      final exists = await _storageHelper.fileExists(metadata.localPath);
      return exists ? metadata.localPath : null;
    } catch (e) {
      return null;
    }
  }

  /// Get metadata for downloaded media
  Future<DownloadedMedia?> getMediaMetadata(String r2Key) async {
    return await _storageHelper.getMediaMetadata(r2Key);
  }

  /// Download media from Cloudflare Worker
  ///
  /// This method:
  /// 1. Streams the file from Cloudflare (free egress)
  /// 2. Saves it locally using path_provider
  /// 3. Stores metadata for future lookups
  /// 4. Provides progress callbacks
  ///
  /// Parameters:
  /// - r2Key: The R2 key (e.g., "media/1234567/file.pdf")
  /// - fileName: Display name for the file
  /// - mimeType: MIME type (e.g., "application/pdf")
  /// - onProgress: Callback with download progress (0.0 to 1.0)
  /// - thumbnailBase64: Optional thumbnail for images
  Future<DownloadResult> downloadMedia({
    required String r2Key,
    required String fileName,
    required String mimeType,
    Function(double progress)? onProgress,
    String? thumbnailBase64,
  }) async {
    try {

      // Check if already downloaded
      if (await isDownloaded(r2Key)) {
        final metadata = await _storageHelper.getMediaMetadata(r2Key);
        return DownloadResult(
          success: true,
          localPath: metadata!.localPath,
          message: 'Already downloaded',
        );
      }

      // Normalize r2Key: add 'media/' prefix if missing (for backward compatibility with old messages)
      final normalizedKey = r2Key.startsWith('media/') ? r2Key : 'media/$r2Key';
      
      // Build Cloudflare Worker URL
      final url = '$cloudflareBaseUrl/$normalizedKey';

      const maxRetries = 3;
      int attempt = 0;
      http.StreamedResponse streamedResponse;

      while (true) {
        attempt++;
        final request = http.Request('GET', Uri.parse(url));
        streamedResponse = await request.send();

        if (streamedResponse.statusCode == 200) {
          break;
        }

        // Retry on 404/403/5xx to handle propagation delays
        if (attempt < maxRetries &&
            (streamedResponse.statusCode == 404 ||
                streamedResponse.statusCode == 403 ||
                streamedResponse.statusCode >= 500)) {
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }

        return DownloadResult(
          success: false,
          message: 'Download failed: HTTP ${streamedResponse.statusCode}',
        );
      }

      // Get content length for progress tracking
      final contentLength = streamedResponse.contentLength ?? 0;

      // Collect bytes with progress tracking
      final bytes = <int>[];
      int downloadedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          final progress = downloadedBytes / contentLength;
          onProgress(progress);
          if (downloadedBytes % (1024 * 100) == 0) {
          }
        }
      }

      // Determine target file name from key
      final segmentsForName = r2Key.split('/');
      final baseName = segmentsForName.isNotEmpty
          ? segmentsForName.last
          : fileName;
      final targetFileName = baseName;

      // Save to public storage (Android MediaStore) or fallback app storage
      String savedPath;
      try {
        savedPath = await _storageHelper.saveToPublicStorage(
          bytes: Uint8List.fromList(bytes),
          fileName: targetFileName,
          mimeType: mimeType,
        );
      } catch (e) {
        return DownloadResult(
          success: false,
          message: 'Failed to save file: $e',
        );
      }

      final actualFileSize = await File(savedPath).length();

      if (!await File(savedPath).exists()) {
        return DownloadResult(
          success: false,
          message: 'File was not saved properly',
        );
      }

      // Save metadata
      final media = DownloadedMedia(
        key: r2Key,
        localPath: savedPath,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: actualFileSize,
        downloadedAt: DateTime.now(),
        thumbnailBase64: thumbnailBase64,
      );

      await _storageHelper.saveMediaMetadata(media);

      return DownloadResult(
        success: true,
        localPath: savedPath,
        message: 'Downloaded successfully',
      );
    } catch (e) {
      return DownloadResult(success: false, message: 'Download failed: $e');
    }
  }

  /// Delete downloaded media (file + metadata)
  Future<bool> deleteMedia(String r2Key) async {
    try {
      final metadata = await _storageHelper.getMediaMetadata(r2Key);
      if (metadata == null) return false;
      await _storageHelper.deleteFile(metadata.localPath);

      // Remove metadata
      await _storageHelper.removeMediaMetadata(r2Key);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get all downloaded media
  Future<List<DownloadedMedia>> getAllDownloaded() async {
    final all = await _storageHelper.getAllMediaMetadata();
    return all.values.toList()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
  }

  /// Get total storage used
  Future<int> getTotalStorageUsed() async {
    return await _storageHelper.getTotalStorageUsed();
  }

  /// Clear all downloads
  Future<void> clearAllDownloads() async {
    await _storageHelper.clearAllMedia();
  }

  /// Save uploaded media to cache (so we don't re-download our own uploads)
  /// This should be called after successfully uploading media
  Future<bool> cacheUploadedMedia({
    required String r2Key,
    required String localPath,
    required String fileName,
    required String mimeType,
    required int fileSize,
    String? thumbnailBase64,
  }) async {
    try {
      // Verify file exists
      final file = File(localPath);
      if (!await file.exists()) {
        return false;
      }

      // Save metadata
      final media = DownloadedMedia(
        key: r2Key,
        localPath: localPath,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: fileSize,
        downloadedAt: DateTime.now(),
        thumbnailBase64: thumbnailBase64,
      );

      await _storageHelper.saveMediaMetadata(media);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Format bytes for logging
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Result of a download operation
class DownloadResult {
  final bool success;
  final String? localPath;
  final String message;

  DownloadResult({
    required this.success,
    this.localPath,
    required this.message,
  });
}
