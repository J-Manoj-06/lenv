import 'package:flutter/foundation.dart';
import 'media_storage_helper.dart';

/// Service to check media availability before attempting downloads
///
/// PURPOSE: Prevent auto-download of images on reinstall or login
/// This service checks:
/// 1. Does local cache contain this media?
/// 2. Does the file still exist on disk?
/// 3. Should we attempt to load from network?
///
/// Flow:
/// - Check local cache first (fast)
/// - If exists locally, use local file path
/// - If NOT cached, show download button without auto-download
class MediaAvailabilityService {
  final MediaStorageHelper _storageHelper = MediaStorageHelper();

  /// Check if media exists locally
  ///
  /// Returns:
  /// - MediaAvailability.CACHED: File exists in local cache
  /// - MediaAvailability.NOT_CACHED: Not in local cache, needs download
  /// - MediaAvailability.CACHE_CORRUPTED: Cache metadata exists but file deleted
  Future<MediaAvailability> checkMediaAvailability(String r2Key) async {
    try {
      // Check if metadata exists in cache database
      final metadata = await _storageHelper.getMediaMetadata(r2Key);

      if (metadata == null) {
        // No metadata = never downloaded
        debugPrint('📊 Media NOT in cache: $r2Key');
        return MediaAvailability.notCached;
      }

      // Metadata exists, check if file still on disk
      final exists = await _storageHelper.fileExists(metadata.localPath);

      if (!exists) {
        // Metadata exists but file is gone (cache cleared or storage issue)
        debugPrint(
          '⚠️ Cache corrupted: metadata exists but file missing: $r2Key',
        );
        // Clean up orphaned metadata
        await _storageHelper.removeMediaMetadata(r2Key).catchError((_) {});
        return MediaAvailability.cacheCorrupted;
      }

      // File exists locally
      debugPrint('✅ Media cached locally: $r2Key -> ${metadata.localPath}');
      return MediaAvailability.cached;
    } catch (e) {
      debugPrint('❌ Error checking media availability: $e');
      return MediaAvailability.notCached;
    }
  }

  /// Get local file path if cached, null otherwise
  /// This does NOT attempt download - just returns cached path if it exists
  Future<String?> getCachedFilePath(String r2Key) async {
    try {
      final metadata = await _storageHelper.getMediaMetadata(r2Key);
      if (metadata == null) return null;

      // Double-check file exists
      final exists = await _storageHelper.fileExists(metadata.localPath);
      return exists ? metadata.localPath : null;
    } catch (e) {
      return null;
    }
  }

  /// Check multiple media items at once
  /// Returns map of r2Key -> MediaAvailability
  Future<Map<String, MediaAvailability>> checkMultipleMedia(
    List<String> r2Keys,
  ) async {
    final results = <String, MediaAvailability>{};

    // Check all in parallel
    final futures = r2Keys.map((key) async {
      final availability = await checkMediaAvailability(key);
      return MapEntry(key, availability);
    });

    final entries = await Future.wait(futures);
    results.addEntries(entries);

    return results;
  }

  /// Get local paths for all cached media
  /// Skips non-cached items
  Future<Map<String, String>> getCachedFilePaths(List<String> r2Keys) async {
    final paths = <String, String>{};

    for (final r2Key in r2Keys) {
      final path = await getCachedFilePath(r2Key);
      if (path != null) {
        paths[r2Key] = path;
      }
    }

    return paths;
  }
}

/// Media availability states
enum MediaAvailability {
  /// File exists in local cache and on disk
  cached('🟢 Cached'),

  /// Not in local cache, needs download
  notCached('⚪ Not Cached'),

  /// Metadata exists but file was deleted from disk
  cacheCorrupted('🔴 Cache Corrupted');

  final String label;
  const MediaAvailability(this.label);

  bool get isCached => this == MediaAvailability.cached;
  bool get needsDownload => this != MediaAvailability.cached;
}
