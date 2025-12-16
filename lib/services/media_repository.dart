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
      debugPrint('❌ Error checking download status: $e');
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
      debugPrint('❌ Error getting local file path: $e');
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
      debugPrint('📥 Starting download: $r2Key');

      // Check if already downloaded
      if (await isDownloaded(r2Key)) {
        debugPrint('✅ Already downloaded: $r2Key');
        final metadata = await _storageHelper.getMediaMetadata(r2Key);
        return DownloadResult(
          success: true,
          localPath: metadata!.localPath,
          message: 'Already downloaded',
        );
      }

      // Build Cloudflare Worker URL
      final url = '$cloudflareBaseUrl/$r2Key';
      debugPrint('🔗 Download URL: $url');

      // Make HTTP request
      debugPrint('🌐 Making HTTP request to: $url');
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await request.send();

      if (streamedResponse.statusCode != 200) {
        debugPrint('❌ HTTP Error: ${streamedResponse.statusCode}');
        return DownloadResult(
          success: false,
          message: 'Download failed: HTTP ${streamedResponse.statusCode}',
        );
      }

      // Get content length for progress tracking
      final contentLength = streamedResponse.contentLength ?? 0;
      debugPrint('📦 Content length: ${_formatBytes(contentLength)}');

      // Collect bytes with progress tracking
      debugPrint('⬇️ Starting download...');
      final bytes = <int>[];
      int downloadedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (contentLength > 0 && onProgress != null) {
          final progress = downloadedBytes / contentLength;
          onProgress(progress);
          if (downloadedBytes % (1024 * 100) == 0) {
            debugPrint(
              '  ⬇️ Progress: ${(progress * 100).toInt()}% (${_formatBytes(downloadedBytes)}/${_formatBytes(contentLength)})',
            );
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
      debugPrint(
        '💾 Saving ${_formatBytes(bytes.length)} to public storage...',
      );
      String savedPath;
      try {
        savedPath = await _storageHelper.saveToPublicStorage(
          bytes: Uint8List.fromList(bytes),
          fileName: targetFileName,
          mimeType: mimeType,
        );
      } catch (e) {
        debugPrint('❌ Error saving to public storage: $e');
        return DownloadResult(
          success: false,
          message: 'Failed to save file: $e',
        );
      }

      final actualFileSize = await File(savedPath).length();
      debugPrint('💾 Saved to: $savedPath');
      debugPrint('📂 File exists: ${await File(savedPath).exists()}');

      if (!await File(savedPath).exists()) {
        debugPrint('❌ ERROR: File was written but does not exist!');
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
      debugPrint('✅ Download complete: $fileName (${media.formattedSize})');
      debugPrint('🔑 Saved with key: $r2Key');

      return DownloadResult(
        success: true,
        localPath: savedPath,
        message: 'Downloaded successfully',
      );
    } catch (e) {
      debugPrint('❌ Download error: $e');
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

      debugPrint('🗑️ Deleted: $r2Key');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting media: $e');
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
