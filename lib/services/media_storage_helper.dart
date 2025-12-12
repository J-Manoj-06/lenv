import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/downloaded_media.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:mime/mime.dart';

/// Helper class for managing local media file storage
/// Handles file paths, directories, and metadata persistence
class MediaStorageHelper {
  static const String _storageKey = 'downloaded_media_v1';
  static const String _mediaFolderName = 'media';

  /// Get the base directory for storing media files
  /// Uses Downloads directory: /storage/emulated/0/Downloads/NewReward_Media/
  /// This is the most reliable and accessible location
  Future<Directory> getMediaDirectory() async {
    try {
      // Try to use Downloads directory (most accessible)
      final Directory? downloadsDir = await getDownloadsDirectory();

      if (downloadsDir != null) {
        final Directory mediaDir = Directory(
          '${downloadsDir.path}/NewReward_Media',
        );
        if (!await mediaDir.exists()) {
          await mediaDir.create(recursive: true);
          print('✅ Created media directory: ${mediaDir.path}');
        }
        print('📁 Using Downloads: ${mediaDir.path}');
        return mediaDir;
      }
    } catch (e) {
      print('⚠️ Downloads directory not available: $e');
    }

    // Fallback 1: External storage
    try {
      final Directory? appDocDir = await getExternalStorageDirectory();
      if (appDocDir != null) {
        final Directory mediaDir = Directory(
          '${appDocDir.path}/$_mediaFolderName',
        );
        if (!await mediaDir.exists()) {
          await mediaDir.create(recursive: true);
        }
        print('📁 Using external storage: ${mediaDir.path}');
        return mediaDir;
      }
    } catch (e) {
      print('⚠️ External storage not available: $e');
    }

    // Fallback 2: App documents
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final Directory mediaDir = Directory(
        '${appDocDir.path}/$_mediaFolderName',
      );
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }
      print('📁 Using app documents: ${mediaDir.path}');
      return mediaDir;
    } catch (e) {
      print('❌ All storage options failed: $e');
      throw Exception('Unable to get storage directory: $e');
    }
  }

  /// Save raw bytes into a public, user-visible collection using Android MediaStore.
  /// - PDFs go to Downloads
  /// - Images go to Pictures
  /// - Audio goes to Music
  /// Falls back to app directories on non-Android platforms.
  Future<String> saveToPublicStorage({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) async {
    final resolvedMime =
        mimeType ?? lookupMimeType(fileName) ?? 'application/octet-stream';

    if (Platform.isAndroid) {
      final mediaStore = MediaStore();
      try {
        // Initialize once for MediaStore
        await MediaStore.ensureInitialized();
        MediaStore.appFolder = 'NewReward';

        // Write to a temporary file then let MediaStore move it
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = p.join(tmpDir.path, fileName);
        final tmpFile = File(tmpPath);
        await tmpFile.writeAsBytes(bytes, flush: true);

        // Choose correct collection
        DirType dirType = DirType.download;
        DirName dirName = DirName.download;
        if (resolvedMime.startsWith('image/')) {
          dirType = DirType.photo;
          dirName = DirName.pictures;
        } else if (resolvedMime.startsWith('audio/')) {
          dirType = DirType.audio;
          dirName = DirName.music;
        } else if (resolvedMime.startsWith('video/')) {
          dirType = DirType.video;
          dirName = DirName.movies;
        }

        final saveInfo = await mediaStore.saveFile(
          tempFilePath: tmpPath,
          dirType: dirType,
          dirName: dirName,
        );

        if (saveInfo != null) {
          // Try to resolve real file path from returned URI
          final uri = saveInfo.uri.toString();
          final resolvedPath = await mediaStore.getFilePathFromUri(
            uriString: uri,
          );
          final finalPath = resolvedPath ?? uri;
          print('✅ Saved to public storage: $finalPath');
          return finalPath;
        }

        print('⚠️ MediaStore save returned null, falling back to app storage');
      } catch (e) {
        print('❌ MediaStore save failed, falling back: $e');
        // Fall through to non-Android path
      }
    }

    // Non-Android or fallback: save to app-visible media directory
    final dir = await getMediaDirectory();
    final outPath = p.join(dir.path, fileName);
    final file = File(outPath);
    await file.writeAsBytes(bytes, flush: true);
    print('✅ Saved to app storage: $outPath');
    return outPath;
  }

  /// Generate local file path for a given R2 key
  /// Example: "media/1234567/file.pdf" -> "/storage/emulated/0/Downloads/NewReward_Media/media_1234567_file.pdf"
  Future<String> getLocalFilePath(String r2Key) async {
    final mediaDir = await getMediaDirectory();
    // Preserve extension so the file is visible to file managers (e.g., .pdf)
    // and flatten nested paths into a single filename for uniqueness.
    final segments = r2Key.split('/');
    final baseName = segments.isNotEmpty ? segments.removeLast() : r2Key;
    final prefix = segments.isNotEmpty ? '${segments.join('_')}_' : '';
    final sanitizedBase = baseName.replaceAll(' ', '_');
    final fileName = '$prefix$sanitizedBase';

    final fullPath = p.join(mediaDir.path, fileName);
    print('📝 Generated local path for $r2Key: $fullPath');
    return fullPath;
  }

  /// Check if a file exists locally
  Future<bool> fileExists(String localPath) async {
    final file = File(localPath);
    final exists = await file.exists();
    print('${exists ? '✅' : '❌'} File exists check: $localPath = $exists');
    return exists;
  }

  /// Delete a local file
  Future<bool> deleteFile(String localPath) async {
    try {
      final file = File(localPath);
      print('🗑️ Attempting to delete: $localPath');
      if (await file.exists()) {
        await file.delete();
        print('✅ File deleted: $localPath');
        return true;
      }
      print('⚠️ File not found: $localPath');
      return false;
    } catch (e) {
      print('❌ Error deleting file: $e');
      return false;
    }
  }

  /// Get file size
  Future<int> getFileSize(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      print('❌ Error getting file size: $e');
      return 0;
    }
  }

  /// Save downloaded media metadata
  Future<void> saveMediaMetadata(DownloadedMedia media) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getAllMediaMetadata();
      existing[media.key] = media;

      final jsonMap = existing.map(
        (key, value) => MapEntry(key, value.toJson()),
      );

      await prefs.setString(_storageKey, json.encode(jsonMap));
      print('✅ Saved metadata for: ${media.key}');
    } catch (e) {
      print('❌ Error saving media metadata: $e');
    }
  }

  /// Get metadata for a specific media key
  Future<DownloadedMedia?> getMediaMetadata(String key) async {
    try {
      final all = await getAllMediaMetadata();
      return all[key];
    } catch (e) {
      print('❌ Error getting media metadata: $e');
      return null;
    }
  }

  /// Get all downloaded media metadata
  Future<Map<String, DownloadedMedia>> getAllMediaMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        return {};
      }

      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      return jsonMap.map(
        (key, value) => MapEntry(
          key,
          DownloadedMedia.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (e) {
      print('❌ Error loading media metadata: $e');
      return {};
    }
  }

  /// Remove metadata for a specific key
  Future<void> removeMediaMetadata(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getAllMediaMetadata();
      existing.remove(key);

      final jsonMap = existing.map(
        (key, value) => MapEntry(key, value.toJson()),
      );

      await prefs.setString(_storageKey, json.encode(jsonMap));
      print('✅ Removed metadata for: $key');
    } catch (e) {
      print('❌ Error removing media metadata: $e');
    }
  }

  /// Clear all downloaded media (files + metadata)
  Future<void> clearAllMedia() async {
    try {
      // Delete all files
      final mediaDir = await getMediaDirectory();
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }

      // Clear metadata
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);

      print('✅ Cleared all media');
    } catch (e) {
      print('❌ Error clearing all media: $e');
    }
  }

  /// Get total storage used by downloaded media
  Future<int> getTotalStorageUsed() async {
    try {
      final all = await getAllMediaMetadata();
      return all.values.fold<int>(0, (sum, media) => sum + media.fileSize);
    } catch (e) {
      print('❌ Error calculating storage: $e');
      return 0;
    }
  }

  /// Get count of downloaded files
  Future<int> getDownloadedCount() async {
    final all = await getAllMediaMetadata();
    return all.length;
  }

  /// Format storage size for display
  String formatStorageSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
